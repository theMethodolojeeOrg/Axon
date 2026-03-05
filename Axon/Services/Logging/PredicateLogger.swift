//
//  PredicateLogger.swift
//  Axon
//
//  Formal predicate logging system for runtime verification.
//  Every operation is a typed predicate claim forming proof trees.
//

import Foundation
import Combine

// MARK: - Predicate Log Model

/// A single predicate log entry - a truth claim about an operation
struct PredicateLog: Identifiable, Equatable {
    let id: String
    let event: String              // e.g., "memory_search", "conversation_send"
    let predicate: String          // The truth claim, e.g., "search_returned_results"
    let passed: Bool               // Did the predicate hold true?
    let scope: PredicateScope      // Infrastructure, service, domain, or user-facing
    let metadata: [String: String] // Simplified metadata as string key-value pairs
    let correlationId: String      // Links related predicates together
    let timestamp: Date
    var parentPredicateId: String? // Forms the proof tree
    var childPredicateIds: [String]

    init(
        id: String = UUID().uuidString,
        event: String,
        predicate: String,
        passed: Bool,
        scope: PredicateScope,
        metadata: [String: String] = [:],
        correlationId: String = UUID().uuidString,
        timestamp: Date = Date(),
        parentPredicateId: String? = nil,
        childPredicateIds: [String] = []
    ) {
        self.id = id
        self.event = event
        self.predicate = predicate
        self.passed = passed
        self.scope = scope
        self.metadata = metadata
        self.correlationId = correlationId
        self.timestamp = timestamp
        self.parentPredicateId = parentPredicateId
        self.childPredicateIds = childPredicateIds
    }
}

/// Scope levels for predicates (from infrastructure to user-facing)
enum PredicateScope: String, Codable, CaseIterable {
    case infra = "infra"           // Network, storage, system calls
    case service = "service"       // Service-level operations
    case domain = "domain"         // Business logic
    case userFacing = "user-facing" // Visible to user

    var priority: Int {
        switch self {
        case .infra: return 0
        case .service: return 1
        case .domain: return 2
        case .userFacing: return 3
        }
    }
}

// MARK: - Predicate Logger Service

/// Main service for logging predicates and forming proof trees
@MainActor
class PredicateLogger: ObservableObject {
    static let shared = PredicateLogger()

    @Published private(set) var predicates: [PredicateLog] = []
    @Published private(set) var currentCorrelationId: String?

    /// Stack of parent predicate IDs for forming trees
    private var parentStack: [String] = []

    /// In-memory index by correlation ID for fast lookup
    private var correlationIndex: [String: [String]] = [:]

    private init() {}

    // MARK: - Correlation Context

    /// Start a new correlation context (e.g., for a user request)
    func startCorrelation() -> String {
        let correlationId = UUID().uuidString
        currentCorrelationId = correlationId
        parentStack.removeAll()
        return correlationId
    }

    /// End the current correlation context
    func endCorrelation() {
        currentCorrelationId = nil
        parentStack.removeAll()
    }

    // MARK: - Logging

    /// Log a predicate and return its ID
    @discardableResult
    func log(
        event: String,
        predicate: String,
        passed: Bool,
        scope: PredicateScope,
        metadata: [String: String] = [:],
        correlationId: String? = nil
    ) -> String {
        let effectiveCorrelationId = correlationId ?? currentCorrelationId ?? UUID().uuidString
        let parentId = parentStack.last

        let log = PredicateLog(
            event: event,
            predicate: predicate,
            passed: passed,
            scope: scope,
            metadata: metadata,
            correlationId: effectiveCorrelationId,
            parentPredicateId: parentId
        )

        // Add to predicates array
        predicates.append(log)

        // Update correlation index
        var ids = correlationIndex[effectiveCorrelationId] ?? []
        ids.append(log.id)
        correlationIndex[effectiveCorrelationId] = ids

        // Update parent's children
        if let parentId = parentId,
           let parentIndex = predicates.firstIndex(where: { $0.id == parentId }) {
            predicates[parentIndex].childPredicateIds.append(log.id)
        }

        #if DEBUG
        let statusIcon = passed ? "✅" : "❌"
        print("[Predicate] \(statusIcon) [\(scope.rawValue)] \(event): \(predicate)")
        #endif

        return log.id
    }

