//
//  SubAgentActivityAttributes.swift
//  Axon
//
//  Shared ActivityAttributes model for sub-agent job Live Activity.
//  This file must be added to the AxonLiveActivity widget extension target.
//
//  **Architectural Commandment #5**: The Mercury Pulse.
//  A sub-agent in the field is a living process - the Dynamic Island
//  gives Tom a real-time sense of his distributed team working.
//

import Foundation
#if os(iOS)
import ActivityKit

struct SubAgentActivityAttributes: ActivityAttributes {
    // Static context (set when activity starts, cannot change)
    let jobId: String
    let role: SubAgentActivityRole
    let taskPreview: String  // First ~100 chars of task
    let contextTags: [String]

    // Dynamic state (updated during activity lifecycle)
    struct ContentState: Codable, Hashable {
        let state: SubAgentActivityState
        let startedAt: Date?
        let elapsedSeconds: Int
        let progress: SubAgentProgress?
        let statusMessage: String?
        let provider: String?
        let model: String?

        static var initial: ContentState {
            ContentState(
                state: .proposed,
                startedAt: nil,
                elapsedSeconds: 0,
                progress: nil,
                statusMessage: nil,
                provider: nil,
                model: nil
            )
        }
    }
}
#endif

// MARK: - Sub-Agent Activity Role

/// Role representation for Live Activity (separate from main SubAgentRole for widget target)
enum SubAgentActivityRole: String, Codable, Hashable {
    case scout
    case mechanic
    case designer
    case namer

    var displayName: String {
        switch self {
        case .scout: return "Scout"
        case .mechanic: return "Mechanic"
        case .designer: return "Designer"
        case .namer: return "Namer"
        }
    }

    var icon: String {
        switch self {
        case .scout: return "binoculars"
        case .mechanic: return "wrench.and.screwdriver"
        case .designer: return "square.and.pencil"
        case .namer: return "textformat.abc"
        }
    }

    var verb: String {
        switch self {
        case .scout: return "Exploring"
        case .mechanic: return "Fixing"
        case .designer: return "Designing"
        case .namer: return "Naming"
        }
    }

    /// Mercury color name for the role
    var mercuryColorName: String {
        switch self {
        case .scout: return "mercury"      // Standard cyan-ish
        case .mechanic: return "lichen"    // Green tint
        case .designer: return "amethyst"  // Purple tint
        case .namer: return "amber"
        }
    }
}

// MARK: - Sub-Agent Activity State

/// State representation for Live Activity
enum SubAgentActivityState: String, Codable, Hashable {
    case proposed       // Awaiting approval
    case approved       // Approved, about to start
    case running        // The Mercury Pulse state
    case awaitingInput  // Sub-agent needs clarification
    case completed      // Successfully finished
    case failed         // Failed with error
    case terminated     // Manually stopped

    var displayName: String {
        switch self {
        case .proposed: return "Proposed"
        case .approved: return "Approved"
        case .running: return "Running"
        case .awaitingInput: return "Needs Input"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .terminated: return "Terminated"
        }
    }

    var icon: String {
        switch self {
        case .proposed: return "doc.badge.clock"
        case .approved: return "checkmark.seal"
        case .running: return "play.circle.fill"
        case .awaitingInput: return "questionmark.bubble"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .terminated: return "stop.circle.fill"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .terminated:
            return true
        default:
            return false
        }
    }

    var isPulsing: Bool {
        self == .running || self == .awaitingInput
    }
}

// MARK: - Sub-Agent Progress

/// Optional progress information for determinate tasks
struct SubAgentProgress: Codable, Hashable {
    let current: Int
    let total: Int
    let label: String?  // e.g., "3 of 5 files"

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    var percentString: String {
        "\(Int(fraction * 100))%"
    }
}
