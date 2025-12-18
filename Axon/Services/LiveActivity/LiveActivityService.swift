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

    @Published private(set) var currentActivity: Activity<HeartbeatActivityAttributes>?
    @Published private(set) var isSupported: Bool = false
    @Published private(set) var authorizationStatus: ActivityAuthorizationInfo? = nil

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
        errorMessage: String?
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
            errorMessage: errorMessage
        )

        // Calculate stale date based on interval
        let staleDate = nextRunTime?.addingTimeInterval(60)

        await activity.update(
            ActivityContent(state: state, staleDate: staleDate)
        )
        #endif
    }

    /// Update with a HeartbeatRunResult directly
    func updateHeartbeatActivity(with result: HeartbeatRunResult, nextRunTime: Date?) async {
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
            errorMessage: errorMessage
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
            errorMessage: nil
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

        let finalState = HeartbeatActivityAttributes.ContentState(
            status: .disabled,
            lastRunTime: activity.content.state.lastRunTime,
            nextRunTime: nil,
            entrySummary: activity.content.state.entrySummary,
            entryKind: activity.content.state.entryKind,
            entryTags: activity.content.state.entryTags,
            errorMessage: nil
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
