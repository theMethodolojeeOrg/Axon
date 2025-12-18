//
//  HeartbeatActivityAttributes.swift
//  Axon
//
//  Shared ActivityAttributes model for heartbeat Live Activity.
//  This file must be added to both the main app and widget extension targets.
//

import ActivityKit
import Foundation

struct HeartbeatActivityAttributes: ActivityAttributes {
    // Static context (set when activity starts, cannot change)
    let profileName: String
    let intervalSeconds: Int

    // Dynamic state (updated during activity lifecycle)
    struct ContentState: Codable, Hashable {
        let status: HeartbeatActivityStatus
        let lastRunTime: Date?
        let nextRunTime: Date?
        let entrySummary: String?
        let entryKind: String?
        let entryTags: [String]
        let errorMessage: String?

        static var idle: ContentState {
            ContentState(
                status: .idle,
                lastRunTime: nil,
                nextRunTime: nil,
                entrySummary: nil,
                entryKind: nil,
                entryTags: [],
                errorMessage: nil
            )
        }
    }
}

enum HeartbeatActivityStatus: String, Codable, Hashable {
    case idle           // Waiting for next heartbeat
    case running        // Currently executing heartbeat
    case quietHours     // Paused due to quiet hours
    case disabled       // Feature disabled
    case error          // Last run failed

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Thinking..."
        case .quietHours: return "Quiet Hours"
        case .disabled: return "Disabled"
        case .error: return "Error"
        }
    }

    var iconName: String {
        switch self {
        case .idle: return "heart.fill"
        case .running: return "brain.head.profile"
        case .quietHours: return "moon.fill"
        case .disabled: return "heart.slash.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .idle: return "gray"
        case .running: return "green"
        case .quietHours: return "purple"
        case .disabled: return "gray"
        case .error: return "red"
        }
    }
}
