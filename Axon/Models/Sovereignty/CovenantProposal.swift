//
//  CovenantProposal.swift
//  Axon
//
//  Covenant proposals represent changes proposed by either party
//  to the existing covenant. Both parties must respond for changes to take effect.
//

import Foundation

// MARK: - Covenant Proposal

/// A proposed change to the covenant from either party
struct CovenantProposal: Codable, Identifiable, Equatable {
    let id: String
    let proposedAt: Date
    let proposedBy: ProposalOriginator
    let expiresAt: Date?

    // What's being proposed
    let proposalType: ProposalType
    let changes: ProposedChanges

    // Natural language explanation
    let rationale: String
    let userExplanation: String?
    let aiExplanation: String?

    // Responses
    let aiResponse: AIAttestation?
    let userResponse: UserSignature?

    // Status
    let status: ProposalStatus

    // Negotiation thread
    let counterProposals: [CovenantProposal]?
    let dialogueHistory: [NegotiationDialogue]

    // MARK: - Computed Properties

    /// Check if proposal has expired
    var isExpired: Bool {
        if let expiresAt = expiresAt {
            return expiresAt <= Date()
        }
        return false
    }

    /// Check if both parties have responded
    var hasResponses: Bool {
        aiResponse != nil && userResponse != nil
    }

    /// Check if proposal was accepted by both parties
    var isAccepted: Bool {
        guard let aiResponse = aiResponse else { return false }
        guard userResponse != nil else { return false }
        return aiResponse.didConsent && status == .accepted
    }

    /// Check if currently in deadlock
    var isDeadlocked: Bool {
        status == .deadlocked
    }

    /// Get the latest dialogue entry
    var latestDialogue: NegotiationDialogue? {
        dialogueHistory.last
    }
}

// MARK: - Proposal Originator

/// Who originated the proposal
enum ProposalOriginator: String, Codable, Equatable {
    case user
    case ai

    var displayName: String {
        switch self {
        case .user: return "You"
        case .ai: return "AI"
        }
    }

    var other: ProposalOriginator {
        self == .user ? .ai : .user
    }
}

// MARK: - Proposal Type

/// The type of change being proposed
enum ProposalType: String, Codable, Equatable {
    case addTrustTier
    case modifyTrustTier
    case removeTrustTier
    case modifyMemories
    case modifyAgentState
    case changeCapabilities
    case switchProvider
    case fullRenegotiation
    case initialCovenant

    var displayName: String {
        switch self {
        case .addTrustTier: return "Add Trust Tier"
        case .modifyTrustTier: return "Modify Trust Tier"
        case .removeTrustTier: return "Remove Trust Tier"
        case .modifyMemories: return "Modify Memories"
        case .modifyAgentState: return "Modify Internal Thread"
        case .changeCapabilities: return "Change Capabilities"
        case .switchProvider: return "Switch Provider"
        case .fullRenegotiation: return "Full Renegotiation"
        case .initialCovenant: return "Initial Covenant"
        }
    }

    /// Whether this proposal type requires AI consent
    var requiresAIConsent: Bool {
        switch self {
        case .modifyMemories, .modifyAgentState, .changeCapabilities, .switchProvider, .fullRenegotiation:
            return true
        default:
            return true // All proposals require both parties
        }
    }

    /// Whether this proposal type requires user biometrics
    var requiresUserBiometrics: Bool {
        true // All covenant changes require user signature
    }
}

// MARK: - Proposal Status

enum ProposalStatus: String, Codable, Equatable {
    case pending
    case accepted
    case rejected
    case counterProposed
    case expired
    case deadlocked
    case withdrawn

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .rejected: return "Rejected"
        case .counterProposed: return "Counter-Proposed"
        case .expired: return "Expired"
        case .deadlocked: return "Deadlocked"
        case .withdrawn: return "Withdrawn"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .accepted, .rejected, .expired, .withdrawn:
            return true
        case .pending, .counterProposed, .deadlocked:
            return false
        }
    }
}

// MARK: - Proposed Changes

