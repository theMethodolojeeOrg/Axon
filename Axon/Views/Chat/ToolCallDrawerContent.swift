//
//  ToolCallDrawerContent.swift
//  Axon
//
//  Expanded drawer showing tool call request and response details.
//  Supports pretty and raw view modes with copy functionality.
//

import SwiftUI

// MARK: - Tool Call Drawer Content

/// Expanded drawer showing tool request and response details
struct ToolCallDrawerContent: View {
    let toolCall: LiveToolCall
    @State private var showRaw: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Format toggle
            HStack {
                Picker("Format", selection: $showRaw) {
                    Text("Pretty").tag(false)
                    Text("Raw").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Spacer()

                // Copy button
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                        Text("Copy")
                            .font(AppTypography.labelSmall())
                    }
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Request section
            if let request = toolCall.request {
                DrawerSection(title: "Request", icon: "arrow.up.circle") {
                    if showRaw {
                        ToolCallCodeBlockView(content: request.rawJSON, language: "json")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Tool", value: request.tool)
                            DetailRow(label: "Query", value: request.query)
                            DetailRow(label: "Time", value: formatTime(request.timestamp))
                        }
                    }
                }
            }

            // Result section
            if let result = toolCall.result {
                DrawerSection(
                    title: result.success ? "Result" : "Error",
                    icon: result.success ? "arrow.down.circle" : "exclamationmark.circle",
                    titleColor: result.success ? AppColors.textPrimary : AppColors.signalHematite
                ) {
                    if showRaw, let rawJSON = result.rawJSON {
                        ToolCallCodeBlockView(content: rawJSON, language: "json")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            // Output or error
                            if result.success {
                                ScrollView {
                                    Text(result.output)
                                        .font(AppTypography.bodySmall())
                                        .foregroundColor(AppColors.textSecondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 300)
                            } else if let error = result.errorMessage {
                                Text(error)
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.signalHematite)
                            }

                            // Sources
                            if let sources = result.sources, !sources.isEmpty {
                                ToolResultSourcesView(sources: sources)
                            }

                            // Memory operation
                            if let memOp = result.memoryOperation {
                                MemoryOperationRow(operation: memOp)
                            }
                        }
                    }
                }
            }

            // Metadata footer
            HStack {
                if let duration = toolCall.duration {
                    Label(formatDuration(duration), systemImage: "clock")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                } else if toolCall.state == .running {
                    HStack(spacing: 4) {
                        PulsingIndicator(color: AppColors.signalMercury)
                        Text(formatElapsed(toolCall.elapsedDuration))
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                Spacer()

                Text(toolCall.id.prefix(8))
                    .font(AppTypography.codeSmall())
                    .foregroundColor(AppColors.textTertiary.opacity(0.5))
            }
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func copyToClipboard() {
        var text = "Tool Call: \(toolCall.displayName)\n"
        text += "State: \(toolCall.state.rawValue)\n"

        if let request = toolCall.request {
            text += "\n--- Request ---\n"
            text += "Tool: \(request.tool)\n"
            text += "Query: \(request.query)\n"
            text += "Raw: \(request.rawJSON)\n"
        }

        if let result = toolCall.result {
            text += "\n--- Result ---\n"
            text += "Success: \(result.success)\n"
            text += "Output: \(result.output)\n"
            if let error = result.errorMessage {
                text += "Error: \(error)\n"
            }
            if let rawJSON = result.rawJSON {
                text += "Raw: \(rawJSON)\n"
            }
        }

        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    // MARK: - Formatting

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int(duration * 1000))ms"
        } else if duration < 60 {
            return String(format: "%.2fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }

    private func formatElapsed(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int(duration * 1000))ms..."
        } else {
            return String(format: "%.1fs...", duration)
        }
    }
}

// MARK: - Drawer Section

private struct DrawerSection<Content: View>: View {
    let title: String
    let icon: String
    var titleColor: Color = AppColors.textPrimary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(AppTypography.labelSmall(.medium))
            }
            .foregroundColor(titleColor)

            content
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 50, alignment: .leading)

            Text(value)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Tool Call Code Block View

private struct ToolCallCodeBlockView: View {
    let content: String
    let language: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(formatJSON(content))
                .font(AppTypography.codeSmall())
                .foregroundColor(AppColors.textSecondary)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(AppColors.substratePrimary)
        .cornerRadius(6)
    }

    private func formatJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return json
        }
        return prettyString
    }
}

// MARK: - Tool Result Sources View

struct ToolResultSourcesView: View {
    let sources: [StreamingToolSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)

            ForEach(sources) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: source.sourceType == .maps ? "map" : "globe")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textTertiary)

                            Text(source.title)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalLichen)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.substratePrimary)
                        .cornerRadius(4)
                    }
                }
            }
        }
    }
}

// MARK: - Memory Operation Row (for drawer)

private struct MemoryOperationRow: View {
    let operation: MessageMemoryOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: operation.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(operation.success ? AppColors.signalLichen : AppColors.signalHematite)

                Text("Memory: \(operation.memoryType.capitalized)")
                    .font(AppTypography.labelSmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("\(Int(operation.confidence * 100))%")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            Text(operation.content)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)

            if !operation.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(operation.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalMercury)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(AppColors.signalMercury.opacity(0.1))
                            .cornerRadius(3)
                    }
                    if operation.tags.count > 3 {
                        Text("+\(operation.tags.count - 3)")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
        }
        .padding(8)
        .background(AppColors.substratePrimary)
        .cornerRadius(6)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            // Success with sources
            ToolCallDrawerContent(toolCall: LiveToolCall(
                name: "google_search",
                displayName: "Web Search",
                icon: "magnifyingglass",
                state: .success,
                request: ToolCallRequest(
                    tool: "google_search",
                    query: "SwiftUI async/await best practices",
                    rawJSON: "{\"tool\": \"google_search\", \"query\": \"SwiftUI async/await best practices\"}"
                ),
                result: ToolCallResult(
                    success: true,
                    output: "Found 5 relevant articles about SwiftUI async/await patterns and best practices for iOS development.",
                    rawJSON: "{\"status\": \"success\", \"results\": 5}",
                    sources: [
                        StreamingToolSource(title: "Swift Concurrency Guide", url: "https://developer.apple.com/swift"),
                        StreamingToolSource(title: "SwiftUI Patterns", url: "https://example.com/swiftui")
                    ],
                    duration: 1.234
                ),
                startedAt: Date().addingTimeInterval(-1.234),
                completedAt: Date()
            ))

            // Running
            ToolCallDrawerContent(toolCall: LiveToolCall(
                name: "code_execution",
                displayName: "Code Execution",
                icon: "terminal",
                state: .running,
                request: ToolCallRequest(
                    tool: "code_execution",
                    query: "Calculate prime numbers up to 1000"
                ),
                startedAt: Date().addingTimeInterval(-2.5),
                statusMessage: "Running code..."
            ))

            // Failed
            ToolCallDrawerContent(toolCall: LiveToolCall(
                name: "url_context",
                displayName: "URL Fetch",
                icon: "link",
                state: .failure,
                request: ToolCallRequest(
                    tool: "url_context",
                    query: "https://example.com/broken-link"
                ),
                result: ToolCallResult(
                    success: false,
                    output: "",
                    duration: 0.5,
                    errorMessage: "HTTP 404: Page not found"
                ),
                startedAt: Date().addingTimeInterval(-0.5),
                completedAt: Date()
            ))
        }
        .padding()
    }
    .background(AppColors.substratePrimary)
}
