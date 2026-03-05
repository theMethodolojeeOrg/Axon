//
//  ShiftLog.swift
//  Axon
//
//  Shift Log model for epistemic transparency.
//  Records the boundary crossing between Discrete Register (grounded facts)
//  and Continuous Register (LLM inference).
//

import Foundation

// MARK: - Shift Log

/// Records an epistemic grounding operation with full transparency
struct ShiftLog: Identifiable, Codable, Equatable {
    let id: String
    let correlationId: String
    let timestamp: Date

    // Operation details
    let operation: String                // e.g., "Intent Parser → Deterministic Search"
    let userQuery: String
    let parsedIntent: ParsedIntent

    // Grounding results
    let groundingOperation: GroundingOperation
    let retrievedFacts: [GroundedFact]

    // Confidence metrics
    let compositeConfidence: CompositeConfidence

    // Epistemic boundaries (what we know vs. don't know)
    let epistemicScope: EpistemicScope

    init(
        id: String = UUID().uuidString,
        correlationId: String,
        timestamp: Date = Date(),
        operation: String,
        userQuery: String,
        parsedIntent: ParsedIntent,
        groundingOperation: GroundingOperation,
        retrievedFacts: [GroundedFact],
        compositeConfidence: CompositeConfidence,
        epistemicScope: EpistemicScope
    ) {
        self.id = id
        self.correlationId = correlationId
        self.timestamp = timestamp
        self.operation = operation
        self.userQuery = userQuery
        self.parsedIntent = parsedIntent
        self.groundingOperation = groundingOperation
        self.retrievedFacts = retrievedFacts
        self.compositeConfidence = compositeConfidence
        self.epistemicScope = epistemicScope
    }
}

// MARK: - Parsed Intent

/// Extracted constraints from user input
struct ParsedIntent: Codable, Equatable {
    let topics: [String]           // Extracted topics/keywords
    let type: String?              // e.g., "query", "update", "clarification"
    let scope: String              // e.g., "Recent project context"
    let constraints: [String]      // Additional filters

    init(
        topics: [String] = [],
        type: String? = nil,
        scope: String = "General",
        constraints: [String] = []
    ) {
        self.topics = topics
        self.type = type
        self.scope = scope
        self.constraints = constraints
    }
}

// MARK: - Grounding Operation

/// Details of the deterministic search
struct GroundingOperation: Codable, Equatable {
    let query: String              // The set operation performed
    let status: GroundingStatus
    let resultCount: Int
    let searchDurationMs: Double?

    init(
        query: String,
        status: GroundingStatus,
        resultCount: Int,
        searchDurationMs: Double? = nil
    ) {
        self.query = query
        self.status = status
        self.resultCount = resultCount
        self.searchDurationMs = searchDurationMs
    }
}

enum GroundingStatus: String, Codable, Equatable {
    case success = "SUCCESS"
    case partial = "PARTIAL"        // Some constraints couldn't be satisfied
    case noResults = "NO_RESULTS"
    case error = "ERROR"
}

// MARK: - Grounded Fact

/// A single grounded fact from memory
struct GroundedFact: Identifiable, Codable, Equatable {
    let id: String                 // Memory ID
    let content: String
    let confidence: Double         // Individual fact confidence
    let source: String             // Where this fact came from
    let evidence: String?          // Why we trust this fact
    let lastUpdated: Date?

    init(
        id: String,
        content: String,
        confidence: Double,
        source: String,
        evidence: String? = nil,
        lastUpdated: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.confidence = confidence
        self.source = source
        self.evidence = evidence
        self.lastUpdated = lastUpdated
    }

    /// Create from a Memory
    init(from memory: Memory) {
        self.id = memory.id
        self.content = memory.content
        self.confidence = memory.confidence
        self.source = memory.type.displayName
        self.evidence = memory.context
        self.lastUpdated = memory.updatedAt
    }
}

// MARK: - Composite Confidence

/// Compositional confidence metrics
struct CompositeConfidence: Codable, Equatable {
    let formula: String            // e.g., "C_total = ∏(1 - ε_i)"
    let groundingReliability: Double  // How reliable was the retrieval?
    let shiftIntegrity: Double        // How reliable was the boundary crossing?
    let result: Double                // Final composite confidence

    init(
        formula: String = "C_total = ∏(1 - ε_i) × ∏(1 - ε_s)",
        groundingReliability: Double,
        shiftIntegrity: Double,
        result: Double? = nil
    ) {
        self.formula = formula
        self.groundingReliability = groundingReliability
        self.shiftIntegrity = shiftIntegrity
        self.result = result ?? (groundingReliability * shiftIntegrity)
    }