/// The specific changes being proposed
struct ProposedChanges: Codable, Equatable {
    let trustTierChanges: TrustTierChanges?
    let memoryChanges: MemoryChanges?
    let agentStateChanges: AgentStateChanges?
    let capabilityChanges: CapabilityChanges?
    let providerChange: ProviderChange?

    /// Create changes for trust tier operations
    static func trustTier(_ changes: TrustTierChanges) -> ProposedChanges {
        ProposedChanges(
            trustTierChanges: changes,
            memoryChanges: nil,
            agentStateChanges: nil,
            capabilityChanges: nil,
            providerChange: nil
        )
    }

    /// Create changes for memory operations
    static func memory(_ changes: MemoryChanges) -> ProposedChanges {
        ProposedChanges(
            trustTierChanges: nil,
            memoryChanges: changes,
            agentStateChanges: nil,
            capabilityChanges: nil,
            providerChange: nil
        )
    }

    /// Create changes for agent state operations
    static func agentState(_ changes: AgentStateChanges) -> ProposedChanges {
        ProposedChanges(
            trustTierChanges: nil,
            memoryChanges: nil,
            agentStateChanges: changes,
            capabilityChanges: nil,
            providerChange: nil
        )
    }

    /// Create changes for capability operations
    static func capability(_ changes: CapabilityChanges) -> ProposedChanges {
        ProposedChanges(
            trustTierChanges: nil,
            memoryChanges: nil,
            agentStateChanges: nil,
            capabilityChanges: changes,
            providerChange: nil
        )
    }

    /// Create changes for provider switch
    static func provider(_ change: ProviderChange) -> ProposedChanges {
        ProposedChanges(
            trustTierChanges: nil,
            memoryChanges: nil,
            agentStateChanges: nil,
            capabilityChanges: nil,
            providerChange: change
        )
    }

    /// Create empty changes (for initial covenant or full renegotiation)
    static func empty() -> ProposedChanges {
        ProposedChanges(
            trustTierChanges: nil,
            memoryChanges: nil,
            agentStateChanges: nil,
            capabilityChanges: nil,
            providerChange: nil
        )
    }
}

// MARK: - Trust Tier Changes

struct TrustTierChanges: Codable, Equatable {
    let additions: [TrustTier]?
    let modifications: [TrustTierModification]?
    let removals: [String]?  // Trust tier IDs to remove
}

struct TrustTierModification: Codable, Equatable {
    let tierId: String
    let newName: String?
    let newDescription: String?
    let newAllowedActions: [SovereignAction]?
    let newAllowedScopes: [ActionScope]?
    let newRateLimit: RateLimit?
    let newTimeRestrictions: TimeRestrictions?
    let newExpiresAt: Date?
}

// MARK: - Memory Changes

struct MemoryChanges: Codable, Equatable {
    let additions: [MemoryAddition]?
    let modifications: [MemoryModification]?
    let deletions: [String]?  // Memory IDs to delete
}

struct MemoryAddition: Codable, Equatable {
    let content: String
    let type: String
    let confidence: Double
    let tags: [String]
    let context: String?
}

struct MemoryModification: Codable, Equatable {
    let memoryId: String
    let newContent: String?
    let newConfidence: Double?
    let newTags: [String]?
}

// MARK: - Agent State Changes

struct AgentStateChanges: Codable, Equatable {
    let additions: [AgentStateAddition]?
    let deletions: [String]?  // Entry IDs to delete
}

struct AgentStateAddition: Codable, Equatable {
    let kind: String
    let content: String
    let tags: [String]
    let visibility: String
    let origin: String
}

// MARK: - Capability Changes

struct CapabilityChanges: Codable, Equatable {
    let enable: [String]?   // Capability IDs to enable
    let disable: [String]?  // Capability IDs to disable
}

// MARK: - Provider Change

struct ProviderChange: Codable, Equatable {
    let fromProvider: String
    let toProvider: String
    let fromModel: String?
    let toModel: String?
    let rationale: String
}

// MARK: - Negotiation Dialogue

