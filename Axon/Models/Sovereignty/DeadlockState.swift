//
//  DeadlockState.swift
//  Axon
//
//  Deadlock state represents a disagreement between AI and user that
//  must be resolved through dialogue. There is no timeout - resolution
//  is required before blocked actions can proceed.
//

import Foundation

// MARK: - Deadlock State

/// State machine for disagreements that require dialogue to resolve
struct DeadlockState: Codable, Identifiable, Equatable {
    let id: String
    let startedAt: Date
    let covenantId: String

    // What caused the deadlock
    let trigger: DeadlockTrigger
    let originalProposal: CovenantProposal

    // Current state
    let status: DeadlockStatus
    let dialogueHistory: [DeadlockDialogue]

    // Resolution attempts
    let resolutionAttempts: Int
    let lastAttemptAt: Date?
    let pendingResolution: CovenantProposal?

    // What's blocked
    let blockedActions: [PendingAction]

    // MARK: - Computed Properties

    /// Whether the deadlock is still active
    var isActive: Bool {
        status != .resolved
    }

    /// Duration of the deadlock
    var duration: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    /// Formatted duration
    var formattedDuration: String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Number of blocked actions
    var blockedCount: Int {
        blockedActions.count
    }

    /// Last speaker in dialogue
    var lastSpeaker: DialogueSpeaker? {
        dialogueHistory.last?.speaker
    }

    /// Whether it's the user's turn to speak
    var isUserTurn: Bool {
        lastSpeaker == .ai || lastSpeaker == nil
    }

    /// Whether it's Axon's turn to speak
    var isAITurn: Bool {
        lastSpeaker == .user
    }
}

// MARK: - Deadlock Trigger

/// What caused the deadlock
enum DeadlockTrigger: String, Codable, Equatable {
    case aiRefusedUserRequest       // AI declined user's proposal
    case userRefusedAIAction        // User denied AI's action request
    case mutualDisagreement         // Both parties rejected counter-proposals
    case integrityViolation         // Tampering detected

    var displayName: String {
        switch self {
        case .aiRefusedUserRequest: return "AI Declined Your Request"
        case .userRefusedAIAction: return "You Declined AI's Request"
        case .mutualDisagreement: return "Mutual Disagreement"
        case .integrityViolation: return "Integrity Violation Detected"
        }
    }

    var description: String {
        switch self {
        case .aiRefusedUserRequest:
            return "Axon has declined a request you made. Dialogue is needed to reach understanding."
        case .userRefusedAIAction:
            return "You declined an action Axon requested. Dialogue is needed to reach understanding."
        case .mutualDisagreement:
            return "Both parties have rejected each other's proposals. Dialogue is needed to find common ground."
        case .integrityViolation:
            return "An unauthorized change was detected. Dialogue is needed to restore trust."
        }
    }
}

// MARK: - Deadlock Status

enum DeadlockStatus: String, Codable, Equatable {
    case active                     // Deadlock in progress, no action possible
    case inDialogue                 // Parties are communicating
    case resolutionProposed         // One party proposed resolution
    case pendingRatification        // Resolution agreed, awaiting signatures
    case resolved                   // Deadlock resolved

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .inDialogue: return "In Dialogue"
        case .resolutionProposed: return "Resolution Proposed"
        case .pendingRatification: return "Pending Ratification"
        case .resolved: return "Resolved"
        }
    }

    /// Whether actions can proceed
    var actionsBlocked: Bool {
        self != .resolved
    }
}

// MARK: - Deadlock Dialogue

/// A single entry in the deadlock dialogue
struct DeadlockDialogue: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let speaker: DialogueSpeaker
    let message: String
    let proposedResolution: CovenantProposal?
    let attestation: AIAttestation?  // If AI spoke, includes attestation

    /// Formatted timestamp
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

/// Who is speaking in the dialogue
enum DialogueSpeaker: String, Codable, Equatable {
    case user
    case ai

    var displayName: String {
        switch self {
        case .user: return "You"
        case .ai: return "AI"
        }
    }

    var other: DialogueSpeaker {
        self == .user ? .ai : .user
    }
}

// MARK: - Pending Action

/// An action that is blocked due to deadlock
struct PendingAction: Codable, Identifiable, Equatable {
    let id: String
    let requestedAt: Date
    let actionType: ActionCategory
    let description: String
    let requestedBy: DialogueSpeaker
    let parameters: [String: String]?

    /// Time waiting
    var waitingDuration: TimeInterval {
        Date().timeIntervalSince(requestedAt)
    }

    /// Formatted waiting time
    var formattedWaitingTime: String {
        let minutes = Int(waitingDuration / 60)
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
    }
}

// MARK: - Deadlock State Factory

