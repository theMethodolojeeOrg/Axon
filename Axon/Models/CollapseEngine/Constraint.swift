//
//  Constraint.swift
//  Axon
//
//  Phase 2 artifacts: Constraints extracted from each system.
//

import Foundation

// MARK: - Constraint

/// A single generative constraint extracted from a system.
///
/// From the protocol:
/// - Constraints must be generative: they should explain how the system produces
///   behavior/structure, rather than merely describe surface features.
/// - Do not import constraints across systems "because the analogy says so."
/// - Prefer constraints that, if removed, would destroy the claimed structure.
struct Constraint: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier
    let id: String

    /// Which system this constraint belongs to
    let system: SystemLabel

    /// The constraint statement
    let content: String

    /// Category of constraint
    let category: ConstraintCategory

    /// What this constraint was derived from (principle, axiom, observation)
    let derivedFrom: String?

    /// Evidence supporting this constraint
    let evidence: [String]?

    /// Is this constraint generative (explains behavior) vs descriptive
    let isGenerative: Bool

    /// Confidence in this constraint (0.0-1.0)
    let confidence: Double

    /// Tags for organization
    let tags: [String]

    /// When this constraint was created
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        system: SystemLabel,
        content: String,
        category: ConstraintCategory,
        derivedFrom: String? = nil,
        evidence: [String]? = nil,
        isGenerative: Bool = true,
        confidence: Double = 0.8,
        tags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.system = system
        self.content = content
        self.category = category
        self.derivedFrom = derivedFrom
        self.evidence = evidence
        self.isGenerative = isGenerative
        self.confidence = max(0, min(1, confidence))
        self.tags = tags
        self.createdAt = createdAt
    }

    /// Short summary for display
    var shortSummary: String {
        let prefix = content.prefix(80)
        return content.count > 80 ? "\(prefix)..." : content
    }
}

// MARK: - Constraint Set

/// A set of constraints for one system.
///
/// This represents the complete constraint extraction for either System A or System B
/// in the collapse workflow.
struct ConstraintSet: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// Which system these constraints are for
    let system: SystemLabel

    /// The constraints in this set
    let constraints: [Constraint]

    /// Method used for extraction
    let extractionMethod: ExtractionMethod

    /// Notes about the extraction process
    let extractionNotes: String?

    /// When this set was created
    let createdAt: Date

    /// When this set was last updated
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        system: SystemLabel,
        constraints: [Constraint],
        extractionMethod: ExtractionMethod = .manual,
        extractionNotes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.system = system
        self.constraints = constraints
        self.extractionMethod = extractionMethod
        self.extractionNotes = extractionNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Number of constraints
    var count: Int { constraints.count }

    /// Constraints grouped by category
    var byCategory: [ConstraintCategory: [Constraint]] {
        Dictionary(grouping: constraints, by: { $0.category })
    }

    /// Only generative constraints
    var generativeConstraints: [Constraint] {
        constraints.filter { $0.isGenerative }
    }

    /// Average confidence across all constraints
    var averageConfidence: Double {
        guard !constraints.isEmpty else { return 0 }
        return constraints.reduce(0) { $0 + $1.confidence } / Double(constraints.count)
    }

    /// Generate a summary for memory storage
    var summary: String {
        """
        Constraint Set for System \(system.rawValue)
        Count: \(count) constraints
        Categories: \(byCategory.keys.map { $0.displayName }.joined(separator: ", "))
        Extraction: \(extractionMethod.displayName)
        Avg Confidence: \(String(format: "%.0f%%", averageConfidence * 100))
        """
    }
}

// MARK: - Extraction Method

/// Method used to extract constraints
enum ExtractionMethod: String, Codable, Equatable {
    case manual = "MANUAL"
    case scoutAgent = "SCOUT_AGENT"
    case parallelScouts = "PARALLEL_SCOUTS"
    case hybrid = "HYBRID"

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .scoutAgent: return "Scout Agent"
        case .parallelScouts: return "Parallel Scouts"
        case .hybrid: return "Hybrid"
        }
    }
}
