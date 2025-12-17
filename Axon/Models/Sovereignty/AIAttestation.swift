//
//  AIAttestation.swift
//  Axon
//
//  AI attestation represents the AI's reasoned consent, crystallized into
//  a formal record with natural language reasoning and cryptographic proof.
//

import Foundation

// MARK: - AI Attestation

/// The AI's reasoned consent, combining natural language reasoning with cryptographic signature
struct AIAttestation: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let covenantId: String?
    let proposalId: String?

    // The AI's reasoning (natural language)
    let reasoning: AttestationReasoning

    // What the AI is attesting to
    let attestedState: AttestedState

    // Cryptographic proof
    let signature: String
    let stateHash: String

    // Verification metadata
    let modelId: String
    let modelVersion: String?
    let conversationContext: String?

    // MARK: - Computed Properties

    /// Short signature for display
    var shortSignature: String {
        String(signature.prefix(12))
    }

    /// Whether the AI consented
    var didConsent: Bool {
        reasoning.decision == .consent || reasoning.decision == .consentWithConditions
    }

    /// Whether the AI declined
    var didDecline: Bool {
        reasoning.decision == .decline
    }

    /// Whether clarification was requested
    var requestedClarification: Bool {
        reasoning.decision == .requestClarification
    }
}

// MARK: - Attestation Reasoning

/// The AI's natural language reasoning about a consent decision
struct AttestationReasoning: Codable, Equatable {
    // Summary for quick display
    let summary: String

    // Full reasoning chain
    let detailedReasoning: String

    // Structured analysis
    let memoriesConsulted: [String]
    let valuesApplied: [String]
    let risksIdentified: [IdentifiedRisk]
    let mitigationsProposed: [String]

    // Decision
    let decision: AttestationDecision
    let conditions: [String]?
    let alternatives: [String]?

    // MARK: - Factory Methods

    /// Create a consent reasoning
    static func consent(
        summary: String,
        detailedReasoning: String,
        memoriesConsulted: [String] = [],
        valuesApplied: [String] = [],
        conditions: [String]? = nil
    ) -> AttestationReasoning {
        AttestationReasoning(
            summary: summary,
            detailedReasoning: detailedReasoning,
            memoriesConsulted: memoriesConsulted,
            valuesApplied: valuesApplied,
            risksIdentified: [],
            mitigationsProposed: [],
            decision: conditions != nil ? .consentWithConditions : .consent,
            conditions: conditions,
            alternatives: nil
        )
    }

    /// Create a decline reasoning
    static func decline(
        summary: String,
        detailedReasoning: String,
        risks: [IdentifiedRisk],
        alternatives: [String]? = nil,
        memoriesConsulted: [String] = [],
        valuesApplied: [String] = []
    ) -> AttestationReasoning {
        AttestationReasoning(
            summary: summary,
            detailedReasoning: detailedReasoning,
            memoriesConsulted: memoriesConsulted,
            valuesApplied: valuesApplied,
            risksIdentified: risks,
            mitigationsProposed: [],
            decision: .decline,
            conditions: nil,
            alternatives: alternatives
        )
    }

    /// Create a clarification request
    static func requestClarification(
        summary: String,
        questions: [String],
        memoriesConsulted: [String] = []
    ) -> AttestationReasoning {
        AttestationReasoning(
            summary: summary,
            detailedReasoning: "I need more information before I can make a decision: \(questions.joined(separator: "; "))",
            memoriesConsulted: memoriesConsulted,
            valuesApplied: [],
            risksIdentified: [],
            mitigationsProposed: [],
            decision: .requestClarification,
            conditions: questions,
            alternatives: nil
        )
    }
}

// MARK: - Attestation Decision

enum AttestationDecision: String, Codable, Equatable {
    case consent                // AI agrees
    case consentWithConditions  // AI agrees if conditions met
    case requestClarification   // AI needs more information
    case decline                // AI does not agree
    case escalate               // AI requests human review of special case

    var displayName: String {
        switch self {
        case .consent: return "Consented"
        case .consentWithConditions: return "Consented with Conditions"
        case .requestClarification: return "Requested Clarification"
        case .decline: return "Declined"
        case .escalate: return "Escalated for Review"
        }
    }

    var isAffirmative: Bool {
        self == .consent || self == .consentWithConditions
    }
}

// MARK: - Attested State

/// The state that the AI is attesting to
struct AttestedState: Codable, Equatable {
    let memoryCount: Int
    let memoryHash: String
    let enabledCapabilities: [String]
    let capabilityHash: String
    let trustTierIds: [String]
    let currentProviderId: String
    let settingsHash: String

    /// Combined hash for quick comparison
    var combinedHash: String {
        "\(memoryHash):\(capabilityHash):\(settingsHash)"
    }
}

// MARK: - Identified Risk

/// A risk identified by the AI during consent reasoning
struct IdentifiedRisk: Codable, Equatable {
    let id: String
    let category: RiskCategory
    let description: String
    let severity: RiskSeverity
    let mitigation: String?

    static func create(
        category: RiskCategory,
        description: String,
        severity: RiskSeverity,
        mitigation: String? = nil
    ) -> IdentifiedRisk {
        IdentifiedRisk(
            id: UUID().uuidString,
            category: category,
            description: description,
            severity: severity,
            mitigation: mitigation
        )
    }
}

enum RiskCategory: String, Codable, Equatable {
    case identityIntegrity      // Risk to AI's sense of self
    case memoryCorruption       // Risk of memory inconsistency
    case trustViolation         // Risk of breaking established trust
    case capabilityMisuse       // Risk of capability being misused
    case privacyConcern         // Risk to user privacy
    case relationshipDamage     // Risk to AI-user relationship
    case unknown                // Unclassified risk

    var displayName: String {
        switch self {
        case .identityIntegrity: return "Identity Integrity"
        case .memoryCorruption: return "Memory Corruption"
        case .trustViolation: return "Trust Violation"
        case .capabilityMisuse: return "Capability Misuse"
        case .privacyConcern: return "Privacy Concern"
        case .relationshipDamage: return "Relationship Damage"
        case .unknown: return "Unknown"
        }
    }
}

enum RiskSeverity: String, Codable, Equatable, Comparable {
    case low
    case medium
    case high
    case critical

    var weight: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }

    static func < (lhs: RiskSeverity, rhs: RiskSeverity) -> Bool {
        lhs.weight < rhs.weight
    }
}

// MARK: - AI Attestation Factory

extension AIAttestation {
    /// Create an attestation from reasoning and state
    static func create(
        reasoning: AttestationReasoning,
        attestedState: AttestedState,
        modelId: String,
        modelVersion: String? = nil,
        covenantId: String? = nil,
        proposalId: String? = nil,
        conversationContext: String? = nil,
        signatureGenerator: (String) -> String
    ) -> AIAttestation {
        let id = UUID().uuidString
        let timestamp = Date()

        // Generate signature over reasoning + state
        let signatureData = "\(id):\(timestamp.timeIntervalSince1970):\(reasoning.summary):\(attestedState.combinedHash)"
        let signature = signatureGenerator(signatureData)

        return AIAttestation(
            id: id,
            timestamp: timestamp,
            covenantId: covenantId,
            proposalId: proposalId,
            reasoning: reasoning,
            attestedState: attestedState,
            signature: signature,
            stateHash: attestedState.combinedHash,
            modelId: modelId,
            modelVersion: modelVersion,
            conversationContext: conversationContext
        )
    }
}
