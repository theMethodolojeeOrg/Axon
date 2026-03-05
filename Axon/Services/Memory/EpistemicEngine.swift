//
//  EpistemicEngine.swift
//  Axon
//
//  The Epistemic Gearbox: Converts "World-Uncertainty" into "State-Certainty".
//  Provides the Discrete Register that grounds LLM responses with facts + confidence.
//

import Foundation
import Combine

// MARK: - Epistemic Engine

/// The Discrete Register that grounds LLM context with verifiable facts
@MainActor
class EpistemicEngine: ObservableObject {
    static let shared = EpistemicEngine()

    private let predicateLogger = PredicateLogger.shared

    private init() {}

    // MARK: - Main Grounding Operation

    /// Ground a user message with relevant memories and produce an EpistemicContext
    func ground(
        userMessage: String,
        memories: [Memory],
        correlationId: String
    ) -> EpistemicContext {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. Parse intent from user message
        let parsedIntent = parseIntent(query: userMessage)

        // 2. Perform deterministic search (constraint intersection)
        let filteredMemories = deterministicSearch(
            memories: memories,
            intent: parsedIntent
        )

        // 3. Convert to grounded facts
        let groundedFacts = filteredMemories.map { GroundedFact(from: $0) }

        // 4. Calculate composite confidence
        let factConfidences = groundedFacts.map { $0.confidence }
        let compositeConfidence = CompositeConfidence.calculate(factConfidences: factConfidences)

        // 5. Determine epistemic scope
        let epistemicScope = determineEpistemicScope(
            query: userMessage,
            intent: parsedIntent,
            facts: groundedFacts
        )

        // 6. Build grounding operation record
        let searchDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let groundingOperation = GroundingOperation(
            query: buildQueryDescription(intent: parsedIntent),
            status: groundedFacts.isEmpty ? .noResults : .success,
            resultCount: groundedFacts.count,
            searchDurationMs: searchDuration
        )

        // 7. Create Shift Log
        let shiftLog = ShiftLog(
            correlationId: correlationId,
            operation: "Intent Parser → Deterministic Search → Confidence Calculator",
            userQuery: userMessage,
            parsedIntent: parsedIntent,
            groundingOperation: groundingOperation,
            retrievedFacts: groundedFacts,
            compositeConfidence: compositeConfidence,
            epistemicScope: epistemicScope
        )

        // 8. Log predicate
        predicateLogger.logGrounding(
            query: userMessage,
            factCount: groundedFacts.count,
            confidence: compositeConfidence.result,
            correlationId: correlationId
        )

        // 9. Format context for injection
        let formattedContext = formatContextForLLM(
            facts: groundedFacts,
            confidence: compositeConfidence,
            scope: epistemicScope
        )

        return EpistemicContext(
            shiftLog: shiftLog,
            groundedFacts: groundedFacts,
            compositeConfidence: compositeConfidence.result,
            formattedContext: formattedContext
        )
    }

    // MARK: - Intent Parsing

    /// Parse user query to extract constraints
    func parseIntent(query: String) -> ParsedIntent {
        let lowercased = query.lowercased()

        // Extract topics (simple keyword extraction)
        let topics = extractTopics(from: query)

        // Determine query type
        let type = determineQueryType(from: lowercased)

        // Determine scope
        let scope = determineScope(from: lowercased)

        // Extract any explicit constraints
        let constraints = extractConstraints(from: lowercased)

        return ParsedIntent(
            topics: topics,
            type: type,
            scope: scope,
            constraints: constraints
        )
    }

    private func extractTopics(from query: String) -> [String] {
        // Simple keyword extraction - extract significant words
        let stopWords = Set([
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "shall", "can", "need", "dare",
            "i", "you", "he", "she", "it", "we", "they", "what", "which", "who",
            "whom", "this", "that", "these", "those", "am", "my", "your", "his",
            "her", "its", "our", "their", "me", "him", "us", "them", "and", "or",
            "but", "if", "then", "else", "when", "where", "why", "how", "all",
            "each", "every", "both", "few", "more", "most", "other", "some",
            "such", "no", "nor", "not", "only", "own", "same", "so", "than",
            "too", "very", "just", "about", "also", "like", "for", "with", "to",
            "of", "in", "on", "at", "by", "from", "as"
        ])

        let words = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { $0.count > 2 && !stopWords.contains($0) }

        return Array(Set(words)).prefix(5).map { $0 }
    }

