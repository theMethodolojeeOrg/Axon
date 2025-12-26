//
//  CollapseStatement.swift
//  Axon
//
//  Phase 8 artifact: Final verdict of the collapse engine.
//

import Foundation

// MARK: - Collapse Statement

/// Final verdict of the collapse engine.
///
/// From the protocol:
/// - Collapse: "isomorphic with respect to S" (scoped) → A ≅_S B
/// - Refusal: "heuristic mapping only" (no deductive transfer) →
///   C_A ≢ C_B ∨ ¬(C ⇒ S) ⇒ Analogy-only
struct CollapseStatement: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// The verdict: COLLAPSED or ANALOGY_ONLY
    let verdict: CollapseStatus

    /// Summary of the collapse decision
    let summary: String

    /// The structure S that was claimed/tested
    let structureS: String

    /// Constraints that supported the collapse
    let constraintsUsed: [String]

    /// Structural claims that held
    let structurePreserved: [String]

    /// Structural claims that couldn't be mapped
    let structureLost: [String]

    /// Overall confidence score (0.0-1.0)
    let confidenceScore: Double

    /// ID of the gauge used for this statement
    let gaugeUsed: String?

    /// Scope within which the statement is valid
    let scope: String

    /// Justification for the verdict
    let justification: String

    /// Recommendations for future work
    let recommendations: [String]?

    /// When this statement was generated
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        verdict: CollapseStatus,
        summary: String,
        structureS: String,
        constraintsUsed: [String] = [],
        structurePreserved: [String] = [],
        structureLost: [String] = [],
        confidenceScore: Double,
        gaugeUsed: String? = nil,
        scope: String,
        justification: String,
        recommendations: [String]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.verdict = verdict
        self.summary = summary
        self.structureS = structureS
        self.constraintsUsed = constraintsUsed
        self.structurePreserved = structurePreserved
        self.structureLost = structureLost
        self.confidenceScore = max(0, min(1, confidenceScore))
        self.gaugeUsed = gaugeUsed
        self.scope = scope
        self.justification = justification
        self.recommendations = recommendations
        self.createdAt = createdAt
    }

    /// Whether the analogy collapsed successfully
    var isCollapsed: Bool {
        verdict == .collapsed
    }

    /// Formal statement of the collapse
    var formalStatement: String {
        if isCollapsed {
            return "A ≅_{\(structureS)} B within scope: \(scope)"
        } else {
            return "A ~ B (heuristic only, no deductive transfer)"
        }
    }

    /// Generate a comprehensive summary for memory storage
    var memorySummary: String {
        """
        Collapse Statement: \(verdict.displayName)
        \(formalStatement)

        Summary: \(summary)

        Confidence: \(String(format: "%.0f%%", confidenceScore * 100))
        Structure preserved: \(structurePreserved.count) claims
        Structure lost: \(structureLost.count) claims

        Justification: \(justification)
        """
    }
}
