//
//  AnalogCard.swift
//  Axon
//
//  Phase 1 artifact: Captures an initial analogy hypothesis between two systems.
//

import Foundation

// MARK: - System Description

/// Description of a system in an analogy
struct SystemDescription: Codable, Equatable, Hashable {
    /// Name of the system
    let name: String

    /// Domain the system belongs to (e.g., "physics", "biology", "software")
    let domain: String

    /// Description of the system
    let description: String

    /// Key principles or axioms of the system
    let keyPrinciples: [String]?

    init(
        name: String,
        domain: String,
        description: String,
        keyPrinciples: [String]? = nil
    ) {
        self.name = name
        self.domain = domain
        self.description = description
        self.keyPrinciples = keyPrinciples
    }
}

// MARK: - Analog Card

/// An AnalogCard captures the initial analogy hypothesis between two systems.
/// It is the first artifact produced in the Collapse Engine workflow.
///
/// From the protocol:
/// - Treat the analogy as a conjecture requiring constraints, scope, and an explicit "likely breaker."
/// - Preserve the earliest claim before refinement to prevent hindsight reconstruction.
struct AnalogCard: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier for this analog card
    let id: String

    /// Session this card belongs to
    let sessionId: CollapseSessionId

    /// Source system (the known/familiar domain)
    let systemA: SystemDescription

    /// Target system (the domain being explored)
    let systemB: SystemDescription

    /// The hypothesized structural correspondence between systems
    let analogyHypothesis: String

    /// Why this analogy might be generative - what insights could transfer
    let generativePotential: String

    /// Initial confidence level (0.0-1.0)
    let initialConfidence: Double

    /// Predicted transfer - a concrete implication to be tested
    let predictedTransfer: String?

    /// The "scary mismatch" - what's most likely to break the analogy
    let scaryMismatch: String?

    /// Scope hint - boundaries of where the analogy applies
    let scopeHint: String?

    /// Sketch of the initial mapping between elements
    let sketchMapping: [MappingElement]?

    /// Tags for categorization and retrieval
    let tags: [String]

    /// When this card was created
    let createdAt: Date

    /// When this card was last updated
    let updatedAt: Date

    /// Additional metadata
    let metadata: [String: String]?

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        systemA: SystemDescription,
        systemB: SystemDescription,
        analogyHypothesis: String,
        generativePotential: String,
        initialConfidence: Double,
        predictedTransfer: String? = nil,
        scaryMismatch: String? = nil,
        scopeHint: String? = nil,
        sketchMapping: [MappingElement]? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.systemA = systemA
        self.systemB = systemB
        self.analogyHypothesis = analogyHypothesis
        self.generativePotential = generativePotential
        self.initialConfidence = max(0, min(1, initialConfidence))
        self.predictedTransfer = predictedTransfer
        self.scaryMismatch = scaryMismatch
        self.scopeHint = scopeHint
        self.sketchMapping = sketchMapping
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    /// Generate a summary for memory storage
    var summary: String {
        """
        Analog Card: \(systemA.name) ↔ \(systemB.name)
        Hypothesis: \(analogyHypothesis)
        Generative Potential: \(generativePotential)
        Confidence: \(String(format: "%.0f%%", initialConfidence * 100))
        """
    }
}

// MARK: - Mapping Element

/// An element in the sketch mapping between systems
struct MappingElement: Codable, Equatable, Hashable {
    /// Element from system A
    let elementA: String

    /// Corresponding element in system B
    let elementB: String

    /// Description of the correspondence
    let correspondence: String?

    /// Confidence in this specific mapping
    let confidence: Double?

    init(
        elementA: String,
        elementB: String,
        correspondence: String? = nil,
        confidence: Double? = nil
    ) {
        self.elementA = elementA
        self.elementB = elementB
        self.correspondence = correspondence
        self.confidence = confidence
    }
}
