//
//  LiveActivityService.swift
//  Axon
//
//  Manages Live Activity lifecycle for heartbeat monitoring.
//

import Foundation
import ActivityKit
import Combine

@MainActor
final class LiveActivityService: ObservableObject {
    static let shared = LiveActivityService()

    #if os(iOS)
    @Published private(set) var currentActivity: Activity<HeartbeatActivityAttributes>?
    @Published private(set) var subAgentActivities: [String: Activity<SubAgentActivityAttributes>] = [:]
    @Published private(set) var authorizationStatus: ActivityAuthorizationInfo? = nil
    #endif
    @Published private(set) var isSupported: Bool = false

    private let settingsViewModel = SettingsViewModel.shared

    private init() {
        #if os(iOS)
        checkSupport()
        #endif
    }

    // MARK: - Public API

    /// Start a new heartbeat Live Activity
    func startHeartbeatActivity(profileName: String, intervalSeconds: Int) async throws {
        #if os(iOS)
        guard isSupported else {
            throw LiveActivityError.notSupported
        }

        guard settingsViewModel.settings.heartbeatSettings.liveActivityEnabled else {
            return
        }

        // End any existing activity first
        await endHeartbeatActivity()

        let attributes = HeartbeatActivityAttributes(
            profileName: profileName,
            intervalSeconds: intervalSeconds
        )

        let initialState = HeartbeatActivityAttributes.ContentState.idle

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
        } catch {
            throw LiveActivityError.failedToStart(error.localizedDescription)
        }
        #endif
    }

    /// Update the Live Activity with a new state
    func updateHeartbeatActivity(
        status: HeartbeatActivityStatus,
        lastRunTime: Date?,
        nextRunTime: Date?,
        entrySummary: String?,
        entryKind: String?,
        entryTags: [String],
        errorMessage: String?,
        moodIcon: HeartbeatMoodIcon? = nil,
        moodReason: String? = nil
    ) async {
        #if os(iOS)
        guard let activity = currentActivity else { return }

        let state = HeartbeatActivityAttributes.ContentState(
            status: status,
            lastRunTime: lastRunTime,
            nextRunTime: nextRunTime,
            entrySummary: entrySummary?.truncated(to: 120),
            entryKind: entryKind,
            entryTags: Array(entryTags.prefix(3)),
            errorMessage: errorMessage,
            moodIcon: moodIcon,
            moodReason: moodReason?.truncated(to: 50)
        )

        // Calculate stale date based on interval
        let staleDate = nextRunTime?.addingTimeInterval(60)

        await activity.update(
            ActivityContent(state: state, staleDate: staleDate)
        )
        #endif
    }

    /// Update with a HeartbeatRunResult directly
    func updateHeartbeatActivity(
        with result: HeartbeatRunResult,
        nextRunTime: Date?,
        moodIcon: HeartbeatMoodIcon? = nil,
        moodReason: String? = nil
    ) async {
        #if os(iOS)
        let status: HeartbeatActivityStatus
        var entrySummary: String?
        var entryKind: String?
        var entryTags: [String] = []
        var errorMessage: String?

        switch result.status {
        case .success:
            status = .idle
            if let entry = result.entry {
                entrySummary = entry.content
                entryKind = entry.kind.rawValue
                entryTags = entry.tags
            }
        case .skipped:
            if result.message.lowercased().contains("quiet") {
                status = .quietHours
            } else if result.message.lowercased().contains("disabled") {
                status = .disabled
            } else {
                status = .idle
            }
        case .failed:
            status = .error
            errorMessage = result.message
        }

        await updateHeartbeatActivity(
            status: status,
            lastRunTime: Date(),
            nextRunTime: nextRunTime,
            entrySummary: entrySummary,
            entryKind: entryKind,
            entryTags: entryTags,
            errorMessage: errorMessage,
            moodIcon: moodIcon,
            moodReason: moodReason
        )
        #endif
    }

    /// Signal that a heartbeat run is starting
    func markHeartbeatRunning() async {
        #if os(iOS)
        guard let activity = currentActivity else { return }

        // Preserve previous state but change status to running
        let currentState = activity.content.state
        let runningState = HeartbeatActivityAttributes.ContentState(
            status: .running,
            lastRunTime: currentState.lastRunTime,
            nextRunTime: nil,
            entrySummary: currentState.entrySummary,
            entryKind: currentState.entryKind,
            entryTags: currentState.entryTags,
            errorMessage: nil,
            moodIcon: currentState.moodIcon,
            moodReason: currentState.moodReason
        )

        await activity.update(
            ActivityContent(state: runningState, staleDate: nil)
        )
        #endif
    }

    /// End the current Live Activity
    func endHeartbeatActivity() async {
        #if os(iOS)
        guard let activity = currentActivity else { return }

        let currentState = activity.content.state
        
        // If the activity is in an error state, clear the error before ending
        // to prevent it from lingering on the lock screen in some iOS versions.
        let finalState = HeartbeatActivityAttributes.ContentState(
            status: .disabled,
            lastRunTime: currentState.lastRunTime,
            nextRunTime: nil,
            entrySummary: currentState.entrySummary,
            entryKind: currentState.entryKind,
            entryTags: currentState.entryTags,
            errorMessage: nil,
            moodIcon: currentState.moodIcon,
            moodReason: currentState.moodReason
        )

        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )

        currentActivity = nil
        #endif
    }

    /// End all heartbeat activities (cleanup)
    func endAllHeartbeatActivities() async {
        #if os(iOS)
        for activity in Activity<HeartbeatActivityAttributes>.activities {
            await activity.end(dismissalPolicy: .immediate)
        }
        currentActivity = nil
        #endif
    }

    // MARK: - Sub-Agent Live Activities

    /// Start a Live Activity for a sub-agent job
    func startSubAgentActivity(for job: SubAgentJob) async throws {
        #if os(iOS)
        guard isSupported else {
            throw LiveActivityError.notSupported
        }

        // Check if activity already exists
        if subAgentActivities[job.id] != nil {
            return
        }

        let attributes = SubAgentActivityAttributes(
            jobId: job.id,
            role: SubAgentActivityRole(from: job.role),
            taskPreview: String(job.task.prefix(100)),
            contextTags: Array(job.contextInjectionTags.prefix(3))
        )

        let initialState = SubAgentActivityAttributes.ContentState(
            state: SubAgentActivityState(from: job.state),
            startedAt: job.startedAt,
            elapsedSeconds: job.startedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0,
            progress: nil,
            statusMessage: nil,
            provider: job.executedProvider?.displayName ?? job.provider?.displayName,
            model: job.executedModel ?? job.model
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            subAgentActivities[job.id] = activity
        } catch {
            throw LiveActivityError.failedToStart(error.localizedDescription)
        }
        #endif
    }

    /// Update a sub-agent Live Activity
    func updateSubAgentActivity(
        jobId: String,
        state: SubAgentJobState,
        startedAt: Date?,
        progress: SubAgentProgress? = nil,
        statusMessage: String? = nil,
        provider: String? = nil,
        model: String? = nil
    ) async {
        #if os(iOS)
        guard let activity = subAgentActivities[jobId] else { return }

        let elapsedSeconds = startedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0

        let contentState = SubAgentActivityAttributes.ContentState(
            state: SubAgentActivityState(from: state),
            startedAt: startedAt,
            elapsedSeconds: elapsedSeconds,
            progress: progress,
            statusMessage: statusMessage?.truncated(to: 80),
            provider: provider,
            model: model
        )

        // Set stale date for terminal states
        let staleDate: Date? = state.isTerminal ? Date().addingTimeInterval(30) : nil

        await activity.update(
            ActivityContent(state: contentState, staleDate: staleDate)
        )

        // Auto-end after completion with delay
        if state.isTerminal {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                await endSubAgentActivity(jobId: jobId)
            }
        }
        #endif
    }

    /// Update a sub-agent Live Activity directly from a job
    func updateSubAgentActivity(with job: SubAgentJob, statusMessage: String? = nil) async {
        #if os(iOS)
        await updateSubAgentActivity(
            jobId: job.id,
            state: job.state,
            startedAt: job.startedAt,
            progress: nil,
            statusMessage: statusMessage,
            provider: job.executedProvider?.displayName ?? job.provider?.displayName,
            model: job.executedModel ?? job.model
        )
        #endif
    }

    /// End a sub-agent Live Activity
    func endSubAgentActivity(jobId: String, immediately: Bool = false) async {
        #if os(iOS)
        guard let activity = subAgentActivities[jobId] else { return }

        let dismissalPolicy: ActivityUIDismissalPolicy = immediately ? .immediate : .after(Date().addingTimeInterval(5))

        await activity.end(dismissalPolicy: dismissalPolicy)
        subAgentActivities.removeValue(forKey: jobId)
        #endif
    }

    /// End all sub-agent Live Activities
    func endAllSubAgentActivities() async {
        #if os(iOS)
        for activity in Activity<SubAgentActivityAttributes>.activities {
            await activity.end(dismissalPolicy: .immediate)
        }
        subAgentActivities.removeAll()
        #endif
    }

    /// Get the number of active sub-agent activities
    var activeSubAgentCount: Int {
        #if os(iOS)
        return subAgentActivities.count
        #else
        return 0
        #endif
    }

    // MARK: - Private

    private func checkSupport() {
        #if os(iOS)
        let info = ActivityAuthorizationInfo()
        authorizationStatus = info
        isSupported = info.areActivitiesEnabled
        #else
        isSupported = false
        #endif
    }
}

// MARK: - Errors

enum LiveActivityError: LocalizedError {
    case notSupported
    case failedToStart(String)
    case failedToUpdate(String)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Live Activities are not supported on this device"
        case .failedToStart(let reason):
            return "Failed to start Live Activity: \(reason)"
        case .failedToUpdate(let reason):
            return "Failed to update Live Activity: \(reason)"
        }
    }
}

// MARK: - String Extension

private extension String {
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength {
            return self
        }
        return String(prefix(maxLength - 3)) + "..."
    }
}
