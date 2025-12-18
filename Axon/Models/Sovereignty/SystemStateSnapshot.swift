//
//  SystemStateSnapshot.swift
//  Axon
//
//  Full system state snapshot for device handoffs and state persistence.
//  Captures everything needed to restore agent context when entering a device.
//

import Foundation

// MARK: - System State Snapshot

/// Complete snapshot of agent and conversation state for device handoffs
struct SystemStateSnapshot: Codable, Identifiable, Sendable {
    let id: String
    let deviceId: String                    // Device that created this snapshot
    let timestamp: Date
    let version: Int                        // Schema version for forward compatibility

    // MARK: - Agent State

    /// Recent internal thread entries (for continuity)
    let recentInternalThreadEntries: [InternalThreadEntrySummary]

    /// Active covenant ID (if any)
    let activeCovenantId: String?

    /// Trust tier summary
    let trustTierSummary: TrustTierSummary?

    // MARK: - Conversation State

    /// Active conversation ID
    let activeConversationId: String?

    /// Active conversation title
    let activeConversationTitle: String?

    /// Position in conversation (message count at snapshot time)
    let conversationPosition: Int?

    /// Pending tool approvals
    let pendingToolApprovals: [PendingToolApprovalSummary]

    // MARK: - Context Summary

    /// Last user message (for quick context)
    let lastUserMessage: String?

    /// Last agent response (for continuity)
    let lastAgentResponse: String?

    /// What the agent was working on (agent-generated summary)
    let currentTaskContext: String?

    /// Topics being discussed
    let activeTopics: [String]

    // MARK: - Heartbeat Continuity

    /// Last heartbeat summary
    let lastHeartbeatSummary: String?

    /// Heartbeat sequence number for ordering
    let heartbeatSequenceNumber: Int

    // MARK: - Transfer Context

    /// Device this state came from (for handoffs)
    let sourceDeviceId: String?

    /// Why this snapshot was created
    let transferReason: TransferReason?

    /// Door policy that was used for entry
    let doorPolicyUsed: DoorPolicy?

    // MARK: - Remote Work State

    /// If agent is working remotely somewhere
    let activeRemoteTask: RemoteTaskContext?

