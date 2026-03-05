//
//  LearningLoopService.swift
//  Axon
//
//  Feedback-driven memory refinement.
//  When prediction ≠ reality, that's data. Update memories. Get smarter next time.
//

import Foundation
import Combine

// MARK: - Learning Loop Service

/// Service for processing feedback and refining memories
@MainActor
class LearningLoopService: ObservableObject {
    static let shared = LearningLoopService()

    private let predicateLogger = PredicateLogger.shared

    /// In-memory storage for learning data (keyed by memory ID)
    @Published private(set) var learningData: [String: MemoryLearningData] = [:]

    /// Pending predictions awaiting outcomes
    @Published private(set) var pendingPredictions: [Prediction] = []

    /// Recent learning events for UI display
    @Published private(set) var recentLearningEvents: [LearningEvent] = []

    private init() {}

    // MARK: - Prediction Tracking

    /// Record a prediction made by the system
    func recordPrediction(
        content: String,
        confidence: Double,
        basedOnMemories: [Memory],
        correlationId: String
    ) -> String {
        let prediction = Prediction(
            content: content,
            confidence: confidence,
            memoryIds: basedOnMemories.map { $0.id },
            correlationId: correlationId
        )

        pendingPredictions.append(prediction)

        // Log the prediction
        predicateLogger.logPrediction(
            content: content,
            confidence: confidence,
            correlationId: correlationId
        )

        #if DEBUG
        print("[LearningLoop] Recorded prediction: \(content.prefix(50))... (conf: \(confidence))")
        #endif

        return prediction.id
    }

    // MARK: - Feedback Processing

    /// Process user feedback on a prediction
    func processUserFeedback(
        userMessage: String,
        previousResponse: String,
        usedMemories: [Memory],
        correlationId: String
    ) -> LearningResult {
        // 1. Detect if this is a contradiction
        let contradictionAnalysis = analyzeForContradiction(
            userMessage: userMessage,
            previousResponse: previousResponse
        )

        // 2. Find matching pending prediction
        let matchingPrediction = findMatchingPrediction(
            correlationId: correlationId,
            response: previousResponse
        )

        // 3. Determine outcome
        let outcome = determineOutcome(
            analysis: contradictionAnalysis,
            prediction: matchingPrediction
        )

        // 4. Update memory learning data
        var updatedMemories: [String] = []
        for memory in usedMemories {
            updateLearningData(
                memoryId: memory.id,
                outcome: outcome,
                analysis: contradictionAnalysis
            )
            updatedMemories.append(memory.id)
        }

        // 5. Create learning event
        let event = LearningEvent(
            correlationId: correlationId,
            outcome: outcome,
            contradictionDetected: contradictionAnalysis.isContradiction,
            affectedMemoryIds: updatedMemories,
            userFeedback: userMessage,
            systemResponse: previousResponse
        )
        recentLearningEvents.insert(event, at: 0)

        // Keep only recent events
        if recentLearningEvents.count > 50 {
            recentLearningEvents = Array(recentLearningEvents.prefix(50))
        }

        // 6. Log outcome
        predicateLogger.logOutcome(
            matchesPrediction: !contradictionAnalysis.isContradiction,
            memoryUpdates: updatedMemories.count,
            correlationId: correlationId
        )

        // 7. Remove matched prediction
        if let prediction = matchingPrediction {
            pendingPredictions.removeAll { $0.id == prediction.id }
        }

        #if DEBUG
        print("[LearningLoop] Processed feedback - Outcome: \(outcome), Updated \(updatedMemories.count) memories")
        #endif

        return LearningResult(
            outcome: outcome,
            updatedMemoryIds: updatedMemories,
            contradictionAnalysis: contradictionAnalysis,
            event: event
        )
    }

    // MARK: - Contradiction Analysis

