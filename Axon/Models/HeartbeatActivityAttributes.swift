//
//  HeartbeatActivityAttributes.swift
//  Axon
//
//  Shared ActivityAttributes model for heartbeat Live Activity.
//  This file must be added to both the main app and widget extension targets.
//

import Foundation
#if os(iOS)
import ActivityKit

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
        let moodIcon: HeartbeatMoodIcon?
        let moodReason: String?

        static var idle: ContentState {
            ContentState(
                status: .idle,
                lastRunTime: nil,
                nextRunTime: nil,
                entrySummary: nil,
                entryKind: nil,
                entryTags: [],
                errorMessage: nil,
                moodIcon: nil,
                moodReason: nil
            )
        }
    }
}
#endif

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

/// AI-selectable mood icons for the Live Activity
/// The AI can pick one to subtly indicate why it started the heartbeat
enum HeartbeatMoodIcon: String, Codable, Hashable, CaseIterable {
    // Thinking / Processing
    case thinking = "brain.head.profile"
    case lightbulb = "lightbulb.fill"
    case sparkles = "sparkles"

    // Emotions / State
    case happy = "face.smiling"
    case curious = "questionmark.circle"
    case focused = "eye"
    case peaceful = "leaf.fill"
    case energetic = "bolt.fill"

    // Activities
    case writing = "pencil.line"
    case reading = "book.fill"
    case organizing = "folder.fill"
    case connecting = "link"
    case searching = "magnifyingglass"

    // Time-related
    case waiting = "clock.fill"
    case sunrise = "sunrise.fill"
    case sunset = "sunset.fill"
    case night = "moon.stars.fill"

    // Abstract
    case wave = "waveform.path"
    case heart = "heart.fill"
    case star = "star.fill"
    case compass = "location.north.fill"

    var sfSymbolName: String { rawValue }

    var displayName: String {
        switch self {
        case .thinking: return "Thinking"
        case .lightbulb: return "Idea"
        case .sparkles: return "Inspired"
        case .happy: return "Happy"
        case .curious: return "Curious"
        case .focused: return "Focused"
        case .peaceful: return "Peaceful"
        case .energetic: return "Energetic"
        case .writing: return "Writing"
        case .reading: return "Reading"
        case .organizing: return "Organizing"
        case .connecting: return "Connecting"
        case .searching: return "Searching"
        case .waiting: return "Waiting"
        case .sunrise: return "Morning"
        case .sunset: return "Evening"
        case .night: return "Night"
        case .wave: return "Processing"
        case .heart: return "Feeling"
        case .star: return "Notable"
        case .compass: return "Exploring"
        }
    }
}