    /// Log and push onto parent stack (for nested operations)
    @discardableResult
    func logAndPush(
        event: String,
        predicate: String,
        passed: Bool,
        scope: PredicateScope,
        metadata: [String: String] = [:],
        correlationId: String? = nil
    ) -> String {
        let id = log(
            event: event,
            predicate: predicate,
            passed: passed,
            scope: scope,
            metadata: metadata,
            correlationId: correlationId
        )
        parentStack.append(id)
        return id
    }

    /// Pop from parent stack (end a nested operation)
    func pop() {
        _ = parentStack.popLast()
    }

    // MARK: - Querying

    /// Get all predicates for a correlation
    func predicates(for correlationId: String) -> [PredicateLog] {
        let ids = correlationIndex[correlationId] ?? []
        return predicates.filter { ids.contains($0.id) }
    }

    /// Get root predicates (no parent) for a correlation
    func rootPredicates(for correlationId: String) -> [PredicateLog] {
        predicates(for: correlationId).filter { $0.parentPredicateId == nil }
    }

    /// Get children of a predicate
    func children(of predicateId: String) -> [PredicateLog] {
        guard let predicate = predicates.first(where: { $0.id == predicateId }) else {
            return []
        }
        return predicates.filter { predicate.childPredicateIds.contains($0.id) }
    }

    /// Build a proof tree for a correlation
    func proofTree(for correlationId: String) -> [PredicateProofNode] {
        let roots = rootPredicates(for: correlationId)
        return roots.map { buildProofNode(from: $0) }
    }

    private func buildProofNode(from predicate: PredicateLog) -> PredicateProofNode {
        let childNodes = children(of: predicate.id).map { buildProofNode(from: $0) }
        return PredicateProofNode(predicate: predicate, children: childNodes)
    }

    /// Calculate composite reliability for a correlation
    func compositeReliability(for correlationId: String) -> Double {
        let logs = predicates(for: correlationId)
        guard !logs.isEmpty else { return 1.0 }

        // Product of (1 - error_rate) for each predicate
        // For simplicity, we treat passed as 1.0 and failed as 0.0
        let passedCount = logs.filter { $0.passed }.count
        return Double(passedCount) / Double(logs.count)
    }

    // MARK: - Cleanup

    /// Clear predicates older than a duration
    func clearOlderThan(_ interval: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-interval)
        let toRemove = predicates.filter { $0.timestamp < cutoff }
        let removeIds = Set(toRemove.map { $0.id })

        predicates.removeAll { removeIds.contains($0.id) }

        // Clean up correlation index
        for (correlationId, ids) in correlationIndex {
            correlationIndex[correlationId] = ids.filter { !removeIds.contains($0) }
            if correlationIndex[correlationId]?.isEmpty == true {
                correlationIndex.removeValue(forKey: correlationId)
            }
        }
    }

    /// Clear all predicates
    func clearAll() {
        predicates.removeAll()
        correlationIndex.removeAll()
        parentStack.removeAll()
        currentCorrelationId = nil
    }
}

// MARK: - Proof Tree Node

/// A node in the proof tree
struct PredicateProofNode: Identifiable {
    let predicate: PredicateLog
    let children: [PredicateProofNode]

    var id: String { predicate.id }

    /// Whether this node and all its children passed
    var allPassed: Bool {
        predicate.passed && children.allSatisfy { $0.allPassed }
    }

    /// Total count of predicates in this subtree
    var totalCount: Int {
        1 + children.reduce(0) { $0 + $1.totalCount }
    }

    /// Count of passed predicates in this subtree
    var passedCount: Int {
        (predicate.passed ? 1 : 0) + children.reduce(0) { $0 + $1.passedCount }
    }