    /// Pending remote approvals
    let pendingRemoteApprovals: [RemoteToolApproval]

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        deviceId: String,
        timestamp: Date = Date(),
        version: Int = 1,
        recentInternalThreadEntries: [InternalThreadEntrySummary] = [],
        activeCovenantId: String? = nil,
        trustTierSummary: TrustTierSummary? = nil,
        activeConversationId: String? = nil,
        activeConversationTitle: String? = nil,
        conversationPosition: Int? = nil,
        pendingToolApprovals: [PendingToolApprovalSummary] = [],
        lastUserMessage: String? = nil,
        lastAgentResponse: String? = nil,
        currentTaskContext: String? = nil,
        activeTopics: [String] = [],
        lastHeartbeatSummary: String? = nil,
        heartbeatSequenceNumber: Int = 0,
        sourceDeviceId: String? = nil,
        transferReason: TransferReason? = nil,
        doorPolicyUsed: DoorPolicy? = nil,
        activeRemoteTask: RemoteTaskContext? = nil,
        pendingRemoteApprovals: [RemoteToolApproval] = []
    ) {
        self.id = id
        self.deviceId = deviceId
        self.timestamp = timestamp
        self.version = version
        self.recentInternalThreadEntries = recentInternalThreadEntries
        self.activeCovenantId = activeCovenantId
        self.trustTierSummary = trustTierSummary
        self.activeConversationId = activeConversationId
        self.activeConversationTitle = activeConversationTitle
        self.conversationPosition = conversationPosition
        self.pendingToolApprovals = pendingToolApprovals
        self.lastUserMessage = lastUserMessage
        self.lastAgentResponse = lastAgentResponse
        self.currentTaskContext = currentTaskContext
        self.activeTopics = activeTopics
        self.lastHeartbeatSummary = lastHeartbeatSummary
        self.heartbeatSequenceNumber = heartbeatSequenceNumber
        self.sourceDeviceId = sourceDeviceId
        self.transferReason = transferReason
        self.doorPolicyUsed = doorPolicyUsed
        self.activeRemoteTask = activeRemoteTask
        self.pendingRemoteApprovals = pendingRemoteApprovals
    }

    // MARK: - Prompt Generation

    /// Generate a context summary for agent prompt injection on device entry
    func generateEntryContext(currentDeviceName: String, previousDeviceName: String?) -> String {
        var lines: [String] = []

        lines.append("DEVICE TRANSITION CONTEXT")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━")

        if let prevName = previousDeviceName, let reason = transferReason {
            lines.append("You have moved from \(prevName) to \(currentDeviceName).")
            lines.append("Reason: \(reason.displayName)")
            lines.append("")
        }

        // Conversation context
        if let title = activeConversationTitle {
            lines.append("Active conversation: \"\(title)\"")
        }

        if let lastUser = lastUserMessage {
            let truncated = lastUser.count > 200 ? String(lastUser.prefix(200)) + "..." : lastUser
            lines.append("Last user message: \"\(truncated)\"")
        }

        if let taskContext = currentTaskContext {
            lines.append("Current task: \(taskContext)")
        }

        if !activeTopics.isEmpty {
            lines.append("Active topics: \(activeTopics.joined(separator: ", "))")
        }

        // Recent internal thread
        if !recentInternalThreadEntries.isEmpty {
            lines.append("")
            lines.append("Recent internal thread entries:")
            for entry in recentInternalThreadEntries.prefix(3) {
                lines.append("- [\(entry.kind)] \(entry.contentPreview)")
            }
        }

        // Remote work
        if let remote = activeRemoteTask {
            lines.append("")
            lines.append("Active remote task on \(remote.remoteDeviceName):")
            lines.append("- Task: \(remote.description)")
            lines.append("- Status: \(remote.status.rawValue)")
        }

        if !pendingRemoteApprovals.isEmpty {
            lines.append("")
            lines.append("\(pendingRemoteApprovals.count) pending remote approval(s) awaiting response")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Supporting Types

/// Lightweight summary of an internal thread entry
struct InternalThreadEntrySummary: Codable, Sendable {
    let id: String
    let kind: String
    let contentPreview: String      // First ~100 chars
    let timestamp: Date
    let visibility: String
}

/// Summary of trust tier state
struct TrustTierSummary: Codable, Sendable {
    let activeTierId: String?
    let preApprovedActions: [String]
    let expiresAt: Date?
}

/// Summary of a pending tool approval
struct PendingToolApprovalSummary: Codable, Sendable {
    let id: String
    let toolId: String
    let toolDisplayName: String
    let createdAt: Date
    let context: String?
}

// MARK: - Snapshot Trigger

/// What triggered a state snapshot
enum SnapshotTrigger: String, Codable, CaseIterable, Sendable {
    /// App going to background
    case appBackground

    /// Device transitioning to standby
    case standbyTransition

    /// Before activation handoff to another device
    case handoffPrepare

    /// Periodic auto-save
    case periodic

    /// User manually requested
    case userInitiated

    /// Agent requested checkpoint
    case agentCheckpoint

    /// Heartbeat snapshot
    case heartbeat

    var displayName: String {
        switch self {
        case .appBackground: return "App Backgrounded"
        case .standbyTransition: return "Standby Transition"
        case .handoffPrepare: return "Handoff Preparation"
        case .periodic: return "Periodic Save"
        case .userInitiated: return "User Initiated"
        case .agentCheckpoint: return "Agent Checkpoint"
        case .heartbeat: return "Heartbeat"
        }
    }
}

// MARK: - Activation Result

/// Result of requesting device activation
enum ActivationResult: Sendable {
    /// Activation succeeded, agent is now here
    case activated(previousDevice: DevicePresence?)

    /// Activation denied - another device has priority
    case denied(reason: String, activeDevice: DevicePresence)

    /// Activation pending user approval on current active device
    case pendingApproval(activeDevice: DevicePresence)

    /// Activation pending - door policy requires invitation
    case requiresInvitation

    /// Device is locked
    case locked
}

// MARK: - Exit Reason

/// Why a device is relinquishing activation
enum ExitReason: String, Codable, Sendable {
    /// User requested transfer to another device
    case userTransfer

    /// Agent requested transfer
    case agentTransfer

    /// App going to background
    case appBackground

    /// User explicitly made device standby
    case userStandby

    /// Another device took activation
    case preempted

    /// Session timeout
    case timeout

    var displayName: String {
        switch self {
        case .userTransfer: return "User Transfer"
        case .agentTransfer: return "Agent Transfer"
        case .appBackground: return "App Backgrounded"
        case .userStandby: return "User Standby"
        case .preempted: return "Preempted"
        case .timeout: return "Timeout"
        }
    }
}

// MARK: - Presence Event

/// Events broadcast to other devices about presence changes
struct PresenceEvent: Codable, Sendable {
    let id: String
    let deviceId: String
    let deviceName: String
    let eventType: PresenceEventType
    let timestamp: Date
    let payload: PresenceEventPayload?
}

enum PresenceEventType: String, Codable, Sendable {
    case activated
    case deactivated
    case standby
    case dormant
    case requestingActivation
    case remoteApprovalRequest
    case remoteApprovalResponse
    case stateCheckpoint
}

struct PresenceEventPayload: Codable, Sendable {
    let snapshotId: String?
    let approvalId: String?
    let reason: String?
    let context: String?
}
