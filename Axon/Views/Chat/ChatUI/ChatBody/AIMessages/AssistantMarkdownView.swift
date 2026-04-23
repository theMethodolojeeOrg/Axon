//
//  AssistantMarkdownView.swift
//  Axon
//
//  Renders assistant markdown while replacing fenced code blocks with
//  custom ChatGPT/Claude-like code boxes.
//

import SwiftUI
import MarkdownUI
import AxonArtifacts

struct AssistantMarkdownView: View {
    let content: String

    /// Already-executed tool calls from persisted message data.
    /// When provided, tool_request blocks matching these will render as completed
    /// instead of trying to re-execute.
    var executedToolCalls: [LiveToolCall]?

    /// When true, this content was loaded from conversation history (not newly streamed)
    /// Used to prevent auto-execution of tool requests on app restart
    var isFromHistory: Bool = false
    var conversationId: String? = nil
    var messageId: String? = nil

    private var segments: [MarkdownSegment] {
        FencedCodeParser.split(content)
    }

    // MARK: - Open-fence detection

    /// Detects an unclosed fenced code block at the end of the streaming content.
    /// Returns the language tag (if any) extracted from the opening fence line.
    ///
    /// An open fence looks like:
    ///   ```swift\nsome code...   (no closing ```)
    ///
    /// We only surface this when `isFromHistory == false` (i.e. actively streaming).
    private var openFenceLanguage: String? {
        guard !isFromHistory else { return nil }

        // Count the number of complete fenced blocks already parsed.
        // If the raw content has one more opening fence than closing fences,
        // there is an open (streaming) block at the tail.
        let openingCount = countOpeningFences(in: content)
        let closingCount = countClosingFences(in: content)

        guard openingCount > closingCount else { return nil }

        // Extract the language tag from the last opening fence line.
        return languageFromLastOpenFence(in: content)
    }

    /// Counts ``` opening fence lines (lines that start with ``` followed by optional language).
    private func countOpeningFences(in text: String) -> Int {
        // A line that starts with ``` and is NOT a bare closing fence (``` alone or ``` with only whitespace).
        // We treat any ``` line that has non-whitespace after it as an opening fence.
        // Bare ``` lines are ambiguous — we count them as closing fences.
        let lines = text.components(separatedBy: "\n")
        var count = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                let afterFence = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if !afterFence.isEmpty {
                    // Has a language tag → opening fence
                    count += 1
                }
            }
        }
        return count
    }

    /// Counts bare ``` closing fence lines.
    private func countClosingFences(in text: String) -> Int {
        let lines = text.components(separatedBy: "\n")
        var count = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "```" {
                count += 1
            }
        }
        return count
    }

    /// Extracts the language tag from the last ``` opening fence in the text.
    private func languageFromLastOpenFence(in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                let afterFence = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if !afterFence.isEmpty {
                    // Parse the info string the same way FencedCodeParser does
                    let lang = afterFence.components(separatedBy: ":").first?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return lang?.isEmpty == false ? lang : nil
                }
            }
        }
        return nil
    }

    // MARK: - Workspace bundle

    private var workspaceBundle: ArtifactWorkspace? {
        let workspaceId = messageId.map { "\($0)_bundle" } ?? UUID().uuidString

        return ArtifactWorkspaceAssembler.workspace(
            from: segments,
            workspaceId: workspaceId,
            title: "Code Workspace",
            conversationId: conversationId,
            messageId: messageId,
            sourceItemId: messageId.map { "\($0)_bundle" },
            isEditableFork: false,
            isReadOnlySnapshot: true
        )
    }

    private struct ParsedToolRequest {
        let tool: String
        let query: String
    }

    /// Parse tool request JSON payload from a fenced block.
    private func parseToolRequest(from code: String) -> ParsedToolRequest? {
        guard let data = code.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String,
              let query = json["query"] as? String else {
            return nil
        }
        return ParsedToolRequest(tool: tool, query: query)
    }

    /// Find an executed tool call matching the given tool request JSON
    private func findExecutedToolCall(for code: String) -> LiveToolCall? {
        guard let executedCalls = executedToolCalls, !executedCalls.isEmpty else {
            return nil
        }

        guard let parsed = parseToolRequest(from: code) else {
            return nil
        }

        // Find a matching executed tool call
        return executedCalls.first { call in
            call.name == parsed.tool && call.request?.query == parsed.query
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                switch segment {
                case .markdown(let markdown):
                    Markdown(markdown)
                        .markdownTheme(MarkdownTheme.axon)
                        .textSelection(.enabled)
                        // Prevent parent ScrollView/LazyVStack measurement oddities
                        // (helps avoid clipping/truncation of long assistant messages).
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                case .code(let language, let path, _, let code):
                    // Special handling for tool fences - show actionable UI when JSON is valid.
                    let normalizedLanguage = language?.lowercased()
                    if normalizedLanguage == "tool_request" || normalizedLanguage == "tool" {
                        if let executedCall = findExecutedToolCall(for: code) {
                            CompletedToolCallView(toolCall: executedCall)
                        } else if parseToolRequest(from: code) != nil {
                            // Pass isFromHistory to prevent auto-execution on app restart
                            ToolRequestCodeBlockView(
                                code: code,
                                isFromHistory: isFromHistory,
                                conversationId: conversationId,
                                sourceMessageId: messageId
                            )
                        } else if normalizedLanguage == "tool" {
                            // Compatibility: if a model accidentally wraps normal prose in
                            // ```tool fences, render it as markdown instead of a code box.
                            Markdown(code)
                                .markdownTheme(MarkdownTheme.axon)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                        } else {
                            CodeBlockView(
                                language: language,
                                filePath: path,
                                workspace: path == nil ? nil : workspaceBundle,
                                code: code
                            )
                        }
                    } else {
                        CodeBlockView(
                            language: language,
                            filePath: path,
                            workspace: path == nil ? nil : workspaceBundle,
                            code: code
                        )
                    }
                }
            }

            // Streaming placeholder: shown as soon as the AI opens a fenced block
            // but before the closing fence arrives. Disappears once the block is
            // fully parsed and appears in `segments` above.
            if let streamingLanguage = openFenceLanguage {
                // Extract the partial code that has been streamed so far inside the open fence.
                let partialCode = extractPartialStreamingCode(language: streamingLanguage)
                CodeBlockView(
                    language: streamingLanguage,
                    filePath: nil,
                    workspace: nil,
                    code: partialCode,
                    isStreaming: true
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: openFenceLanguage != nil)
    }

    // MARK: - Partial code extraction

    /// Extracts the code lines that have been streamed so far inside the last open fence.
    private func extractPartialStreamingCode(language: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var inOpenFence = false
        var codeLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inOpenFence {
                if trimmed.hasPrefix("```") && trimmed != "```" {
                    // This is an opening fence — check if it's the last one
                    // (we'll collect from the last opening fence)
                    inOpenFence = true
                    codeLines = []  // reset; we want only the last open block
                }
            } else {
                if trimmed == "```" {
                    // Closing fence — this block is complete, reset
                    inOpenFence = false
                    codeLines = []
                } else {
                    codeLines.append(line)
                }
            }
        }

        // If we're still in an open fence, codeLines holds the partial content
        return inOpenFence ? codeLines.joined(separator: "\n") : ""
    }
}

#Preview {
    ScrollView {
        AssistantMarkdownView(content: """
        Here is some text.

        ```swift
        struct Foo {
            let bar: String
        }
        ```

        More text.
        """)
        .padding()
        .background(AppColors.substratePrimary)
    }
}