    /// Analyze user message for contradictions with previous response
    private func analyzeForContradiction(
        userMessage: String,
        previousResponse: String
    ) -> ContradictionAnalysis {
        let lowercasedUser = userMessage.lowercased()

        // Contradiction indicators
        let contradictionPhrases = [
            "no, ", "no.", "not ", "actually", "wrong", "incorrect", "that's not",
            "i didn't", "i don't", "we didn't", "we don't", "you're wrong",
            "that's incorrect", "not quite", "not really", "the opposite",
            "on the contrary", "but actually", "but really", "but i",
            "however", "in fact", "correction", "let me correct"
        ]

        let clarificationPhrases = [
            "i meant", "what i meant", "to clarify", "to be clear",
            "specifically", "more precisely", "let me explain",
            "what i'm saying is", "my point is"
        ]

        let confirmationPhrases = [
            "yes", "correct", "right", "exactly", "that's right",
            "perfect", "good", "thanks", "thank you", "great"
        ]

        // Check for contradiction
        var contradictionScore: Double = 0.0
        var matchedIndicators: [String] = []

        for phrase in contradictionPhrases {
            if lowercasedUser.contains(phrase) {
                contradictionScore += 0.3
                matchedIndicators.append(phrase)
            }
        }

        // Check for clarification (partial contradiction)
        for phrase in clarificationPhrases {
            if lowercasedUser.contains(phrase) {
                contradictionScore += 0.15
                matchedIndicators.append(phrase)
            }
        }

        // Check for confirmation (reduces contradiction score)
        for phrase in confirmationPhrases {
            if lowercasedUser.hasPrefix(phrase) || lowercasedUser.contains(" \(phrase)") {
                contradictionScore -= 0.2
            }
        }

        let isContradiction = contradictionScore >= 0.3
        let type: ContradictionType = {
            if contradictionScore >= 0.5 { return .direct }
            if contradictionScore >= 0.3 { return .partial }
            if contradictionScore >= 0.15 { return .refinement }
            return .none
        }()

        // Extract what was contradicted (simple extraction)
        let contradictedContent = extractContradictedContent(
            userMessage: userMessage,
            previousResponse: previousResponse
        )

        return ContradictionAnalysis(
            isContradiction: isContradiction,
            type: type,
            confidence: min(contradictionScore, 1.0),
            matchedIndicators: matchedIndicators,
            contradictedContent: contradictedContent
        )
    }

