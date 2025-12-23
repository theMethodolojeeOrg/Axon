//
//  AssistantMarkdownView.swift
//  Axon
//
//  Renders assistant markdown while replacing fenced code blocks with
//  custom ChatGPT/Claude-like code boxes.
//

import SwiftUI
import MarkdownUI

struct AssistantMarkdownView: View {
    let content: String

    /// Already-executed tool calls from persisted message data.
    /// When provided, tool_request blocks matching these will render as completed
    /// instead of trying to re-execute.
    var executedToolCalls: [LiveToolCall]?

    private var segments: [MarkdownSegment] {
        FencedCodeParser.split(content)
    }

    /// Find an executed tool call matching the given tool request JSON
    private func findExecutedToolCall(for code: String) -> LiveToolCall? {
        guard let executedCalls = executedToolCalls, !executedCalls.isEmpty else {
            return nil
        }

        // Parse the tool request JSON to get tool name and query
        guard let data = code.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String,
              let query = json["query"] as? String else {
            return nil
        }

        // Find a matching executed tool call
        return executedCalls.first { call in
            call.name == tool && call.request?.query == query
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

                case .code(let language, let code):
                    // Special handling for tool_request blocks - show actionable UI
                    if language?.lowercased() == "tool_request" {
                        // Check if this tool was already executed (from persisted message data)
                        if let executedCall = findExecutedToolCall(for: code) {
                            CompletedToolCallView(toolCall: executedCall)
                        } else {
                            ToolRequestCodeBlockView(code: code)
                        }
                    } else {
                        CodeBlockView(language: language, code: code) {
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(AppColors.textPrimary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
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
