//
//  InlineSubAgentJobView.swift
//  Axon
//
//  Displays a sub-agent job inline during message streaming.
//  Shows job state (running/success/failure) with expandable detail drawer.
//
//  **Architectural Commandment #5**: The Mercury Pulse.
//  The RUNNING state must feel different from a standard tool call.
//  This is a living process—a Scout out in the field.
//

import SwiftUI

// MARK: - Inline Sub-Agent Job View

/// Displays a sub-agent job inline with state indicator and expandable drawer.
struct InlineSubAgentJobView: View {
    let job: SubAgentJob
    @State private var isExpanded: Bool = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header - always visible
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    // State indicator with Mercury Pulse
                    stateIndicator

                    // Role icon (animated when running)
                    roleIcon

                    // Role name and task preview
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.role.displayName)
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text(truncatedTask)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Status message or duration
                    statusBadge

                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(stateColor.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(stateColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded drawer - job details
            if isExpanded {
                SubAgentJobDrawerContent(job: job)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            if job.state == .running {
                startTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: job.state) { _, newState in
            if newState == .running {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    // MARK: - State Indicator (Mercury Pulse)

    @ViewBuilder
    private var stateIndicator: some View {
        switch job.state {
        case .proposed:
            Circle()
                .fill(AppColors.textTertiary)
                .frame(width: 8, height: 8)

        case .approved:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12))
                .foregroundColor(AppColors.signalMercury)

        case .running:
            // THE MERCURY PULSE - living process indicator
            MercuryPulseIndicator(color: stateColor)

        case .awaitingInput:
            QuestionPulseIndicator()

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalLichen)

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalHematite)

        case .terminated:
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalHematite)

        case .expired:
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textTertiary)

        case .rejected:
            Image(systemName: "xmark.seal.fill")
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalHematite)
        }
    }

    // MARK: - Role Icon (Animated when Running)

    @ViewBuilder
    private var roleIcon: some View {
        if job.state == .running {
            AnimatedRoleIcon(role: job.role, color: stateColor)
        } else {
            Image(systemName: job.role.icon)
                .font(.system(size: 14))
                .foregroundColor(stateColor)
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch job.state {
        case .running:
            // Live elapsed time counter
            HStack(spacing: 4) {
                Text(formatElapsed(elapsedTime))
                    .font(AppTypography.codeSmall())
                    .foregroundColor(AppColors.textTertiary)
                    .monospacedDigit()
            }

        case .awaitingInput:
            HStack(spacing: 4) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 10))
                Text("Needs input")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.signalMercury)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.signalMercury.opacity(0.1))
            .cornerRadius(4)

        case .completed, .failed, .terminated:
            if let duration = job.duration {
                Text(formatDuration(duration))
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - State Color

    private var stateColor: Color {
        switch job.state {
        case .proposed: return AppColors.textTertiary
        case .approved: return AppColors.signalMercury
        case .running: return mercuryColor(for: job.role)
        case .awaitingInput: return AppColors.signalMercury
        case .completed: return AppColors.signalLichen
        case .failed, .terminated: return AppColors.signalHematite
        case .expired, .rejected: return AppColors.textTertiary
        }
    }

    /// Different mercury tints for different roles
    private func mercuryColor(for role: SubAgentRole) -> Color {
        switch role {
        case .scout: return AppColors.signalMercury  // Standard mercury
        case .mechanic: return AppColors.signalLichen.opacity(0.8)  // Greenish tint
        case .designer: return Color.purple.opacity(0.7)  // Purple tint
        }
    }

    // MARK: - Task Preview

    private var truncatedTask: String {
        let maxLength = 50
        if job.task.count <= maxLength {
            return job.task
        }
        // Truncate mid-sentence to show activity
        let truncated = String(job.task.prefix(maxLength))
        return truncated + "..."
    }

    // MARK: - Timer

    private func startTimer() {
        elapsedTime = job.startedAt.map { Date().timeIntervalSince($0) } ?? 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let startedAt = job.startedAt {
                elapsedTime = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Formatting

    private func formatElapsed(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int(duration * 1000))ms"
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
    }

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

// MARK: - Mercury Pulse Indicator

/// The signature "Mercury Pulse" for running sub-agents.
/// A living, breathing indicator that shows a process is active in the field.
struct MercuryPulseIndicator: View {
    let color: Color
    @State private var isPulsing = false
    @State private var ringScale: CGFloat = 0.5

    var body: some View {
        ZStack {
            // Outer expanding ring
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 2)
                .frame(width: 16, height: 16)
                .scaleEffect(ringScale)
                .opacity(isPulsing ? 0 : 0.8)

            // Inner pulsing core
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.2 : 0.9)
                .shadow(color: color.opacity(0.5), radius: isPulsing ? 4 : 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                ringScale = 1.5
            }
        }
    }
}

