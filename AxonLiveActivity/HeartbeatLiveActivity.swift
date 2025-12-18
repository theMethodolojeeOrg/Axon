//
//  HeartbeatLiveActivity.swift
//  AxonLiveActivity
//
//  Live Activity UI for heartbeat monitoring.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct HeartbeatLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeartbeatActivityAttributes.self) { context in
            // Lock Screen / Notification Center view
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (when user long-presses)
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                // Compact leading (left side of pill)
                CompactLeadingView(context: context)
            } compactTrailing: {
                // Compact trailing (right side of pill)
                CompactTrailingView(context: context)
            } minimal: {
                // Minimal view (when sharing space with other activities)
                MinimalView(context: context)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: context.state.status.iconName)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: context.state.status == .running)

                Text("Axon Heartbeat")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(context.state.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.2))
                    .clipShape(Capsule())
            }

            // Entry summary
            if let summary = context.state.entrySummary {
                VStack(alignment: .leading, spacing: 4) {
                    if let kind = context.state.entryKind {
                        Text(kind.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }

            // Tags
            if !context.state.entryTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(context.state.entryTags, id: \.self) { tag in
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

            // Footer with timing info
            HStack {
                if let lastRun = context.state.lastRunTime {
                    Label {
                        Text(lastRun, style: .relative)
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if let nextRun = context.state.nextRunTime {
                    Label {
                        Text("Next: \(nextRun, style: .relative)")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // Error message if present
            if let error = context.state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.8))
    }

    private var statusColor: Color {
        switch context.state.status {
        case .idle: return .gray
        case .running: return .green
        case .quietHours: return .purple
        case .disabled: return .gray
        case .error: return .red
        }
    }
}

// MARK: - Dynamic Island Compact Views

struct CompactLeadingView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        Image(systemName: context.state.status.iconName)
            .font(.system(size: 16))
            .foregroundStyle(statusColor)
            .symbolEffect(.pulse, isActive: context.state.status == .running)
    }

    private var statusColor: Color {
        switch context.state.status {
        case .idle: return .gray
        case .running: return .green
        case .quietHours: return .purple
        case .disabled: return .gray
        case .error: return .red
        }
    }
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        if context.state.status == .running {
            Text("...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let lastRun = context.state.lastRunTime {
            Text(lastRun, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct MinimalView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        Image(systemName: context.state.status.iconName)
            .font(.system(size: 14))
            .foregroundStyle(statusColor)
            .symbolEffect(.pulse, isActive: context.state.status == .running)
    }

    private var statusColor: Color {
        switch context.state.status {
        case .idle: return .gray
        case .running: return .green
        case .quietHours: return .purple
        case .disabled: return .gray
        case .error: return .red
        }
    }
}

// MARK: - Dynamic Island Expanded Views

struct ExpandedLeadingView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        VStack(alignment: .leading) {
            Image(systemName: context.state.status.iconName)
                .font(.title2)
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, isActive: context.state.status == .running)
        }
    }

    private var statusColor: Color {
        switch context.state.status {
        case .idle: return .gray
        case .running: return .green
        case .quietHours: return .purple
        case .disabled: return .gray
        case .error: return .red
        }
    }
}

struct ExpandedTrailingView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing) {
            Text(context.state.status.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let nextRun = context.state.nextRunTime {
                Text(nextRun, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

struct ExpandedCenterView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        VStack {
            Text("Axon")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(context.attributes.profileName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ExpandedBottomView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let summary = context.state.entrySummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            } else if context.state.status == .running {
                Text("Thinking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else if context.state.status == .quietHours {
                Text("Paused during quiet hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting for next heartbeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !context.state.entryTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(context.state.entryTags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Preview Provider

#Preview("Lock Screen", as: .content, using: HeartbeatActivityAttributes(
    profileName: "Balanced",
    intervalSeconds: 3600
)) {
    HeartbeatLiveActivity()
} contentStates: {
    HeartbeatActivityAttributes.ContentState(
        status: .idle,
        lastRunTime: Date().addingTimeInterval(-300),
        nextRunTime: Date().addingTimeInterval(3300),
        entrySummary: "Reflected on the day's progress. User seems focused on the Live Activity feature.",
        entryKind: "self_reflection",
        entryTags: ["productivity", "focus"],
        errorMessage: nil
    )
    HeartbeatActivityAttributes.ContentState(
        status: .running,
        lastRunTime: Date().addingTimeInterval(-300),
        nextRunTime: nil,
        entrySummary: nil,
        entryKind: nil,
        entryTags: [],
        errorMessage: nil
    )
    HeartbeatActivityAttributes.ContentState(
        status: .quietHours,
        lastRunTime: Date().addingTimeInterval(-7200),
        nextRunTime: Date().addingTimeInterval(14400),
        entrySummary: "Last thought before quiet hours.",
        entryKind: "note",
        entryTags: ["evening"],
        errorMessage: nil
    )
}