    private func determineQueryType(from query: String) -> String? {
        if query.contains("what") || query.contains("?") {
            return "query"
        } else if query.contains("update") || query.contains("change") || query.contains("set") {
            return "update"
        } else if query.contains("clarif") || query.contains("mean") || query.contains("explain") {
            return "clarification"
        } else if query.contains("remember") || query.contains("recall") || query.contains("remind") {
            return "recall"
        }
        return "general"
    }

    private func determineScope(from query: String) -> String {
        if query.contains("recent") || query.contains("latest") || query.contains("last") {
            return "Recent context"
        } else if query.contains("always") || query.contains("general") || query.contains("usually") {
            return "General knowledge"
        } else if query.contains("project") || query.contains("work") || query.contains("task") {
            return "Project context"
        }
        return "Current conversation"
    }

    private func extractConstraints(from query: String) -> [String] {
        var constraints: [String] = []

        // Time-based constraints
        if query.contains("today") { constraints.append("timeframe=today") }
        if query.contains("yesterday") { constraints.append("timeframe=yesterday") }
        if query.contains("this week") { constraints.append("timeframe=this_week") }

        // Type-based constraints
        if query.contains("preference") { constraints.append("type=allocentric") }
        if query.contains("learned") || query.contains("learning") { constraints.append("type=egoic") }

        return constraints
    }

    // MARK: - Deterministic Search

