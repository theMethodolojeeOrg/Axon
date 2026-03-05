//
//  HeartbeatSettings.swift
//  Axon
//
//  Heartbeat scheduling and delivery settings
//

import Foundation

// MARK: - Heartbeat Module ID

enum HeartbeatModuleId: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemStatus = "system_status"
    case recentMessages = "recent_messages"
    case lastInternalThreadEntry = "last_internal_thread_entry"
    case pendingApprovals = "pending_approvals"
    case lastHeartbeat = "last_heartbeat"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemStatus: return "System Status"
        case .recentMessages: return "Recent Messages"
        case .lastInternalThreadEntry: return "Last Internal Thread Entry"
        case .pendingApprovals: return "Pending Approvals"
        case .lastHeartbeat: return "Last Heartbeat"
        }
    }
}

// MARK: - Heartbeat Delivery Profile

struct HeartbeatDeliveryProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var moduleIds: [HeartbeatModuleId]
    var description: String?

    static let defaultProfileId = "balanced"

    static let defaultProfiles: [HeartbeatDeliveryProfile] = [
        HeartbeatDeliveryProfile(
            id: "balanced",
            name: "Balanced",
            moduleIds: [.systemStatus, .recentMessages, .lastInternalThreadEntry, .pendingApprovals],
            description: "Default mix of status, recent context, and internal thread history."
        ),
        HeartbeatDeliveryProfile(
            id: "light",
            name: "Lightweight",
            moduleIds: [.systemStatus, .lastInternalThreadEntry],
            description: "Minimal context for quick check-ins."
        ),
        HeartbeatDeliveryProfile(
            id: "deep",
            name: "Deep Context",
            moduleIds: [.systemStatus, .recentMessages, .lastInternalThreadEntry, .pendingApprovals, .lastHeartbeat],
            description: "More context and continuity across heartbeats."
        )
    ]
}

// MARK: - Heartbeat Execution Mode

/// Determines how heartbeat triggers execute - silently or as visible solo threads
enum HeartbeatExecutionMode: String, Codable, CaseIterable, Sendable {
    /// Current behavior: silent reflection, no tools, no visible thread
    case internalThread

    /// Visible conversation with tool access and turn allocation
    case soloThread

    var displayName: String {
        switch self {
        case .internalThread: return "Internal Thread"
        case .soloThread: return "Solo Thread"
        }
    }

    var description: String {
        switch self {
        case .internalThread:
            return "Quiet reflection and note-taking in the internal thread"
        case .soloThread:
            return "Visible conversation with tool access and turn allocation"
        }
    }

    var icon: String {
        switch self {
        case .internalThread: return "text.bubble"
        case .soloThread: return "bolt.circle.fill"
        }
    }
}

// MARK: - Heartbeat Settings

struct HeartbeatSettings: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var intervalSeconds: Int = 3600
    var deliveryProfileId: String = HeartbeatDeliveryProfile.defaultProfileId
    var maxTokensBudget: Int = 800
    var maxToolCalls: Int = 0
    var allowBackground: Bool = false
    var allowNotifications: Bool = true
    var liveActivityEnabled: Bool = true
    var quietHours: TimeRestrictions? = nil
    var deliveryProfiles: [HeartbeatDeliveryProfile] = HeartbeatDeliveryProfile.defaultProfiles

    // MARK: - Solo Thread Configuration

    /// Execution mode for heartbeat triggers
    var executionMode: HeartbeatExecutionMode = .internalThread

    /// Number of turns allocated per solo thread session
    var soloTurnsPerSession: Int = 5

    /// Maximum solo sessions per day
    var soloMaxSessionsPerDay: Int = 3

    /// Tool categories allowed in solo threads
    var soloAllowedToolCategories: [ToolCategory] = [
        .memoryReflection, .internalThread, .toolDiscovery
    ]

    /// Number of solo sessions completed today (resets daily)
    var soloSessionsToday: Int = 0

    /// Date of last solo session count reset
    var soloSessionsResetDate: Date?

    func profile(for id: String) -> HeartbeatDeliveryProfile? {
        deliveryProfiles.first { $0.id == id }
    }

    /// Whether more solo sessions are available today
    var canStartSoloSession: Bool {
        soloSessionsToday < soloMaxSessionsPerDay
    }

    /// Reset daily session count if it's a new day
    mutating func resetDailyCountIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let resetDate = soloSessionsResetDate {
            let lastReset = calendar.startOfDay(for: resetDate)
            if lastReset < today {
                soloSessionsToday = 0
                soloSessionsResetDate = Date()
            }
        } else {
            soloSessionsResetDate = Date()
        }
    }
}