// MARK: - Question Pulse Indicator

/// Indicator for jobs awaiting input - a gentle question pulse.
struct QuestionPulseIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "questionmark.circle.fill")
            .font(.system(size: 14))
            .foregroundColor(AppColors.signalMercury)
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

// MARK: - Animated Role Icon

/// Role icon with scanning/working animation.
struct AnimatedRoleIcon: View {
    let role: SubAgentRole
    let color: Color
    @State private var rotation: Double = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        Group {
            switch role {
            case .scout:
                // Binoculars scanning left-right
                Image(systemName: "binoculars")
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .offset(x: offset)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            offset = 3
                        }
                    }

            case .mechanic:
                // Wrench rotating
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }

            case .designer:
                // Pencil writing
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .offset(y: offset)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                            offset = -2
                        }
                    }
            }
        }
    }
}

// MARK: - Sub-Agent Jobs List View

/// List of inline sub-agent jobs for display in message bubble.
struct InlineSubAgentJobsView: View {
    let jobs: [SubAgentJob]

    var body: some View {
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(jobs) { job in
                    InlineSubAgentJobView(job: job)
                }
            }
        }
    }
}

// MARK: - Sub-Agent Jobs Badge

/// Compact badge showing sub-agent job count and state.
struct SubAgentJobsBadge: View {
    let jobs: [SubAgentJob]

    private var runningCount: Int {
        jobs.filter { $0.state == .running }.count
    }

    private var awaitingCount: Int {
        jobs.filter { $0.state == .awaitingInput }.count
    }

    private var failureCount: Int {
        jobs.filter { $0.state == .failed || $0.state == .terminated }.count
    }

    private var badgeColor: Color {
        if failureCount > 0 {
            return AppColors.signalHematite
        } else if awaitingCount > 0 {
            return AppColors.signalMercury
        } else if runningCount > 0 {
            return AppColors.signalMercury
        } else {
            return AppColors.signalLichen
        }
    }

    var body: some View {
        if !jobs.isEmpty {
            HStack(spacing: 4) {
                if runningCount > 0 {
                    MercuryPulseIndicator(color: badgeColor)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: failureCount > 0 ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.system(size: 10))
                }
                Text("\(jobs.count)")
                    .font(AppTypography.labelSmall())

                // Show role icons
                ForEach(Array(Set(jobs.map { $0.role })), id: \.self) { role in
                    Image(systemName: role.icon)
                        .font(.system(size: 8))
                }
            }
            .foregroundColor(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // Proposed
            InlineSubAgentJobView(job: SubAgentJob(
                role: .scout,
                task: "Explore the axon-bridge-vscode directory for network errors"
            ))

            // Running Scout
            InlineSubAgentJobView(job: {
                var job = SubAgentJob(
                    role: .scout,
                    task: "Search for API endpoint definitions across the codebase looking for authentication patterns"
                )
                job = job.started()
                job = job.transitioning(to: .running)
                return job
            }())

            // Running Mechanic
            InlineSubAgentJobView(job: {
                var job = SubAgentJob(
                    role: .mechanic,
                    task: "Fix the network error handling in the WebSocket connection manager"
                )
                job = job.started()
                job = job.transitioning(to: .running)
                return job
            }())

            // Awaiting Input
            InlineSubAgentJobView(job: {
                var job = SubAgentJob(
                    role: .designer,
                    task: "Design the implementation approach for adding OAuth support"
                )
                job = job.started()
                job = job.transitioning(to: .awaitingInput, reason: "Need clarification on OAuth provider")
                return job
            }())

            // Completed
            InlineSubAgentJobView(job: {
                var job = SubAgentJob(
                    role: .scout,
                    task: "Find all usages of deprecated API endpoints"
                )
                job = job.started()
                job = job.finished()
                job = job.transitioning(to: .completed)
                return job
            }())

            // Failed
            InlineSubAgentJobView(job: {
                var job = SubAgentJob(
                    role: .mechanic,
                    task: "Update the database schema for user preferences"
                )
                job = job.started()
                job = job.transitioning(to: .failed, reason: "Database connection timeout")
                return job
            }())

            // Badge
            SubAgentJobsBadge(jobs: [
                SubAgentJob(role: .scout, task: "Task 1"),
                {
                    var job = SubAgentJob(role: .mechanic, task: "Task 2")
                    job = job.transitioning(to: .running)
                    return job
                }()
            ])
        }
        .padding()
    }
    .background(AppColors.substratePrimary)
}
