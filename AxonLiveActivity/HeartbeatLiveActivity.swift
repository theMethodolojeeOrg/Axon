//
//  HeartbeatLiveActivity.swift
//  AxonLiveActivity
//
//  Live Activity UI for heartbeat monitoring.
//

import ActivityKit
import WidgetKit
import Combine
import SwiftUI

// MARK: - Flipping Icon View

/// An animated icon that flips between the status/mood icon and Axon logo
/// The flip is a 3D rotation around the Y-axis (spinning "backward" in 3D)
struct FlippingIconView: View {
    let iconName: String
    let iconColor: Color
    let fontSize: Font
    let iconSize: CGFloat
    let isRunning: Bool

    // Animation timing: 10 seconds on icon, 0.8 second flip (0.4s each half), brief logo display, flip back
    private let displayDuration: Double = 10.0
    private let flipDuration: Double = 0.4  // Half of total flip time (0.8s total)

    var body: some View {
        // Use TimelineView to drive the animation cycle
        TimelineView(.periodic(from: .now, by: 0.05)) { timeline in
            let phase = calculatePhase(at: timeline.date)

            ZStack {
                // Status/Mood Icon
                Image(systemName: iconName)
                    .font(fontSize)
                    .foregroundStyle(iconColor)
                    .symbolEffect(.pulse, isActive: isRunning)
                    .opacity(phase.showIcon ? 1 : 0)
                    .rotation3DEffect(
                        .degrees(phase.iconRotation),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )

                // Axon Logo (template image, colored to match)
                Image("AxonLogoTemplate")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(iconColor)
                    .opacity(phase.showLogo ? 1 : 0)
                    .rotation3DEffect(
                        .degrees(phase.logoRotation),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )
            }
        }
    }

    private struct AnimationPhase {
        var showIcon: Bool
        var showLogo: Bool
        var iconRotation: Double
        var logoRotation: Double
    }

    private func calculatePhase(at date: Date) -> AnimationPhase {
        // Total cycle: 10s icon + 0.4s flip out + 0.4s flip in + 1s logo + 0.4s flip out + 0.4s flip in = ~12.6s
        let logoDuration: Double = 1.0
        let cycleDuration = displayDuration + flipDuration * 4 + logoDuration
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)

        if elapsed < displayDuration {
            // Phase 1: Showing icon (0 - 10s)
            return AnimationPhase(showIcon: true, showLogo: false, iconRotation: 0, logoRotation: -90)
        } else if elapsed < displayDuration + flipDuration {
            // Phase 2: Flipping icon away (10s - 10.4s)
            let flipProgress = (elapsed - displayDuration) / flipDuration
            let rotation = flipProgress * 90  // 0 -> 90 degrees (spinning backward/away)
            return AnimationPhase(showIcon: true, showLogo: false, iconRotation: rotation, logoRotation: -90)
        } else if elapsed < displayDuration + flipDuration * 2 {
            // Phase 3: Flipping logo in (10.4s - 10.8s)
            let flipProgress = (elapsed - displayDuration - flipDuration) / flipDuration
            let rotation = -90 + flipProgress * 90  // -90 -> 0 degrees
            return AnimationPhase(showIcon: false, showLogo: true, iconRotation: 90, logoRotation: rotation)
        } else if elapsed < displayDuration + flipDuration * 2 + logoDuration {
            // Phase 4: Showing logo (10.8s - 11.8s)
            return AnimationPhase(showIcon: false, showLogo: true, iconRotation: 90, logoRotation: 0)
        } else if elapsed < displayDuration + flipDuration * 3 + logoDuration {
            // Phase 5: Flipping logo away (11.8s - 12.2s)
            let flipProgress = (elapsed - displayDuration - flipDuration * 2 - logoDuration) / flipDuration
            let rotation = flipProgress * 90  // 0 -> 90 degrees
            return AnimationPhase(showIcon: false, showLogo: true, iconRotation: -90, logoRotation: rotation)
        } else {
            // Phase 6: Flipping icon back in (12.2s - 12.6s)
            let flipProgress = (elapsed - displayDuration - flipDuration * 3 - logoDuration) / flipDuration
            let rotation = -90 + flipProgress * 90  // -90 -> 0 degrees
            return AnimationPhase(showIcon: true, showLogo: false, iconRotation: rotation, logoRotation: 90)
        }
    }
}