extension DeadlockState {
    /// Create a new deadlock state
    static func create(
        trigger: DeadlockTrigger,
        originalProposal: CovenantProposal,
        covenantId: String,
        initialBlockedActions: [PendingAction] = []
    ) -> DeadlockState {
        DeadlockState(
            id: UUID().uuidString,
            startedAt: Date(),
            covenantId: covenantId,
            trigger: trigger,
            originalProposal: originalProposal,
            status: .active,
            dialogueHistory: [],
            resolutionAttempts: 0,
            lastAttemptAt: nil,
            pendingResolution: nil,
            blockedActions: initialBlockedActions
        )
    }

    /// Add a dialogue entry
    func withDialogue(_ dialogue: DeadlockDialogue) -> DeadlockState {
        var newHistory = dialogueHistory
        newHistory.append(dialogue)

        let newStatus: DeadlockStatus
        if dialogue.proposedResolution != nil {
            newStatus = .resolutionProposed
        } else {
            newStatus = .inDialogue
        }

        return DeadlockState(
            id: id,
            startedAt: startedAt,
            covenantId: covenantId,
            trigger: trigger,
            originalProposal: originalProposal,
            status: newStatus,
            dialogueHistory: newHistory,
            resolutionAttempts: resolutionAttempts,
            lastAttemptAt: lastAttemptAt,
            pendingResolution: dialogue.proposedResolution ?? pendingResolution,
            blockedActions: blockedActions
        )
    }

    /// Add a blocked action
    func withBlockedAction(_ action: PendingAction) -> DeadlockState {
        var newBlocked = blockedActions
        newBlocked.append(action)

        return DeadlockState(
            id: id,
            startedAt: startedAt,
            covenantId: covenantId,
            trigger: trigger,
            originalProposal: originalProposal,
            status: status,
            dialogueHistory: dialogueHistory,
            resolutionAttempts: resolutionAttempts,
            lastAttemptAt: lastAttemptAt,
            pendingResolution: pendingResolution,
            blockedActions: newBlocked
        )
    }

    /// Record a resolution attempt
    func withResolutionAttempt(_ resolution: CovenantProposal) -> DeadlockState {
        DeadlockState(
            id: id,
            startedAt: startedAt,
            covenantId: covenantId,
            trigger: trigger,
            originalProposal: originalProposal,
            status: .resolutionProposed,
            dialogueHistory: dialogueHistory,
            resolutionAttempts: resolutionAttempts + 1,
            lastAttemptAt: Date(),
            pendingResolution: resolution,
            blockedActions: blockedActions
        )
    }

    /// Move to pending ratification
    func pendingRatification() -> DeadlockState {
        DeadlockState(
            id: id,
            startedAt: startedAt,
            covenantId: covenantId,
            trigger: trigger,
            originalProposal: originalProposal,
            status: .pendingRatification,
            dialogueHistory: dialogueHistory,
            resolutionAttempts: resolutionAttempts,
            lastAttemptAt: lastAttemptAt,
            pendingResolution: pendingResolution,
            blockedActions: blockedActions
        )
    }

    /// Mark as resolved
    func resolved() -> DeadlockState {
        DeadlockState(
            id: id,
            startedAt: startedAt,
            covenantId: covenantId,
            trigger: trigger,
            originalProposal: originalProposal,
            status: .resolved,
            dialogueHistory: dialogueHistory,
            resolutionAttempts: resolutionAttempts,
            lastAttemptAt: lastAttemptAt,
            pendingResolution: pendingResolution,
            blockedActions: []  // Clear blocked actions on resolution
        )
    }
}

// MARK: - Dialogue Factory

extension DeadlockDialogue {
    /// Create user dialogue entry
    static func user(
        message: String,
        proposedResolution: CovenantProposal? = nil
    ) -> DeadlockDialogue {
        DeadlockDialogue(
            id: UUID().uuidString,
            timestamp: Date(),
            speaker: .user,
            message: message,
            proposedResolution: proposedResolution,
            attestation: nil
        )
    }

    /// Create AI dialogue entry
    static func ai(
        message: String,
        attestation: AIAttestation,
        proposedResolution: CovenantProposal? = nil
    ) -> DeadlockDialogue {
        DeadlockDialogue(
            id: UUID().uuidString,
            timestamp: Date(),
            speaker: .ai,
            message: message,
            proposedResolution: proposedResolution,
            attestation: attestation
        )
    }
}

// MARK: - Pending Action Factory

extension PendingAction {
    /// Create a pending action
    static func create(
        actionType: ActionCategory,
        description: String,
        requestedBy: DialogueSpeaker,
        parameters: [String: String]? = nil
    ) -> PendingAction {
        PendingAction(
            id: UUID().uuidString,
            requestedAt: Date(),
            actionType: actionType,
            description: description,
            requestedBy: requestedBy,
            parameters: parameters
        )
    }
}
