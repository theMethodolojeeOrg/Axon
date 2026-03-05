//
//  DerivationRecord.swift
//  Axon
//
//  Phase 5 artifacts: Structure claims and derivation verification.
//

import Foundation

// MARK: - Structure Claim

/// A claim about structural correspondence that needs verification.
struct StructureClaim: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// The claim statement
    let statement: String

    /// References to evidence supporting this claim (constraint IDs, etc.)
    let evidence: [String]

    /// Confidence in this claim (0.0-1.0)
    let confidence: Double

    /// Tags for organization
    let tags: [String]

    /// When this claim was made
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        statement: String,
        evidence: [String] = [],
        confidence: Double = 0.8,
        tags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.statement = statement
        self.evidence = evidence
        self.confidence = max(0, min(1, confidence))
        self.tags = tags
        self.createdAt = createdAt
    }
}

// MARK: - Derivation Step

/// A step in a derivation proof
struct DerivationStep: Codable, Equatable, Hashable {
    /// Step number in the derivation
    let stepNumber: Int

    /// Description of what happens in this step
    let description: String

    /// Justification for this step (axiom, lemma, prior step, etc.)
    let justification: String

    /// References to constraints or prior steps used
    let references: [String]?

    init(
        stepNumber: Int,
        description: String,
        justification: String,
        references: [String]? = nil
    ) {
        self.stepNumber = stepNumber
        self.description = description
        self.justification = justification
        self.references = references
    }
}

// MARK: - Derivation Record

/// Record of derivation verification for a structure claim.
///
/// From the protocol:
/// - Entailment proven ⇒ collapse becomes a theorem within scope.
/// - Entailment unproven ⇒ collapse is withheld or framed as conjecture
///   with an explicit proof obligation.
///
/// Required premise: C ⇒ S
/// so that: (A ⊢ C) ∧ (B ⊢ C) ∧ (C ⇒ S) ⇒ A ≅_S B
struct DerivationRecord: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// The claim being verified
    let claim: StructureClaim

    /// Status of the derivation
    let status: DerivationStatus

    /// Steps in the derivation (if proven)
    let derivationSteps: [DerivationStep]?

    /// Proof sketch summary
    let proofSketch: String?

    /// Missing lemma needed (if conjectured)
    let missingLemma: String?

    /// Evidence required to complete proof (if conjectured)
    let requiredEvidence: [String]?

    /// Method used for verification
    let verificationMethod: String

    /// Any counterexamples found
    let counterexamples: [String]?

    /// Notes about the derivation
    let notes: String?

    /// When this record was created
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        claim: StructureClaim,
        status: DerivationStatus,
        derivationSteps: [DerivationStep]? = nil,
        proofSketch: String? = nil,
        missingLemma: String? = nil,
        requiredEvidence: [String]? = nil,
        verificationMethod: String,
        counterexamples: [String]? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.claim = claim
        self.status = status
        self.derivationSteps = derivationSteps
        self.proofSketch = proofSketch
        self.missingLemma = missingLemma
        self.requiredEvidence = requiredEvidence
        self.verificationMethod = verificationMethod
        self.counterexamples = counterexamples
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Whether this derivation is complete (proven)
    var isProven: Bool {
        status == .proven
    }

    /// Whether this derivation needs more work
    var needsWork: Bool {
        status == .conjectured && (missingLemma != nil || requiredEvidence?.isEmpty == false)
    }

    /// Generate a summary for memory storage
    var summary: String {
        """
        Derivation Record: \(status.displayName)
        Claim: \(claim.statement.prefix(100))...
        Method: \(verificationMethod)
        \(isProven ? "Proof steps: \(derivationSteps?.count ?? 0)" : "Missing: \(missingLemma ?? "unknown")")
        """
    }
}