/// Convenience initializer with size presets
extension FlippingIconView {
    enum IconSize {
        case compact      // Dynamic Island compact (14pt)
        case minimal      // Dynamic Island minimal (12pt)
        case standard     // Lock screen header (title2 ~22pt)
        case expanded     // Dynamic Island expanded (title2)

        var font: Font {
            switch self {
            case .compact: return .system(size: 14)
            case .minimal: return .system(size: 12)
            case .standard, .expanded: return .title2
            }
        }

        var imageSize: CGFloat {
            switch self {
            case .compact: return 14
            case .minimal: return 12
            case .standard, .expanded: return 22
            }
        }
    }

    init(iconName: String, iconColor: Color, size: IconSize, isRunning: Bool = false) {
        self.iconName = iconName
        self.iconColor = iconColor
        self.fontSize = size.font
        self.iconSize = size.imageSize
        self.isRunning = isRunning
    }
}

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
        VStack(alignment: .leading, spacing: 10) {
            // Header with animated flipping icon
            HStack(spacing: 10) {
                // Animated icon that flips between mood/status icon and Axon logo
                FlippingIconView(
                    iconName: context.state.moodIcon?.sfSymbolName ?? context.state.status.iconName,
                    iconColor: context.state.moodIcon.map { moodColor(for: $0) } ?? statusColor,
                    size: .standard,
                    isRunning: context.state.status == .running
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Axon")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    // Mood reason or status
                    if let reason = context.state.moodReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(context.state.status.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Status indicator
                if context.state.status == .running {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else if context.state.status == .idle, let nextRun = context.state.nextRunTime {
                    // Small countdown in header
                    Text(nextRun, style: .timer)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Entry summary with kind badge
            if let summary = context.state.entrySummary {
                HStack(alignment: .top, spacing: 8) {
                    if let kind = context.state.entryKind {
                        Text(kind.capitalized)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.8))
                            .clipShape(Capsule())
                    }

                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            } else if context.state.status == .idle {
                Text("Waiting for next heartbeat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            // Progressive Loading Bar (Animated)
            if let nextRun = context.state.nextRunTime, context.state.status == .idle {
                ProgressiveLoadingBar(
                    targetDate: nextRun,
                    intervalSeconds: context.attributes.intervalSeconds
                )
                .frame(height: 6)
                .padding(.vertical, 4)
            }

            // Tags row
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

            // Footer: last run time + next run countdown
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

                // Profile name
                Text(context.attributes.profileName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Error message if present
            if let error = context.state.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.85))
    }

    private var statusColor: Color {
        switch context.state.status {
        case .idle: return AppColors.signalLichen
        case .running: return .green
        case .quietHours: return .purple
        case .disabled: return .gray
        case .error: return .red
        }
    }

    private func moodColor(for mood: HeartbeatMoodIcon) -> Color {
        switch mood {
        case .thinking, .lightbulb, .sparkles: return .yellow
        case .happy, .peaceful: return .green
        case .curious, .searching: return .cyan
        case .focused, .reading, .writing: return .blue
        case .energetic: return .orange
        case .organizing, .connecting: return .indigo
        case .waiting, .sunrise, .sunset, .night: return .purple
        case .wave, .heart, .star, .compass: return .pink
        }
    }
}

// MARK: - Progressive Loading Bar

struct ProgressiveLoadingBar: View {
    let targetDate: Date
    let intervalSeconds: Int
    
    @State private var stripeOffset: CGFloat = 0
    
    var body: some View {
        // Drive updates periodically to refresh progress and stripe animation.
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            let _ = timeline.date // force usage to keep the timeline active
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    // Progress fill (signalLichenDark)
                    Capsule()
                        .fill(AppColors.signalLichenDark)
                        .frame(width: geo.size.width * calculateProgress(at: Date()))
                        .overlay(
                            // Animated stripes (signalLichenLight)
                            stripePattern
                                .offset(x: stripeOffset)
                                .mask(Capsule())
                        )
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                stripeOffset = 40 // Match the pattern repeat width
            }
        }
    }
    
    private var stripePattern: some View {
        HStack(spacing: 0) {
            ForEach(0..<20, id: \.self) { _ in
                Rectangle()
                    .fill(AppColors.signalLichenLight.opacity(0.3))
                    .frame(width: 20)
                    .skewed()
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20)
            }
        }
    }
    
    private func calculateProgress(at now: Date) -> Double {
        let total = Double(intervalSeconds)
        let remaining = targetDate.timeIntervalSince(now)
        let elapsed = total - remaining
        return max(0, min(1, elapsed / total))
    }
}

extension View {
    func skewed() -> some View {
        self
            .rotationEffect(.degrees(-15))
            .scaleEffect(x: 1.3, y: 1.0)
    }
}

// MARK: - Countdown View (Legacy/Header)

struct CountdownView: View {
    let targetDate: Date
    let intervalSeconds: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            // Countdown timer
            Text(targetDate, style: .timer)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .monospacedDigit()

            // Progress indicator (visual bar)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 3)

                    Capsule()
                        .fill(Color.cyan)
                        .frame(width: progressWidth(in: geo.size.width), height: 3)
                }
            }
            .frame(width: 50, height: 3)
        }
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        let now = Date()
        let total = Double(intervalSeconds)
        let remaining = targetDate.timeIntervalSince(now)
        let elapsed = total - remaining
        let progress = max(0, min(1, elapsed / total))
        return CGFloat(progress) * totalWidth
    }
}

