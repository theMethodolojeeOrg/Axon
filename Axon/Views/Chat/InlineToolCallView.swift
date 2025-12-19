//
//  InlineToolCallView.swift
//  Axon
//
//  Displays a tool call inline during message streaming.
//  Shows tool state (running/success/failure) with expandable detail drawer.
//

import SwiftUI

// MARK: - Inline Tool Call View

/// Displays a tool call inline during streaming with state indicator and expandable drawer
struct InlineToolCallView: View {
    let toolCall: LiveToolCall
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header - always visible
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    // State indicator
                    stateIndicator

                    // Tool icon
                    Image(systemName: toolCall.icon)
                        .font(.system(size: 14))
                        .foregroundColor(stateColor)

                    // Tool name
                    Text(toolCall.displayName)
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    // Status message or duration
                    if toolCall.state == .running {
                        Text(toolCall.statusMessage ?? "Running...")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    } else if let duration = toolCall.duration {
                        Text(formatDuration(duration))
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()

                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(stateColor.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded drawer - request/response details
            if isExpanded {
                ToolCallDrawerContent(toolCall: toolCall)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        switch toolCall.state {
        case .pending:
            Circle()
                .fill(AppColors.textTertiary)
                .frame(width: 8, height: 8)

        case .running:
            PulsingIndicator(color: AppColors.signalMercury)

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalLichen)

        case .failure:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalHematite)
        }
    }

    // MARK: - State Color

    private var stateColor: Color {
        switch toolCall.state {
        case .pending: return AppColors.textTertiary
        case .running: return AppColors.signalMercury
        case .success: return AppColors.signalLichen
        case .failure: return AppColors.signalHematite
        }
    }

    // MARK: - Duration Formatting

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int(duration * 1000))ms"
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Pulsing Indicator

/// Animated pulsing indicator for running state
struct PulsingIndicator: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Compact Tool Call Badge

/// Compact badge showing tool call count and state
struct ToolCallsBadge: View {
    let toolCalls: [LiveToolCall]

    private var runningCount: Int {
        toolCalls.filter { $0.state == .running }.count
    }

    private var failureCount: Int {
        toolCalls.filter { $0.state == .failure }.count
    }

    private var badgeColor: Color {
        if failureCount > 0 {
            return AppColors.signalHematite
        } else if runningCount > 0 {
            return AppColors.signalMercury
        } else {
            return AppColors.signalLichen
        }
    }

    var body: some View {
        if !toolCalls.isEmpty {
            HStack(spacing: 4) {
                if runningCount > 0 {
                    PulsingIndicator(color: badgeColor)
                } else {
                    Image(systemName: failureCount > 0 ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(size: 10))
                }
                Text("\(toolCalls.count)")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Tool Calls List View

/// List of inline tool calls for display in message bubble
struct InlineToolCallsView: View {
    let toolCalls: [LiveToolCall]

    var body: some View {
        if !toolCalls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(toolCalls) { toolCall in
                    InlineToolCallView(toolCall: toolCall)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Running tool
        InlineToolCallView(toolCall: LiveToolCall(
            name: "google_search",
            displayName: "Web Search",
            icon: "magnifyingglass",
            state: .running,
            request: ToolCallRequest(tool: "google_search", query: "latest iOS 18 features"),
            statusMessage: "Searching the web..."
        ))

        // Success tool
        InlineToolCallView(toolCall: LiveToolCall(
            name: "code_execution",
            displayName: "Code Execution",
            icon: "terminal",
            state: .success,
            request: ToolCallRequest(tool: "code_execution", query: "Calculate fibonacci(10)"),
            result: ToolCallResult(
                success: true,
                output: "Result: 55",
                duration: 1.234
            ),
            completedAt: Date()
        ))

        // Failed tool
        InlineToolCallView(toolCall: LiveToolCall(
            name: "url_context",
            displayName: "URL Fetch",
            icon: "link",
            state: .failure,
            request: ToolCallRequest(tool: "url_context", query: "https://example.com/page"),
            result: ToolCallResult(
                success: false,
                output: "",
                duration: 0.5,
                errorMessage: "Failed to fetch URL: 404 Not Found"
            ),
            completedAt: Date()
        ))

        // Badge
        ToolCallsBadge(toolCalls: [
            LiveToolCall(name: "google_search", displayName: "Search", icon: "magnifyingglass", state: .success),
            LiveToolCall(name: "code_execution", displayName: "Code", icon: "terminal", state: .running)
        ])
    }
    .padding()
    .background(AppColors.substratePrimary)
}
