//
//  GaugeFramework.swift
//  Axon
//
//  Phase 6-7 artifacts: Gauge anchors, shifts, and relativity notes.
//

import Foundation

// MARK: - Gauge Anchor

/// A gauge/representational frame chosen for the analogy.
///
/// From the protocol:
/// A gauge is chosen to stabilize representation and reduce effective complexity
/// by quotienting representational symmetries. Gauge anchoring is treated as an
/// operator that enables ratcheting progress by preventing frame drift.
///
/// Key points:
/// - Choose what is held fixed so operator semantics become stable.
/// - Explicitly list what symmetries are being "modded out."
/// - Record risks of over-anchoring and anchor competition.
struct GaugeAnchor: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// Name of this gauge
    let name: String

    /// Description of what this gauge represents
    let description: String

    /// Symmetries being quotiented (factored out)
    let quotientSymmetries: [String]

    /// Invariants made legible by this gauge choice
    let invariantsMadeLegible: [String]?

    /// Operators stabilized by this gauge
    let operatorsStabilized: [String]?

    /// The representational basis being used
    let representationalBasis: String

    /// Rationale for selecting this gauge
    let selectionRationale: String

    /// Risks of this gauge choice (over-anchoring, competition, etc.)
    let risks: [String]?

    /// When this gauge was created
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        name: String,
        description: String,
        quotientSymmetries: [String],
        invariantsMadeLegible: [String]? = nil,
        operatorsStabilized: [String]? = nil,
        representationalBasis: String,
        selectionRationale: String,
        risks: [String]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.name = name
        self.description = description
        self.quotientSymmetries = quotientSymmetries
        self.invariantsMadeLegible = invariantsMadeLegible
        self.operatorsStabilized = operatorsStabilized
        self.representationalBasis = representationalBasis
        self.selectionRationale = selectionRationale
        self.risks = risks
        self.createdAt = createdAt
    }

    /// Generate a summary for memory storage
    var summary: String {
        """
        Gauge Anchor: \(name)
        Quotients: \(quotientSymmetries.joined(separator: ", "))
        Basis: \(representationalBasis)
        """
    }
}

// MARK: - Gauge Shift

/// Record of a shift from one gauge to another.
///
/// This tracks transformations between representational frames,
/// preserving the ability to translate results across gauges.
struct GaugeShift: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// ID of the gauge being shifted from
    let fromGaugeId: String

    /// ID of the gauge being shifted to
    let toGaugeId: String

    /// The transformation rule between gauges
    let transformationRule: String

    /// Invariants preserved across the shift
    let preservedInvariants: [String]

    /// What changes under this transformation
    let changedUnderTransform: [String]?

    /// Notes about this shift
    let notes: String?

    /// When this shift was recorded
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        fromGaugeId: String,
        toGaugeId: String,
        transformationRule: String,
        preservedInvariants: [String],
        changedUnderTransform: [String]? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.fromGaugeId = fromGaugeId
        self.toGaugeId = toGaugeId
        self.transformationRule = transformationRule
        self.preservedInvariants = preservedInvariants
        self.changedUnderTransform = changedUnderTransform
        self.notes = notes
        self.createdAt = createdAt
    }
}

// MARK: - Gauge Relativity Note

/// Note indexing a claim to its gauge and scope.
///
/// From the protocol (Gauge Relativity Principle):
/// A gauge is not a standard. A gauge is a locally optimal instrument for a
/// declared scope. Subsequent researchers may re-gauge—changing what is held
/// fixed—without invalidating prior work, provided scope and invariants are explicit.
///
/// Key points:
/// - Treat every claim as indexed to (g, scope).
/// - Permit future gauge moves as legitimate continuation, not contradiction.
/// - Provide translation hints where possible.
struct GaugeRelativityNote: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// ID of the claim being indexed
    let claimId: String

    /// ID of the gauge this claim is indexed to
    let gaugeId: String

    /// Scope within which this claim is valid
    let scope: String

    /// Whether re-gauging is permitted
    let permitsReGauging: Bool

    /// Constraints on valid re-gauging
    let reGaugingConstraints: [String]?

    /// Allowable re-gauge targets
    let allowableReGauges: [String]?

    /// Hints for translating to other gauges
    let transformHints: [String]?

    /// Dependencies on scope
    let scopeDependencies: [String]?

    /// Notes about this indexing
    let notes: String?

    /// When this note was created
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        claimId: String,
        gaugeId: String,
        scope: String,
        permitsReGauging: Bool = true,
        reGaugingConstraints: [String]? = nil,
        allowableReGauges: [String]? = nil,
        transformHints: [String]? = nil,
        scopeDependencies: [String]? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.claimId = claimId
        self.gaugeId = gaugeId
        self.scope = scope
        self.permitsReGauging = permitsReGauging
        self.reGaugingConstraints = reGaugingConstraints
        self.allowableReGauges = allowableReGauges
        self.transformHints = transformHints
        self.scopeDependencies = scopeDependencies
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Claim indexing string in the format S = S(g, scope)
    var claimIndexing: String {
        "S = S(\(gaugeId), \(scope))"
    }

    /// Generate a summary for memory storage
    var summary: String {
        """
        Gauge Relativity Note
        Claim indexed to: \(claimIndexing)
        Re-gauging: \(permitsReGauging ? "Permitted" : "Restricted")
        """
    }
}