// MARK: - Dynamic Island Compact Views

struct CompactLeadingView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        // Animated icon that flips between mood/status icon and Axon logo
        FlippingIconView(
            iconName: context.state.moodIcon?.sfSymbolName ?? context.state.status.iconName,
            iconColor: context.state.moodIcon.map { moodColor(for: $0) } ?? statusColor,
            size: .compact,
            isRunning: context.state.status == .running
        )
    }

    private var statusColor: Color {
        switch context.state.status {
        case .idle: return .cyan
        case .running: return .green
        case .quietHours: return .purple
        case .disabled: return .gray
        case .error: return .red
        }
    }

    private func moodColor(for mood: HeartbeatMoodIcon) -> Color {
        switch mood {
        case .thinking, .lightbulb, .sparkles: return .yellow
        case .happy, .peaceful: return .green
        case .curious, .searching: return .cyan
        case .focused, .reading, .writing: return .blue
        case .energetic: return .orange
        case .organizing, .connecting: return .indigo
        case .waiting, .sunrise, .sunset, .night: return .purple
        case .wave, .heart, .star, .compass: return .pink
        }
    }
}

struct CompactTrailingView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        if context.state.status == .running {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.6)
        } else if let nextRun = context.state.nextRunTime {
            // Show countdown to next heartbeat
            Text(nextRun, style: .timer)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
        // Animated icon that flips between mood/status icon and Axon logo
        FlippingIconView(
            iconName: context.state.moodIcon?.sfSymbolName ?? context.state.status.iconName,
            iconColor: context.state.moodIcon.map { moodColor(for: $0) } ?? statusColor,
            size: .minimal,
            isRunning: context.state.status == .running
        )
    }

    private var statusColor: Color {
        switch context.state.status {
        case .idle: return .cyan
        case .running: return .green
        case .quietHours: return .purple
        case .disabled: return .gray
        case .error: return .red
        }
    }

    private func moodColor(for mood: HeartbeatMoodIcon) -> Color {
        switch mood {
        case .thinking, .lightbulb, .sparkles: return .yellow
        case .happy, .peaceful: return .green
        case .curious, .searching: return .cyan
        case .focused, .reading, .writing: return .blue
        case .energetic: return .orange
        case .organizing, .connecting: return .indigo
        case .waiting, .sunrise, .sunset, .night: return .purple
        case .wave, .heart, .star, .compass: return .pink
        }
    }
}

