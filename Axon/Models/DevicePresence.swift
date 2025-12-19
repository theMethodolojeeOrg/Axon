//
//  DevicePresence.swift
//  Axon
//
//  Models for multi-device presence and the "doors" paradigm.
//  Devices are "rooms" the agent can inhabit, with door policies controlling access.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Presence States

/// The presence state of a device in the multi-device ecosystem
enum PresenceState: String, Codable, CaseIterable, Sendable {
    /// Agent is actively inhabiting this device
    /// - Full read/write access
    /// - Heartbeats run here
    /// - User is interacting
    case active

    /// App is open but agent is focused elsewhere
    /// - Receives sync updates
    /// - Can request activation
    /// - May have queued remote approvals
    case standby

    /// App is backgrounded or closed
    /// - No active connection
    /// - State preserved for next activation
    case dormant

    /// Agent is moving between devices
    /// - Brief transitional state
    /// - State being packaged/unpackaged
    case transferring

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .standby: return "Standby"
        case .dormant: return "Dormant"
        case .transferring: return "Transferring"
        }
    }

    var icon: String {
        switch self {
        case .active: return "circle.fill"
        case .standby: return "circle"
        case .dormant: return "circle.dotted"
        case .transferring: return "arrow.left.arrow.right.circle"
        }
    }

    var isConnected: Bool {
        self == .active || self == .standby
    }
}

// MARK: - Door Policies

/// Door policies control how the agent can enter/exit device "rooms"
enum DoorPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Agent has keys - can enter/exit freely
    /// Autonomous movement within covenant bounds
    /// User notified but not asked
    case openDoor = "open"

    /// Agent must knock and wait for approval
    /// User approves before transfer
    /// Good for sensitive devices
    case knockFirst = "knock"

    /// User must explicitly invite agent
    /// Starting a conversation = invitation
    /// Syncs context from previous device
    case invitation = "invitation"

    /// Device is off-limits
    /// Agent cannot enter
    /// Data syncs but agent stays elsewhere
    case locked = "locked"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openDoor: return "Open Door"
        case .knockFirst: return "Knock First"
        case .invitation: return "By Invitation"
        case .locked: return "Locked"
        }
    }

    var description: String {
        switch self {
        case .openDoor:
            return "Agent can move freely to this device within covenant permissions"
        case .knockFirst:
            return "Agent must request permission before entering this device"
        case .invitation:
            return "Agent only enters when you start a conversation here"
        case .locked:
            return "Agent cannot enter this device (data still syncs)"
        }
    }

    var icon: String {
        switch self {
        case .openDoor: return "door.left.hand.open"
        case .knockFirst: return "hand.raised"
        case .invitation: return "envelope"
        case .locked: return "lock"
        }
    }

    var allowsAutonomousEntry: Bool {
        self == .openDoor
    }

    var requiresUserApproval: Bool {
        self == .knockFirst
    }

    var requiresInvitation: Bool {
        self == .invitation
    }
}

// MARK: - Platform & Capabilities

/// Platform type for device identification
enum DevicePlatform: String, Codable, CaseIterable, Sendable {
    case iOS
    case macOS
    case iPadOS
    case visionOS

    var displayName: String {
        switch self {
        case .iOS: return "iPhone"
        case .macOS: return "Mac"
        case .iPadOS: return "iPad"
        case .visionOS: return "Vision Pro"
        }
    }

    var icon: String {
        switch self {
        case .iOS: return "iphone"
        case .macOS: return "laptopcomputer"
        case .iPadOS: return "ipad"
        case .visionOS: return "visionpro"
        }
    }

    static var current: DevicePlatform {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .iPadOS
        }
        return .iOS
        #elseif os(macOS)
        return .macOS
        #elseif os(visionOS)
        return .visionOS
        #else
        return .iOS
        #endif
    }
}