    /// Perform set intersection over memories based on intent
    private func deterministicSearch(memories: [Memory], intent: ParsedIntent) -> [Memory] {
        var result = memories

        // Filter by topic relevance (if topics extracted)
        if !intent.topics.isEmpty {
            result = result.filter { memory in
                let memoryText = (memory.content + " " + memory.tags.joined(separator: " ")).lowercased()
                return intent.topics.contains { topic in
                    memoryText.contains(topic)
                }
            }
        }

        // Filter by type if constrained
        for constraint in intent.constraints {
            if constraint.starts(with: "type=") {
                let typeValue = String(constraint.dropFirst(5))
                if let memoryType = MemoryType(rawValue: typeValue) {
                    result = result.filter { $0.type == memoryType || $0.type.toNewSchema == memoryType }
                }
            }
        }

        // Filter by recency if scoped
        if intent.scope.contains("Recent") {
            let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            result = result.filter { $0.updatedAt > oneWeekAgo }
        }

        // Sort by confidence and recency
        result.sort { lhs, rhs in
            if abs(lhs.confidence - rhs.confidence) > 0.1 {
                return lhs.confidence > rhs.confidence
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        return result
    }

    private func buildQueryDescription(intent: ParsedIntent) -> String {
        var parts: [String] = ["AllMemories"]

        if !intent.topics.isEmpty {
            parts.append("∩ Topics(\(intent.topics.joined(separator: ", ")))")
        }

        for constraint in intent.constraints {
            parts.append("∩ \(constraint)")
        }

        if intent.scope != "Current conversation" {
            parts.append("∩ Scope(\(intent.scope))")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Epistemic Scope Determination

    private func determineEpistemicScope(
        query: String,
        intent: ParsedIntent,
        facts: [GroundedFact]
    ) -> EpistemicScope {
        var grounded: [String] = []
        var unknown: [String] = []
        var assumptions: [String] = []
        var gapIdentified: String?

        // What we know
        if !facts.isEmpty {
            grounded.append("Exact facts from StoredMemory (\(facts.count) retrieved)")
            grounded.append("Retrieval operation completed successfully")

            let avgConfidence = facts.map { $0.confidence }.reduce(0, +) / Double(facts.count)
            grounded.append("Average fact confidence: \(String(format: "%.0f%%", avgConfidence * 100))")
        }

        // What we don't know
        unknown.append("Whether these facts apply to THIS specific moment")
        unknown.append("Whether context has changed since memories were written")
        unknown.append("What the user's actual current intent is beyond parsed query")

        if facts.isEmpty {
            unknown.append("No directly relevant memories found for this query")
            gapIdentified = "Query may be about a topic not yet captured in memory"
        }

        // Assumptions we're making
        if !intent.topics.isEmpty {
            assumptions.append("Query is about: \(intent.topics.joined(separator: ", "))")
        }
        assumptions.append("Scope: \(intent.scope)")
        if let type = intent.type {
            assumptions.append("Query type: \(type)")
        }

        return EpistemicScope(
            grounded: grounded,
            unknown: unknown,
            assumptions: assumptions,
            gapIdentified: gapIdentified
        )
    }

    // MARK: - Context Formatting

    /// Format the epistemic context for LLM injection
    func formatContextForLLM(
        facts: [GroundedFact],
        confidence: CompositeConfidence,
        scope: EpistemicScope
    ) -> String {
        var lines: [String] = []

        // Header
        lines.append("GROUND TRUTH CONTEXT (Confidence: \(String(format: "%.0f%%", confidence.result * 100)))")
        lines.append(String(repeating: "━", count: 50))

        // Facts section
        if facts.isEmpty {
            lines.append("No directly grounded facts for this query.")
            lines.append("")
        } else {
            lines.append("\(facts.count) grounded facts retrieved from StoredMemory:")
            lines.append("")

            for (index, fact) in facts.enumerated() {
                lines.append("\(index + 1). [\(fact.id.prefix(8))..., conf: \(String(format: "%.0f%%", fact.confidence * 100))] \(fact.content)")
                lines.append("   → Retrieved from: \(fact.source)")
                if let evidence = fact.evidence, !evidence.isEmpty {
                    lines.append("   → Evidence: \(evidence)")
                }
                lines.append("")
            }
        }

        // Confidence breakdown
        lines.append("COMPOSITE CONFIDENCE: \(String(format: "%.0f%%", confidence.result * 100))")
        lines.append("Grounding Reliability (DR execution): \(String(format: "%.0f%%", confidence.groundingReliability * 100))")
        lines.append("Shift Integrity (boundary crossing): \(String(format: "%.0f%%", confidence.shiftIntegrity * 100))")
        lines.append("")

        // Epistemic boundaries
        lines.append("EPISTEMIC BOUNDARIES")
        lines.append(String(repeating: "━", count: 50))

        for item in scope.grounded {
            lines.append("✓ GROUNDED: \(item)")
        }
        for item in scope.unknown {
            lines.append("✗ UNKNOWN: \(item)")
        }
        for item in scope.assumptions {
            lines.append("⚠ ASSUMPTION: \(item)")
        }

        if let gap = scope.gapIdentified {
            lines.append("")
            lines.append("GAP IDENTIFIED: \(gap)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Confidence Adjustment (AMLP)

    /// Adjust confidence based on context transfer (per AMLP principles)
    func adjustConfidence(
        baseConfidence: Double,
        contextSimilarity: ContextSimilarity
    ) -> Double {
        let multiplier: Double
        switch contextSimilarity {
        case .same:
            multiplier = 1.0
        case .similar:
            multiplier = 0.8  // 20% reduction
        case .different:
            multiplier = 0.6  // 40% reduction
        case .fundamentallyNew:
            multiplier = 0.3  // 70% reduction
        }

        return baseConfidence * multiplier
    }
}

// MARK: - Context Similarity

enum ContextSimilarity {
    case same              // Exact same context as grounding
    case similar           // Similar but not identical
    case different         // Substantially different context
    case fundamentallyNew  // Completely new context
}

// MARK: - Epistemic Engine Extensions

extension EpistemicEngine {

    /// Quick grounding with just memories (for simple cases)
    func quickGround(
        query: String,
        memories: [Memory],
        maxFacts: Int = 5
    ) -> (facts: [GroundedFact], confidence: Double) {
        let correlationId = PredicateLogger.shared.startCorrelation()
        defer { PredicateLogger.shared.endCorrelation() }

        let context = ground(
            userMessage: query,
            memories: memories,
            correlationId: correlationId
        )

        let limitedFacts = Array(context.groundedFacts.prefix(maxFacts))
        return (limitedFacts, context.compositeConfidence)
    }

    /// Check if we have sufficient grounding for a query
    func hasSufficientGrounding(
        for query: String,
        memories: [Memory],
        minFacts: Int = 1,
        minConfidence: Double = 0.5
    ) -> Bool {
        let (facts, confidence) = quickGround(query: query, memories: memories)
        return facts.count >= minFacts && confidence >= minConfidence
    }
}