// MARK: - Dynamic Island Expanded Views

struct ExpandedLeadingView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Animated icon that flips between mood/status icon and Axon logo
            FlippingIconView(
                iconName: context.state.moodIcon?.sfSymbolName ?? context.state.status.iconName,
                iconColor: context.state.moodIcon.map { moodColor(for: $0) } ?? statusColor,
                size: .expanded,
                isRunning: context.state.status == .running
            )

            if let reason = context.state.moodReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var statusColor: Color {
        switch context.state.status {
        case .idle: return .cyan
        case .running: return .green
        case .quietHours: return .purple
        case .disabled: return .gray
        case .error: return .red
        }
    }

    private func moodColor(for mood: HeartbeatMoodIcon) -> Color {
        switch mood {
        case .thinking, .lightbulb, .sparkles: return .yellow
        case .happy, .peaceful: return .green
        case .curious, .searching: return .cyan
        case .focused, .reading, .writing: return .blue
        case .energetic: return .orange
        case .organizing, .connecting: return .indigo
        case .waiting, .sunrise, .sunset, .night: return .purple
        case .wave, .heart, .star, .compass: return .pink
        }
    }
}

struct ExpandedTrailingView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(context.state.status.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let nextRun = context.state.nextRunTime {
                Text(nextRun, style: .timer)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
    }
}

struct ExpandedCenterView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        VStack(spacing: 2) {
            Text("Axon")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(context.attributes.profileName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ExpandedBottomView: View {
    let context: ActivityViewContext<HeartbeatActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Entry summary
            if let summary = context.state.entrySummary {
                HStack(alignment: .top, spacing: 6) {
                    if let kind = context.state.entryKind {
                        Text(kind.capitalized)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.cyan)
                    }
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            } else if context.state.status == .running {
                HStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            } else if context.state.status == .quietHours {
                Text("Paused during quiet hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting for next heartbeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Tags
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

#Preview("Lock Screen", as: .dynamicIsland(.expanded), using: HeartbeatActivityAttributes(
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
        errorMessage: nil,
        moodIcon: .sparkles,
        moodReason: "Feeling inspired"
    )
    HeartbeatActivityAttributes.ContentState(
        status: .running,
        lastRunTime: Date().addingTimeInterval(-300),
        nextRunTime: nil,
        entrySummary: nil,
        entryKind: nil,
        entryTags: [],
        errorMessage: nil,
        moodIcon: .thinking,
        moodReason: nil
    )
    HeartbeatActivityAttributes.ContentState(
        status: .idle,
        lastRunTime: Date().addingTimeInterval(-600),
        nextRunTime: Date().addingTimeInterval(3000),
        entrySummary: "Organized some thoughts about the project structure.",
        entryKind: "note",
        entryTags: ["planning"],
        errorMessage: nil,
        moodIcon: .organizing,
        moodReason: "Getting things in order"
    )
    HeartbeatActivityAttributes.ContentState(
        status: .quietHours,
        lastRunTime: Date().addingTimeInterval(-7200),
        nextRunTime: Date().addingTimeInterval(14400),
        entrySummary: "Last thought before quiet hours.",
        entryKind: "note",
        entryTags: ["evening"],
        errorMessage: nil,
        moodIcon: .night,
        moodReason: "Winding down"
    )
}