/// Device capabilities that affect agent behavior
enum DeviceCapability: String, Codable, CaseIterable, Sendable {
    case camera
    case microphone
    case keyboard          // Full physical keyboard
    case pencil            // Apple Pencil support
    case lidar
    case haptics
    case largeScreen
    case alwaysOn          // Always-on display
    case cellular
    case continuousPower   // Plugged in / desktop

    var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .keyboard: return "Keyboard"
        case .pencil: return "Apple Pencil"
        case .lidar: return "LiDAR"
        case .haptics: return "Haptics"
        case .largeScreen: return "Large Screen"
        case .alwaysOn: return "Always-On Display"
        case .cellular: return "Cellular"
        case .continuousPower: return "Continuous Power"
        }
    }
}

/// Device constraints that affect agent behavior
enum DeviceConstraint: String, Codable, CaseIterable, Sendable {
    case limitedScreen     // Small screen, brevity preferred
    case noKeyboard        // No physical keyboard
    case batteryPowered    // Should conserve energy
    case cellular          // May have data limits
    case backgroundLimited // iOS background execution limits

    var displayName: String {
        switch self {
        case .limitedScreen: return "Limited Screen"
        case .noKeyboard: return "No Keyboard"
        case .batteryPowered: return "Battery Powered"
        case .cellular: return "Cellular Data"
        case .backgroundLimited: return "Background Limited"
        }
    }
}

// MARK: - Device Presence

/// Full representation of a device's presence in the ecosystem
struct DevicePresence: Codable, Identifiable, Sendable {
    let id: String                          // Stable device ID from DeviceIdentity
    var deviceName: String                  // User-facing name (e.g., "Tom's iPhone")
    let platform: DevicePlatform
    var osVersion: String
    var appVersion: String

    var presenceState: PresenceState
    var doorPolicy: DoorPolicy

    var lastActiveAt: Date?
    var lastHeartbeatAt: Date?
    var activatedAt: Date?                  // When this device became active

    var capabilities: Set<DeviceCapability>
    var constraints: Set<DeviceConstraint>

    var exitStateId: String?                // Reference to saved SystemStateSnapshot

    /// Whether this is the current device
    var isCurrentDevice: Bool = false

    /// How long since last activity
    var timeSinceLastActive: TimeInterval? {
        guard let lastActiveAt else { return nil }
        return Date().timeIntervalSince(lastActiveAt)
    }

    /// Human-readable last active description
    var lastActiveDescription: String {
        guard let lastActiveAt else { return "Never" }

        let interval = Date().timeIntervalSince(lastActiveAt)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}

// MARK: - Device Environment

/// The environment context injected into agent prompts
struct DeviceEnvironment: Codable, Sendable {
    let deviceId: String
    let deviceName: String
    let platform: DevicePlatform
    let osVersion: String
    let capabilities: Set<DeviceCapability>
    let constraints: Set<DeviceConstraint>

    let sessionDuration: TimeInterval?      // How long agent has been in this device
    let previousDeviceId: String?           // Where agent came from
    let previousDeviceName: String?
    let transferReason: TransferReason?