    /// Reliability of this subtree
    var reliability: Double {
        Double(passedCount) / Double(totalCount)
    }
}

// MARK: - Convenience Extensions

extension PredicateLogger {

    // MARK: - Memory Operations

    func logMemorySearch(query: String, resultCount: Int, correlationId: String? = nil) -> String {
        log(
            event: "memory_search",
            predicate: "search_returned_\(resultCount)_results",
            passed: true,
            scope: .service,
            metadata: [
                "query": query,
                "resultCount": String(resultCount)
            ],
            correlationId: correlationId
        )
    }

    func logMemoryRetrieve(memoryId: String, found: Bool, correlationId: String? = nil) -> String {
        log(
            event: "memory_retrieve",
            predicate: found ? "memory_found" : "memory_not_found",
            passed: found,
            scope: .service,
            metadata: ["memoryId": memoryId],
            correlationId: correlationId
        )
    }

    func logMemoryCreate(memoryId: String, type: String, confidence: Double, correlationId: String? = nil) -> String {
        log(
            event: "memory_create",
            predicate: "memory_created_successfully",
            passed: true,
            scope: .service,
            metadata: [
                "memoryId": memoryId,
                "type": type,
                "confidence": String(confidence)
            ],
            correlationId: correlationId
        )
    }

    // MARK: - Epistemic Operations

    func logGrounding(query: String, factCount: Int, confidence: Double, correlationId: String? = nil) -> String {
        log(
            event: "epistemic_grounding",
            predicate: "grounded_\(factCount)_facts",
            passed: factCount > 0 || confidence >= 0.5,
            scope: .domain,
            metadata: [
                "query": query,
                "factCount": String(factCount),
                "confidence": String(confidence)
            ],
            correlationId: correlationId
        )
    }

    func logSalienceInjection(memoryCount: Int, tokenCount: Int, correlationId: String? = nil) -> String {
        log(
            event: "salience_injection",
            predicate: "injected_\(memoryCount)_memories",
            passed: true,
            scope: .domain,
            metadata: [
                "memoryCount": String(memoryCount),
                "tokenCount": String(tokenCount)
            ],
            correlationId: correlationId
        )
    }

    // MARK: - LLM Operations

    func logLLMRequest(provider: String, model: String, correlationId: String? = nil) -> String {
        logAndPush(
            event: "llm_request",
            predicate: "request_initiated",
            passed: true,
            scope: .infra,
            metadata: [
                "provider": provider,
                "model": model
            ],
            correlationId: correlationId
        )
    }

    func logLLMResponse(success: Bool, tokenCount: Int? = nil, error: String? = nil, correlationId: String? = nil) -> String {
        defer { pop() }
        var meta: [String: String] = [:]
        if let tc = tokenCount { meta["tokenCount"] = String(tc) }
        if let err = error { meta["error"] = err }
        return log(
            event: "llm_response",
            predicate: success ? "response_received" : "response_failed",
            passed: success,
            scope: .infra,
            metadata: meta,
            correlationId: correlationId
        )
    }

    // MARK: - Learning Operations

    func logPrediction(content: String, confidence: Double, correlationId: String? = nil) -> String {
        log(
            event: "learning_prediction",
            predicate: "prediction_made",
            passed: true,
            scope: .domain,
            metadata: [
                "contentPreview": String(content.prefix(100)),
                "confidence": String(confidence)
            ],
            correlationId: correlationId
        )
    }

    func logOutcome(matchesPrediction: Bool, memoryUpdates: Int, correlationId: String? = nil) -> String {
        log(
            event: "learning_outcome",
            predicate: matchesPrediction ? "prediction_confirmed" : "prediction_contradicted",
            passed: true, // The outcome itself always passes - it's truth
            scope: .domain,
            metadata: [
                "matchesPrediction": String(matchesPrediction),
                "memoryUpdates": String(memoryUpdates)
            ],
            correlationId: correlationId
        )
    }
}