    /// Calculate composite confidence from individual fact confidences
    static func calculate(factConfidences: [Double], shiftIntegrity: Double = 0.98) -> CompositeConfidence {
        guard !factConfidences.isEmpty else {
            return CompositeConfidence(
                groundingReliability: 0.0,
                shiftIntegrity: shiftIntegrity,
                result: 0.0
            )
        }

        // Product of individual reliabilities
        let groundingReliability = factConfidences.reduce(1.0) { $0 * $1 }
        let result = groundingReliability * shiftIntegrity

        return CompositeConfidence(
            groundingReliability: groundingReliability,
            shiftIntegrity: shiftIntegrity,
            result: result
        )
    }
}

// MARK: - Epistemic Scope

/// What we know vs. what we don't know
struct EpistemicScope: Codable, Equatable {
    let grounded: [String]         // What IS grounded truth
    let unknown: [String]          // What we DON'T know
    let assumptions: [String]      // Assumptions we're making
    let gapIdentified: String?     // Key gap in knowledge

    init(
        grounded: [String] = [],
        unknown: [String] = [],
        assumptions: [String] = [],
        gapIdentified: String? = nil
    ) {
        self.grounded = grounded
        self.unknown = unknown
        self.assumptions = assumptions
        self.gapIdentified = gapIdentified
    }
}

// MARK: - Epistemic Context

/// The complete epistemic context provided to the LLM
struct EpistemicContext: Codable, Equatable {
    let shiftLog: ShiftLog
    let groundedFacts: [GroundedFact]
    let compositeConfidence: Double
    let formattedContext: String   // Pre-formatted for injection

    init(shiftLog: ShiftLog, groundedFacts: [GroundedFact], compositeConfidence: Double, formattedContext: String) {
        self.shiftLog = shiftLog
        self.groundedFacts = groundedFacts
        self.compositeConfidence = compositeConfidence
        self.formattedContext = formattedContext
    }
}

// MARK: - Learning Evidence

/// Evidence from the learning loop (prediction vs. outcome)
struct LearningEvidence: Identifiable, Codable, Equatable {
    let id: String
    let memoryId: String
    let timestamp: Date
    let predictionConfidence: Double
    let outcome: LearningOutcome
    let newConditions: [String]?   // Scoping conditions discovered
    let notes: String?

    init(
        id: String = UUID().uuidString,
        memoryId: String,
        timestamp: Date = Date(),
        predictionConfidence: Double,
        outcome: LearningOutcome,
        newConditions: [String]? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.memoryId = memoryId
        self.timestamp = timestamp
        self.predictionConfidence = predictionConfidence
        self.outcome = outcome
        self.newConditions = newConditions
        self.notes = notes
    }
}

enum LearningOutcome: String, Codable, Equatable {
    case confirmed = "confirmed"       // Prediction matched reality
    case contradicted = "contradicted" // Prediction didn't match
    case refined = "refined"           // Partially correct, needs scoping
    case neutral = "neutral"           // Not enough data to judge
}

// MARK: - Memory Extension for Learning

/// Extended memory properties for learning loop
struct MemoryLearningData: Codable, Equatable {
    let memoryId: String
    var successCount: Int
    var failureCount: Int
    var conditions: [String]       // Scoping conditions
    var learningHistory: [LearningEvidence]
    var lastLearningUpdate: Date?

    init(
        memoryId: String,
        successCount: Int = 0,
        failureCount: Int = 0,
        conditions: [String] = [],
        learningHistory: [LearningEvidence] = [],
        lastLearningUpdate: Date? = nil
    ) {
        self.memoryId = memoryId
        self.successCount = successCount
        self.failureCount = failureCount
        self.conditions = conditions
        self.learningHistory = learningHistory
        self.lastLearningUpdate = lastLearningUpdate
    }

    /// Calculated reliability based on success/failure counts
    var reliability: Double {
        let total = successCount + failureCount
        guard total > 0 else { return 0.5 } // No data yet
        return Double(successCount) / Double(total)
    }

    /// Add a learning evidence record
    mutating func addEvidence(_ evidence: LearningEvidence) {
        learningHistory.append(evidence)
        lastLearningUpdate = Date()

        switch evidence.outcome {
        case .confirmed:
            successCount += 1
        case .contradicted:
            failureCount += 1
        case .refined:
            // Refined doesn't change counts but adds conditions
            if let conditions = evidence.newConditions {
                self.conditions.append(contentsOf: conditions)
            }
        case .neutral:
            break
        }
    }
}