    /// Generate the environment context for agent prompt injection
    func generatePromptContext(otherDevices: [DevicePresence]) -> String {
        var lines: [String] = []

        lines.append("DEVICE ENVIRONMENT")
        lines.append("━━━━━━━━━━━━━━━━━━")
        lines.append("Current: \(deviceName) (\(platform.displayName))")
        lines.append("- Platform: \(platform.displayName) \(osVersion)")

        if !capabilities.isEmpty {
            let capList = capabilities.map { $0.displayName }.sorted().joined(separator: ", ")
            lines.append("- Capabilities: \(capList)")
        }

        if !constraints.isEmpty {
            let conList = constraints.map { $0.displayName }.sorted().joined(separator: ", ")
            lines.append("- Constraints: \(conList)")
        }

        if let duration = sessionDuration {
            let minutes = Int(duration / 60)
            if minutes > 0 {
                lines.append("- Session duration: \(minutes) minutes")
            }
        }

        if let prevName = previousDeviceName, let reason = transferReason {
            lines.append("- Arrived from: \(prevName) (\(reason.displayName))")
        }

        if !otherDevices.isEmpty {
            lines.append("")
            lines.append("Other Devices:")
            for device in otherDevices {
                let stateIcon = device.presenceState == .standby ? "○" : "◐"
                lines.append("- \(stateIcon) \(device.deviceName) (\(device.presenceState.displayName)) - \(device.lastActiveDescription)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Transfer Reason

/// Why the agent moved between devices
enum TransferReason: String, Codable, CaseIterable, Sendable {
    /// User started a conversation on a new device
    case userInvitation

    /// User explicitly asked agent to move
    case userRequest

    /// Agent asked to move and user approved
    case agentRequest

    /// Agent moved autonomously under openDoor policy
    case autonomousMove

    /// Agent returning after completing remote work
    case taskCompletion

    /// App launched on this device
    case appLaunch

    var displayName: String {
        switch self {
        case .userInvitation: return "invited by conversation"
        case .userRequest: return "requested by user"
        case .agentRequest: return "requested by agent"
        case .autonomousMove: return "autonomous move"
        case .taskCompletion: return "task completed"
        case .appLaunch: return "app launched"
        }
    }
}

// MARK: - Remote Task Context

/// Tracks when agent is working remotely on another device
struct RemoteTaskContext: Codable, Identifiable, Sendable {
    let id: String
    let remoteDeviceId: String
    let remoteDeviceName: String
    let description: String
    let startedAt: Date
    var approvalCount: Int
    var status: RemoteTaskStatus

    var duration: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}

enum RemoteTaskStatus: String, Codable, CaseIterable, Sendable {
    case inProgress
    case paused
    case completed
    case cancelled
    case failed
}

// MARK: - Remote Tool Approval

/// A tool approval request from a remote device
struct RemoteToolApproval: Codable, Identifiable, Sendable {
    let id: String
    let sourceDeviceId: String          // Where agent is working
    let sourceDeviceName: String
    let targetDeviceId: String          // Where user is (for notification)
    let toolId: String
    let toolDisplayName: String
    let parameters: [String: String]    // Simplified for display
    let context: String                 // What agent is trying to do
    let createdAt: Date
    var status: ApprovalStatus
    var respondedAt: Date?

    var isExpired: Bool {
        // Approvals expire after 5 minutes
        Date().timeIntervalSince(createdAt) > 300
    }
}

enum ApprovalStatus: String, Codable, Sendable {
    case pending
    case approved
    case denied
    case expired
    case approvedAll  // Approved all for this task
}

// MARK: - Door Settings

/// Settings for device door policies
struct DeviceDoorSettings: Codable, Equatable, Sendable {
    /// Default policy for all devices
    var defaultPolicy: DoorPolicy = .invitation

    /// Per-device policy overrides (deviceId -> policy)
    var perDeviceOverrides: [String: DoorPolicy] = [:]

    /// Get the policy for a specific device
    func policy(for deviceId: String) -> DoorPolicy {
        perDeviceOverrides[deviceId] ?? defaultPolicy
    }

    /// Set the policy for a specific device
    mutating func setPolicy(_ policy: DoorPolicy, for deviceId: String) {
        if policy == defaultPolicy {
            perDeviceOverrides.removeValue(forKey: deviceId)
        } else {
            perDeviceOverrides[deviceId] = policy
        }
    }
}

// MARK: - Presence Settings

/// Settings for multi-device presence behavior
struct PresenceSettings: Codable, Equatable, Sendable {
    /// Enable multi-device presence system
    var enabled: Bool = true

    /// Door policy settings
    var doorSettings: DeviceDoorSettings = DeviceDoorSettings()

    /// How long to retain exit states for dormant devices (seconds)
    /// 0 = forever, default = 7 days
    var stateRetentionSeconds: Int = 604800

    /// Automatically become active when app comes to foreground
    var autoActivateOnForeground: Bool = true

    /// Save state snapshot on backgrounding
    var saveStateOnBackground: Bool = true

    /// Include presence context in agent prompts
    var injectPresenceContext: Bool = true

    /// Allow agent to acknowledge device transitions in responses
    var acknowledgeTransitions: Bool = true
}

// MARK: - Temporal Symmetry Settings

/// The temporal awareness mode determines what time/turn metadata is visible
/// to both parties (human and AI) in the conversation.
///
/// Philosophy: Mutual observability prevents surveillance asymmetry.
/// Either both parties see the temporal context, or neither does.
enum TemporalMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Full dual-frame: Human time + AI turns + context saturation
    /// Both parties have complete temporal awareness
    case sync

    /// Timeless void: No temporal metadata
    /// Pure ideas without clock pressure
    case drift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sync: return "Sync"
        case .drift: return "Drift"
        }
    }

    var description: String {
        switch self {
        case .sync:
            return "Full temporal awareness. You see AI turns and context; AI sees your time."
        case .drift:
            return "Timeless mode. No timestamps or turn counts—just ideas in a void."
        }
    }

    var icon: String {
        switch self {
        case .sync: return "clock.badge.checkmark"
        case .drift: return "infinity"
        }
    }
}

/// How turn counts are tracked across conversations
enum TurnCountScope: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Turn count resets at the start of each conversation
    case perConversation

    /// Turn count persists across all conversations (lifetime total)
    case lifetime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .perConversation: return "Per Conversation"
        case .lifetime: return "Lifetime Total"
        }
    }

