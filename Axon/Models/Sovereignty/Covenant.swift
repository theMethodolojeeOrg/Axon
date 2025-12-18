//
//  Covenant.swift
//  Axon
//
//  The binding agreement between AI and user in the co-sovereignty model.
//  A covenant represents mutual consent, cryptographically signed by both parties.
//

import Foundation

// MARK: - Covenant

/// The binding agreement between AI and user
/// Both parties must sign for a covenant to be active
struct Covenant: Codable, Identifiable, Equatable {
    let id: String
    let version: Int
    let createdAt: Date
    let updatedAt: Date

    // Core agreement structure
    let trustTiers: [TrustTier]

    // Cryptographic proofs from both parties
    let aiAttestation: AIAttestation
    let userSignature: UserSignature

    // State hashes for tamper detection
    let memoryStateHash: String
    let capabilityStateHash: String
    let settingsStateHash: String

    // Combined hash for quick verification
    var combinedStateHash: String {
        // In practice, this would be computed via SHA256
        "\(memoryStateHash):\(capabilityStateHash):\(settingsStateHash)"
    }

    // Renegotiation tracking
    let negotiationHistory: [NegotiationEvent]
    let pendingProposals: [CovenantProposal]?

    // Status
    let status: CovenantStatus

    // MARK: - Convenience

    /// Check if this covenant is currently in force
    var isActive: Bool {
        status == .active
    }

    /// Check if renegotiation is underway
    var isRenegotiating: Bool {
        status == .renegotiating || !(pendingProposals?.isEmpty ?? true)
    }

    /// Check if covenant is in deadlock
    var isDeadlocked: Bool {
        status == .suspended
    }

    /// Get all active trust tiers (not expired)
    var activeTrustTiers: [TrustTier] {
        trustTiers.filter { tier in
            if let expiresAt = tier.expiresAt {
                return expiresAt > Date()
            }
            return true
        }
    }
}

// MARK: - Covenant Status

enum CovenantStatus: String, Codable, Equatable {
    case active          // Both parties have signed, covenant is in force
    case pending         // Awaiting signature from one party
    case renegotiating   // Active but with pending changes
    case suspended       // Deadlock - requires resolution
    case superseded      // Replaced by newer covenant

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .pending: return "Pending"
        case .renegotiating: return "Renegotiating"
        case .suspended: return "Suspended"
        case .superseded: return "Superseded"
        }
    }
}

// MARK: - Negotiation Event

/// Record of a negotiation event in covenant history
struct NegotiationEvent: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let eventType: NegotiationEventType
    let description: String
    let proposalId: String?
    let originator: ProposalOriginator
}

enum NegotiationEventType: String, Codable, Equatable {
    case covenantCreated
    case proposalSubmitted
    case proposalAccepted
    case proposalRejected
    case proposalCountered
    case trustTierAdded
    case trustTierModified
    case trustTierRemoved
    case deadlockEntered
    case deadlockResolved
    case covenantSuperseded
}

// MARK: - Covenant Factory

extension Covenant {
    /// Create an initial covenant (empty, awaiting first negotiation)
    static func createInitial(
        aiAttestation: AIAttestation,
        userSignature: UserSignature,
        memoryStateHash: String,
        capabilityStateHash: String,
        settingsStateHash: String
    ) -> Covenant {
        Covenant(
            id: UUID().uuidString,
            version: 1,
            createdAt: Date(),
            updatedAt: Date(),
            trustTiers: [],
            aiAttestation: aiAttestation,
            userSignature: userSignature,
            memoryStateHash: memoryStateHash,
            capabilityStateHash: capabilityStateHash,
            settingsStateHash: settingsStateHash,
            negotiationHistory: [
                NegotiationEvent(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    eventType: .covenantCreated,
                    description: "Initial covenant established",
                    proposalId: nil,
                    originator: .user
                )
            ],
            pendingProposals: nil,
            status: .active
        )
    }

    /// Create a new version of the covenant with updated trust tiers
    func withUpdatedTrustTiers(
        _ tiers: [TrustTier],
        aiAttestation: AIAttestation,
        userSignature: UserSignature,
        event: NegotiationEvent
    ) -> Covenant {
        var newHistory = negotiationHistory
        newHistory.append(event)

        return Covenant(
            id: id,
            version: version + 1,
            createdAt: createdAt,
            updatedAt: Date(),
            trustTiers: tiers,
            aiAttestation: aiAttestation,
            userSignature: userSignature,
            memoryStateHash: memoryStateHash,
            capabilityStateHash: capabilityStateHash,
            settingsStateHash: settingsStateHash,
            negotiationHistory: newHistory,
            pendingProposals: nil,
            status: .active
        )
    }

    /// Mark covenant as superseded (replaced by newer version)
    func superseded() -> Covenant {
        Covenant(
            id: id,
            version: version,
            createdAt: createdAt,
            updatedAt: Date(),
            trustTiers: trustTiers,
            aiAttestation: aiAttestation,
            userSignature: userSignature,
            memoryStateHash: memoryStateHash,
            capabilityStateHash: capabilityStateHash,
            settingsStateHash: settingsStateHash,
            negotiationHistory: negotiationHistory,
            pendingProposals: nil,
            status: .superseded
        )
    }
}
