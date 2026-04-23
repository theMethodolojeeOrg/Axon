//
//  SubAgentLiveActivity.swift
//  AxonLiveActivity
//
//  Live Activity UI for sub-agent job monitoring.
//  Implements the Mercury Pulse - a living process indicator for agents in the field.
//
//  **Architectural Commandment #5**: The Mercury Pulse.
//  The RUNNING state must feel different from a standard tool call.
//  This is a living process—a Scout out in the field.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SubAgentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SubAgentActivityAttributes.self) { context in
            // Lock Screen / Notification Center view
            SubAgentLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (when user long-presses)
                DynamicIslandExpandedRegion(.leading) {
                    SubAgentExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SubAgentExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    SubAgentExpandedCenterView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SubAgentExpandedBottomView(context: context)
                }
            } compactLeading: {
                // Compact leading (left side of pill) - Role icon with pulse
                SubAgentCompactLeadingView(context: context)
            } compactTrailing: {
                // Compact trailing (right side of pill) - Elapsed time
                SubAgentCompactTrailingView(context: context)
            } minimal: {
                // Minimal view (when sharing space with other activities)
                SubAgentMinimalView(context: context)
            }
        }
    }
}

// MARK: - Lock Screen View

struct SubAgentLockScreenView: View {
    let context: ActivityViewContext<SubAgentActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with role and state
            HStack(spacing: 10) {
                // Role icon with Mercury Pulse
                ZStack {
                    if context.state.state.isPulsing {
                        // Outer pulse ring
                        Circle()
                            .stroke(roleColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 36, height: 36)
                            .scaleEffect(1.2)

                        Circle()
                            .stroke(roleColor.opacity(0.2), lineWidth: 1)
                            .frame(width: 44, height: 44)
                            .scaleEffect(1.4)
                    }

                    Image(systemName: context.attributes.role.icon)
                        .font(.title2)
                        .foregroundStyle(roleColor)
                        .symbolEffect(.pulse, isActive: context.state.state.isPulsing)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(context.attributes.role.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        // State badge
                        Text(context.state.state.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(stateColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(stateColor.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    // Status message or default verb
                    Text(context.state.statusMessage ?? "\(context.attributes.role.verb)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Elapsed time
                if let startedAt = context.state.startedAt {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(startedAt, style: .timer)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .monospacedDigit()

                        if let progress = context.state.progress {
                            Text(progress.percentString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Task preview
            Text(context.attributes.taskPreview)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            // Progress bar (if available)
            if let progress = context.state.progress {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 4)

                            Capsule()
                                .fill(roleColor)
                                .frame(width: geo.size.width * progress.fraction, height: 4)
                        }
                    }
                    .frame(height: 4)

                    if let label = progress.label {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Context tags
            if !context.attributes.contextTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(context.attributes.contextTags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            // Footer: Model info
            HStack {
                if let provider = context.state.provider, let model = context.state.model {
                    Text("\(provider) • \(model)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("Axon")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.85))
    }

    private var roleColor: Color {
        switch context.attributes.role {
        case .scout: return .cyan
        case .mechanic: return .green
        case .designer: return .purple
        case .namer: return .orange
        }
    }

    private var stateColor: Color {
        switch context.state.state {
        case .proposed: return .gray
        case .approved: return .cyan
        case .running: return roleColor
        case .awaitingInput: return .orange
        case .completed: return .green
        case .failed, .terminated: return .red
        }
    }
}

// MARK: - Dynamic Island Compact Views

struct SubAgentCompactLeadingView: View {
    let context: ActivityViewContext<SubAgentActivityAttributes>

    var body: some View {
        Image(systemName: context.attributes.role.icon)
            .font(.system(size: 14))
            .foregroundStyle(roleColor)
            .symbolEffect(.pulse, isActive: context.state.state.isPulsing)
    }

    private var roleColor: Color {
        switch context.attributes.role {
        case .scout: return .cyan
        case .mechanic: return .green
        case .designer: return .purple
        case .namer: return .orange
        }
    }
}

struct SubAgentCompactTrailingView: View {
    let context: ActivityViewContext<SubAgentActivityAttributes>

    var body: some View {
        if context.state.state == .running, let startedAt = context.state.startedAt {
            Text(startedAt, style: .timer)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else if context.state.state == .awaitingInput {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        } else if context.state.state.isTerminal {
            Image(systemName: context.state.state.icon)
                .font(.system(size: 12))
                .foregroundStyle(context.state.state == .completed ? .green : .red)
        }
    }
}

struct SubAgentMinimalView: View {
    let context: ActivityViewContext<SubAgentActivityAttributes>

    var body: some View {
        Image(systemName: context.attributes.role.icon)
            .font(.system(size: 12))
            .foregroundStyle(roleColor)
            .symbolEffect(.pulse, isActive: context.state.state.isPulsing)
    }

    private var roleColor: Color {
        switch context.attributes.role {
        case .scout: return .cyan
        case .mechanic: return .green
        case .designer: return .purple
        case .namer: return .orange
        }
    }
}

// MARK: - Dynamic Island Expanded Views

struct SubAgentExpandedLeadingView: View {
    let context: ActivityViewContext<SubAgentActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Role icon with pulse
            ZStack {
                if context.state.state.isPulsing {
                    Circle()
                        .stroke(roleColor.opacity(0.3), lineWidth: 1)
                        .frame(width: 28, height: 28)
                }

                Image(systemName: context.attributes.role.icon)
                    .font(.title2)
                    .foregroundStyle(roleColor)
                    .symbolEffect(.pulse, isActive: context.state.state.isPulsing)
            }

            Text(context.attributes.role.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var roleColor: Color {
        switch context.attributes.role {
        case .scout: return .cyan
        case .mechanic: return .green
        case .designer: return .purple
        case .namer: return .orange
        }
    }
}

struct SubAgentExpandedTrailingView: View {
    let context: ActivityViewContext<SubAgentActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // State
            Text(context.state.state.displayName)
                .font(.caption)
                .foregroundStyle(stateColor)

            // Elapsed time
            if let startedAt = context.state.startedAt {
                Text(startedAt, style: .timer)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
    }

    private var stateColor: Color {
        switch context.state.state {
        case .proposed: return .gray
        case .approved: return .cyan
        case .running: return .green
        case .awaitingInput: return .orange
        case .completed: return .green
        case .failed, .terminated: return .red
        }
    }
}

struct SubAgentExpandedCenterView: View {
    let context: ActivityViewContext<SubAgentActivityAttributes>

    var body: some View {
        VStack(spacing: 2) {
            Text("Sub-Agent")
                .font(.headline)
                .foregroundStyle(.primary)

            if let provider = context.state.provider {
                Text(provider)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SubAgentExpandedBottomView: View {
    let context: ActivityViewContext<SubAgentActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Task preview
            Text(context.attributes.taskPreview)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)

            // Progress or status
            if let progress = context.state.progress {
                HStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 3)

                            Capsule()
                                .fill(roleColor)
                                .frame(width: geo.size.width * progress.fraction, height: 3)
                        }
                    }
                    .frame(height: 3)

                    Text(progress.percentString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if context.state.state == .awaitingInput {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.bubble")
                        .font(.caption)
                    Text("Needs your input")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            } else if context.state.state == .running {
                HStack(spacing: 4) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                    Text(context.state.statusMessage ?? "\(context.attributes.role.verb)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Context tags
            if !context.attributes.contextTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(context.attributes.contextTags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var roleColor: Color {
        switch context.attributes.role {
        case .scout: return .cyan
        case .mechanic: return .green
        case .designer: return .purple
        case .namer: return .orange
        }
    }
}

// MARK: - Preview Provider

#Preview("Lock Screen - Scout Running", as: .content, using: SubAgentActivityAttributes(
    jobId: "job-123",
    role: .scout,
    taskPreview: "Explore axon-bridge-vscode directory for network-related error handling patterns",
    contextTags: ["VSIX", "NetworkPatterns"]
)) {
    SubAgentLiveActivity()
} contentStates: {
    SubAgentActivityAttributes.ContentState(
        state: .running,
        startedAt: Date().addingTimeInterval(-42),
        elapsedSeconds: 42,
        progress: nil,
        statusMessage: "Scanning files...",
        provider: "xAI",
        model: "grok-4-fast"
    )
}

#Preview("Lock Screen - Mechanic with Progress", as: .content, using: SubAgentActivityAttributes(
    jobId: "job-456",
    role: .mechanic,
    taskPreview: "Fix network error handling in WebSocket connection manager",
    contextTags: ["WebSocket", "ErrorHandling"]
)) {
    SubAgentLiveActivity()
} contentStates: {
    SubAgentActivityAttributes.ContentState(
        state: .running,
        startedAt: Date().addingTimeInterval(-120),
        elapsedSeconds: 120,
        progress: SubAgentProgress(current: 3, total: 5, label: "3 of 5 files"),
        statusMessage: "Applying fixes...",
        provider: "Anthropic",
        model: "claude-sonnet"
    )
}

#Preview("Lock Screen - Designer Awaiting Input", as: .content, using: SubAgentActivityAttributes(
    jobId: "job-789",
    role: .designer,
    taskPreview: "Design implementation approach for OAuth 2.0 support",
    contextTags: ["OAuth", "Architecture"]
)) {
    SubAgentLiveActivity()
} contentStates: {
    SubAgentActivityAttributes.ContentState(
        state: .awaitingInput,
        startedAt: Date().addingTimeInterval(-90),
        elapsedSeconds: 90,
        progress: nil,
        statusMessage: "Which OAuth provider should we prioritize?",
        provider: "Google",
        model: "gemini-2.5-pro"
    )
}

#Preview("Lock Screen - Completed", as: .content, using: SubAgentActivityAttributes(
    jobId: "job-completed",
    role: .scout,
    taskPreview: "Find all usages of deprecated API endpoints",
    contextTags: ["API", "Deprecation"]
)) {
    SubAgentLiveActivity()
} contentStates: {
    SubAgentActivityAttributes.ContentState(
        state: .completed,
        startedAt: Date().addingTimeInterval(-180),
        elapsedSeconds: 180,
        progress: SubAgentProgress(current: 12, total: 12, label: "12 files analyzed"),
        statusMessage: "Found 3 deprecated endpoints",
        provider: "Anthropic",
        model: "claude-haiku"
    )
}
