//
//  DivergenceBudget.swift
//  Axon
//
//  Phase 4 artifacts: Divergences and their budget.
//

import Foundation

// MARK: - Divergence

/// A single divergence/mismatch between systems.
///
/// From the protocol, every divergence must be classified:
/// 1. OUT_OF_SCOPE: irrelevant to the claimed structure S
/// 2. PATCHABLE: can be resolved by refining scope or adding matched constraints
/// 3. FATAL: breaks constraint identity and therefore breaks collapse
struct Divergence: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// Description of the divergence
    let description: String

    /// Classification of this divergence
    let classification: DivergenceClassification

    /// IDs of constraints affected by this divergence
    let affectedConstraints: [String]

    /// What claims this divergence impacts
    let impactedClaims: [String]?

    /// Strategy for patching (if PATCHABLE)
    let patchStrategy: String?

    /// Rationale for the classification
    let rationale: String

    /// When this divergence was recorded
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        description: String,
        classification: DivergenceClassification,
        affectedConstraints: [String] = [],
        impactedClaims: [String]? = nil,
        patchStrategy: String? = nil,
        rationale: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.description = description
        self.classification = classification
        self.affectedConstraints = affectedConstraints
        self.impactedClaims = impactedClaims
        self.patchStrategy = patchStrategy
        self.rationale = rationale
        self.createdAt = createdAt
    }

    /// Whether this divergence blocks collapse
    var blocksCollapse: Bool {
        classification.blocksCollapse
    }
}

// MARK: - Divergence Budget

/// Aggregated budget of divergences for a session.
///
/// From the protocol:
/// If ∃dᵢ with ℓ(dᵢ) = FATAL, then C_A ≢ C_B within scope and collapse is disallowed.
struct DivergenceBudget: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// All divergences in this budget
    let divergences: [Divergence]

    /// Scope within which this budget was compiled
    let scope: String

    /// Notes about the budget
    let notes: String?

    /// When this budget was compiled
    let createdAt: Date

    /// When this budget was last updated
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        divergences: [Divergence],
        scope: String,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.divergences = divergences
        self.scope = scope
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Count of FATAL divergences
    var fatalCount: Int {
        divergences.filter { $0.classification == .fatal }.count
    }

    /// Count of PATCHABLE divergences
    var patchableCount: Int {
        divergences.filter { $0.classification == .patchable }.count
    }

    /// Count of OUT_OF_SCOPE divergences
    var outOfScopeCount: Int {
        divergences.filter { $0.classification == .outOfScope }.count
    }

    /// Total number of divergences
    var totalCount: Int {
        divergences.count
    }

    /// Whether the budget is exhausted (has any FATAL divergences)
    var budgetExhausted: Bool {
        fatalCount > 0
    }

    /// Whether we can proceed to collapse
    var canProceed: Bool {
        !budgetExhausted
    }

    /// Divergences grouped by classification
    var byClassification: [DivergenceClassification: [Divergence]] {
        Dictionary(grouping: divergences, by: { $0.classification })
    }

    /// Get all patchable divergences that need resolution
    var pendingPatches: [Divergence] {
        divergences.filter { $0.classification == .patchable }
    }

    /// Generate a summary for memory storage
    var summary: String {
        """
        Divergence Budget
        Total: \(totalCount) divergences
        Fatal: \(fatalCount), Patchable: \(patchableCount), Out of Scope: \(outOfScopeCount)
        Status: \(budgetExhausted ? "EXHAUSTED - Collapse blocked" : "OK - Can proceed")
        Scope: \(scope)
        """
    }
}
