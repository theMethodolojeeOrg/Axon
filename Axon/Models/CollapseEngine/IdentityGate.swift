//
//  IdentityGate.swift
//  Axon
//
//  Phase 3 artifact: Result of comparing constraint sets.
//

import Foundation

// MARK: - Constraint Pair

/// A pair of matched constraints from the two systems
struct ConstraintPair: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier
    let id: String

    /// Constraint ID from system A
    let constraintAId: String

    /// Constraint ID from system B
    let constraintBId: String

    /// Type of match between the constraints
    let matchType: MatchType

    /// Explanation of the match
    let explanation: String?

    /// Confidence in this pairing (0.0-1.0)
    let confidence: Double

    init(
        id: String = UUID().uuidString,
        constraintAId: String,
        constraintBId: String,
        matchType: MatchType,
        explanation: String? = nil,
        confidence: Double = 0.8
    ) {
        self.id = id
        self.constraintAId = constraintAId
        self.constraintBId = constraintBId
        self.matchType = matchType
        self.explanation = explanation
        self.confidence = max(0, min(1, confidence))
    }
}

// MARK: - Identity Gate Result

/// Result from comparing constraint sets through the identity gate.
///
/// From the protocol:
/// - SIMILAR ⇒ heuristic transfer only; no syllogism.
/// - IDENTICAL (within scope) ⇒ proceed to derivation verification.
/// - DIVERGENT ⇒ revise scope or abandon collapse.
///
/// Only IDENTICAL permits a collapse claim of the form A ≅_S B.
struct IdentityGateResult: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// Reference to constraint set A
    let constraintSetAId: String

    /// Reference to constraint set B
    let constraintSetBId: String

    /// The verdict from the identity gate
    let verdict: IdentityGateVerdict

    /// Pairs of matched constraints
    let matchedPairs: [ConstraintPair]

    /// Constraint IDs from A with no match in B
    let unmatchedA: [String]

    /// Constraint IDs from B with no match in A
    let unmatchedB: [String]

    /// Overall similarity score (0.0-1.0)
    let similarityScore: Double

    /// Scope within which the comparison was made
    let scope: String

    /// Notes about the comparison
    let notes: String?

    /// When this result was created
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        constraintSetAId: String,
        constraintSetBId: String,
        verdict: IdentityGateVerdict,
        matchedPairs: [ConstraintPair],
        unmatchedA: [String],
        unmatchedB: [String],
        similarityScore: Double,
        scope: String,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.constraintSetAId = constraintSetAId
        self.constraintSetBId = constraintSetBId
        self.verdict = verdict
        self.matchedPairs = matchedPairs
        self.unmatchedA = unmatchedA
        self.unmatchedB = unmatchedB
        self.similarityScore = max(0, min(1, similarityScore))
        self.scope = scope
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Number of matched constraint pairs
    var matchedCount: Int { matchedPairs.count }

    /// Total unmatched constraints
    var unmatchedCount: Int { unmatchedA.count + unmatchedB.count }

    /// Percentage of constraints matched
    var matchPercentage: Double {
        let total = matchedCount * 2 + unmatchedA.count + unmatchedB.count
        guard total > 0 else { return 0 }
        return Double(matchedCount * 2) / Double(total)
    }

    /// Whether this result permits proceeding to collapse
    var canProceedToCollapse: Bool {
        verdict == .identical
    }

    /// Generate a summary for memory storage
    var summary: String {
        """
        Identity Gate Result: \(verdict.displayName)
        Matched: \(matchedCount) pairs
        Unmatched: \(unmatchedA.count) from A, \(unmatchedB.count) from B
        Similarity: \(String(format: "%.0f%%", similarityScore * 100))
        Scope: \(scope)
        """
    }
}