    private func extractContradictedContent(
        userMessage: String,
        previousResponse: String
    ) -> String? {
        // Simple extraction - look for quoted content or content after "not"
        // This is a basic implementation; could be enhanced with LLM analysis

        // Check for quoted content
        if let range = userMessage.range(of: "\".*\"", options: .regularExpression) {
            return String(userMessage[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        // Check for content after "not" or "didn't"
        let patterns = ["not ", "didn't ", "don't ", "isn't ", "aren't "]
        for pattern in patterns {
            if let range = userMessage.lowercased().range(of: pattern) {
                let afterNot = String(userMessage[range.upperBound...])
                let words = afterNot.components(separatedBy: CharacterSet.punctuationCharacters.union(.whitespaces))
                    .filter { !$0.isEmpty }
                    .prefix(5)
                if !words.isEmpty {
                    return words.joined(separator: " ")
                }
            }
        }

        return nil
    }

    // MARK: - Outcome Determination

    private func determineOutcome(
        analysis: ContradictionAnalysis,
        prediction: Prediction?
    ) -> LearningOutcome {
        switch analysis.type {
        case .direct:
            return .contradicted
        case .partial:
            return .refined
        case .refinement:
            return .refined
        case .none:
            return prediction != nil ? .confirmed : .neutral
        }
    }

    // MARK: - Learning Data Updates

    private func updateLearningData(
        memoryId: String,
        outcome: LearningOutcome,
        analysis: ContradictionAnalysis
    ) {
        var data = learningData[memoryId] ?? MemoryLearningData(memoryId: memoryId)

        let evidence = LearningEvidence(
            memoryId: memoryId,
            predictionConfidence: analysis.confidence,
            outcome: outcome,
            newConditions: analysis.contradictedContent.map { [$0] },
            notes: analysis.matchedIndicators.isEmpty ? nil : "Indicators: \(analysis.matchedIndicators.joined(separator: ", "))"
        )

        data.addEvidence(evidence)
        learningData[memoryId] = data
    }

    // MARK: - Prediction Matching

    private func findMatchingPrediction(
        correlationId: String,
        response: String
    ) -> Prediction? {
        // First try to match by correlation ID
        if let match = pendingPredictions.first(where: { $0.correlationId == correlationId }) {
            return match
        }

        // Fall back to content matching
        return pendingPredictions.first { prediction in
            response.contains(prediction.content.prefix(50))
        }
    }

    // MARK: - Memory Refinement Suggestions

    /// Get suggestions for refining a memory based on learning data
    func getRefinementSuggestions(for memoryId: String) -> [RefinementSuggestion] {
        guard let data = learningData[memoryId] else { return [] }

        var suggestions: [RefinementSuggestion] = []

        // Low reliability suggestion
        if data.reliability < 0.5 && (data.successCount + data.failureCount) >= 3 {
            suggestions.append(RefinementSuggestion(
                type: .reduceConfidence,
                reason: "Memory has been contradicted frequently (reliability: \(Int(data.reliability * 100))%)",
                suggestedAction: "Consider reducing confidence or adding conditions"
            ))
        }

        // High failure count
        if data.failureCount >= 3 {
            suggestions.append(RefinementSuggestion(
                type: .addConditions,
                reason: "Memory has failed \(data.failureCount) times",
                suggestedAction: "Add scoping conditions: \(data.conditions.joined(separator: ", "))"
            ))
        }

        // High success - could be promoted
        if data.reliability > 0.9 && data.successCount >= 5 {
            suggestions.append(RefinementSuggestion(
                type: .increaseConfidence,
                reason: "Memory has been confirmed \(data.successCount) times with \(Int(data.reliability * 100))% reliability",
                suggestedAction: "Consider increasing confidence"
            ))
        }

        return suggestions
    }

    // MARK: - Analytics

    /// Get overall learning statistics
    func getLearningStats() -> LearningStats {
        let totalPredictions = recentLearningEvents.count
        let confirmed = recentLearningEvents.filter { $0.outcome == .confirmed }.count
        let contradicted = recentLearningEvents.filter { $0.outcome == .contradicted }.count
        let refined = recentLearningEvents.filter { $0.outcome == .refined }.count

        let avgReliability: Double = {
            let reliabilities = learningData.values.map { $0.reliability }
            guard !reliabilities.isEmpty else { return 0.5 }
            return reliabilities.reduce(0, +) / Double(reliabilities.count)
        }()

        return LearningStats(
            totalPredictions: totalPredictions,
            confirmedCount: confirmed,
            contradictedCount: contradicted,
            refinedCount: refined,
            averageReliability: avgReliability,
            memoriesTracked: learningData.count
        )
    }

    // MARK: - Cleanup

    /// Clear old predictions
    func clearOldPredictions(olderThan interval: TimeInterval = 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        pendingPredictions.removeAll { $0.timestamp < cutoff }
    }

    /// Clear all learning data
    func clearAllLearningData() {
        learningData.removeAll()
        pendingPredictions.removeAll()
        recentLearningEvents.removeAll()
    }

    /// Reset learning data for a specific memory (gives it a fresh start)
    func resetLearningData(for memoryId: String) {
        learningData.removeValue(forKey: memoryId)

        // Also remove any learning events that reference this memory
        recentLearningEvents.removeAll { event in
            event.affectedMemoryIds.contains(memoryId)
        }

        #if DEBUG
        print("[LearningLoop] Reset learning data for memory: \(memoryId)")
        #endif
    }
}

// MARK: - Supporting Types

struct Prediction: Identifiable {
    let id: String
    let content: String
    let confidence: Double
    let memoryIds: [String]
    let correlationId: String
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        content: String,
        confidence: Double,
        memoryIds: [String],
        correlationId: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.confidence = confidence
        self.memoryIds = memoryIds
        self.correlationId = correlationId
        self.timestamp = timestamp
    }
}

struct ContradictionAnalysis {
    let isContradiction: Bool
    let type: ContradictionType
    let confidence: Double
    let matchedIndicators: [String]
    let contradictedContent: String?
}

enum ContradictionType {
    case none
    case refinement  // Slight adjustment needed
    case partial     // Some aspects wrong
    case direct      // Direct contradiction
}

struct LearningEvent: Identifiable {
    let id: String
    let timestamp: Date
    let correlationId: String
    let outcome: LearningOutcome
    let contradictionDetected: Bool
    let affectedMemoryIds: [String]
    let userFeedback: String
    let systemResponse: String

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        correlationId: String,
        outcome: LearningOutcome,
        contradictionDetected: Bool,
        affectedMemoryIds: [String],
        userFeedback: String,
        systemResponse: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.correlationId = correlationId
        self.outcome = outcome
        self.contradictionDetected = contradictionDetected
        self.affectedMemoryIds = affectedMemoryIds
        self.userFeedback = userFeedback
        self.systemResponse = systemResponse
    }
}

struct LearningResult {
    let outcome: LearningOutcome
    let updatedMemoryIds: [String]
    let contradictionAnalysis: ContradictionAnalysis
    let event: LearningEvent
}

struct RefinementSuggestion {
    let type: RefinementType
    let reason: String
    let suggestedAction: String
}

enum RefinementType {
    case reduceConfidence
    case increaseConfidence
    case addConditions
    case split           // Split into multiple memories
    case archive         // Memory no longer relevant
}

struct LearningStats {
    let totalPredictions: Int
    let confirmedCount: Int
    let contradictedCount: Int
    let refinedCount: Int
    let averageReliability: Double
    let memoriesTracked: Int

    var confirmationRate: Double {
        guard totalPredictions > 0 else { return 0 }
        return Double(confirmedCount) / Double(totalPredictions)
    }

    var contradictionRate: Double {
        guard totalPredictions > 0 else { return 0 }
        return Double(contradictedCount) / Double(totalPredictions)
    }
}