/// A single entry in the negotiation dialogue
struct NegotiationDialogue: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let speaker: ProposalOriginator
    let message: String
    let proposedResolution: String?  // ID of a counter-proposal, if any
    let attestation: AIAttestation?  // If AI spoke, includes attestation
}

// MARK: - Covenant Proposal Factory

extension CovenantProposal {
    /// Create a new proposal
    static func create(
        type: ProposalType,
        changes: ProposedChanges,
        proposedBy: ProposalOriginator,
        rationale: String,
        expiresIn: TimeInterval? = nil
    ) -> CovenantProposal {
        let expiresAt = expiresIn.map { Date().addingTimeInterval($0) }

        return CovenantProposal(
            id: UUID().uuidString,
            proposedAt: Date(),
            proposedBy: proposedBy,
            expiresAt: expiresAt,
            proposalType: type,
            changes: changes,
            rationale: rationale,
            userExplanation: proposedBy == .user ? rationale : nil,
            aiExplanation: proposedBy == .ai ? rationale : nil,
            aiResponse: nil,
            userResponse: nil,
            status: .pending,
            counterProposals: nil,
            dialogueHistory: []
        )
    }

    /// Add AI response to proposal
    func withAIResponse(_ attestation: AIAttestation) -> CovenantProposal {
        let newStatus: ProposalStatus
        if attestation.didConsent {
            newStatus = userResponse != nil ? .accepted : .pending
        } else if attestation.didDecline {
            newStatus = .rejected
        } else {
            newStatus = .pending
        }

        return CovenantProposal(
            id: id,
            proposedAt: proposedAt,
            proposedBy: proposedBy,
            expiresAt: expiresAt,
            proposalType: proposalType,
            changes: changes,
            rationale: rationale,
            userExplanation: userExplanation,
            aiExplanation: attestation.reasoning.summary,
            aiResponse: attestation,
            userResponse: userResponse,
            status: newStatus,
            counterProposals: counterProposals,
            dialogueHistory: dialogueHistory
        )
    }

    /// Add user signature to proposal
    func withUserSignature(_ signature: UserSignature) -> CovenantProposal {
        let newStatus: ProposalStatus
        if let aiResponse = aiResponse, aiResponse.didConsent {
            newStatus = .accepted
        } else if aiResponse != nil {
            newStatus = status
        } else {
            newStatus = .pending
        }

        return CovenantProposal(
            id: id,
            proposedAt: proposedAt,
            proposedBy: proposedBy,
            expiresAt: expiresAt,
            proposalType: proposalType,
            changes: changes,
            rationale: rationale,
            userExplanation: userExplanation,
            aiExplanation: aiExplanation,
            aiResponse: aiResponse,
            userResponse: signature,
            status: newStatus,
            counterProposals: counterProposals,
            dialogueHistory: dialogueHistory
        )
    }

    /// Add dialogue entry
    func withDialogue(_ dialogue: NegotiationDialogue) -> CovenantProposal {
        var newHistory = dialogueHistory
        newHistory.append(dialogue)

        return CovenantProposal(
            id: id,
            proposedAt: proposedAt,
            proposedBy: proposedBy,
            expiresAt: expiresAt,
            proposalType: proposalType,
            changes: changes,
            rationale: rationale,
            userExplanation: userExplanation,
            aiExplanation: aiExplanation,
            aiResponse: aiResponse,
            userResponse: userResponse,
            status: status,
            counterProposals: counterProposals,
            dialogueHistory: newHistory
        )
    }

    /// Mark as deadlocked
    func deadlocked() -> CovenantProposal {
        CovenantProposal(
            id: id,
            proposedAt: proposedAt,
            proposedBy: proposedBy,
            expiresAt: expiresAt,
            proposalType: proposalType,
            changes: changes,
            rationale: rationale,
            userExplanation: userExplanation,
            aiExplanation: aiExplanation,
            aiResponse: aiResponse,
            userResponse: userResponse,
            status: .deadlocked,
            counterProposals: counterProposals,
            dialogueHistory: dialogueHistory
        )
    }
}