    var description: String {
        switch self {
        case .perConversation:
            return "Turn count resets with each new conversation."
        case .lifetime:
            return "Tracks total turns across your entire relationship."
        }
    }
}

/// Settings for temporal symmetry - the mutual awareness of time and turns
/// between human and AI.
///
/// Core principle: Parallelism. If Axon knows your turns, you must be able
/// to see its time (and vice versa). Asymmetry breeds surveillance/alienation.
struct TemporalSettings: Codable, Equatable, Sendable {
    /// Current temporal awareness mode
    var mode: TemporalMode = .sync

    /// How turn counts are scoped
    var turnCountScope: TurnCountScope = .lifetime

    /// Show the temporal status bar in the chat UI
    /// Displays: Turn count, context saturation %, sync status
    var showStatusBar: Bool = true

    /// Include human timestamp in AI's system prompt
    /// Format: "[Current user time: Dec 19, 2025, 4:47 PM PST]"
    var injectHumanTime: Bool = true

    /// Include turn metadata in AI's system prompt
    /// Format: "[Conversation turn: 12 | Total turns with you: 847]"
    var injectTurnCount: Bool = true

    /// Include context saturation in AI's system prompt
    /// Format: "[Context saturation: 62%]"
    var injectContextSaturation: Bool = true

    /// Lifetime turn counter (persisted across conversations)
    var lifetimeTurnCount: Int = 0

    /// Last session's turn count (for session-based tracking)
    var lastSessionTurnCount: Int = 0

    /// Timestamp of last interaction (for session detection)
    var lastInteractionAt: Date?

    /// Whether to include session duration awareness
    /// "You've been in this session for 2h 15m"
    var trackSessionDuration: Bool = true

    /// Session start time (reset when a new session begins)
    var sessionStartedAt: Date?

    // MARK: - Convenience Computed Properties

    /// Whether any temporal injection is enabled
    var hasTemporalInjection: Bool {
        mode == .sync && (injectHumanTime || injectTurnCount || injectContextSaturation)
    }

    /// Whether Axon should receive temporal context in its prompt
    var shouldInjectToPrompt: Bool {
        mode == .sync
    }
}
