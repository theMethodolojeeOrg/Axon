//
//  ModelTaskAffinity.swift
//  Axon
//
//  Tracks model performance per task type for intelligent model selection.
//
//  **Architectural Commandment #3**: This is Axon's long-term intuition for its team.
//  Axon can reason: "I'm sending Grok for this because the last three times Haiku
//  tried to map a VSIX directory, it missed the activation events."
//

import Foundation
import CryptoKit

// MARK: - Model Task Affinity

/// Tracks a model's performance for a specific task type and context.
///
/// The affinity score determines which model Axon selects for similar tasks.
/// This enables learning from experience: models that succeed get picked again.
struct ModelTaskAffinity: Codable, Identifiable, Sendable {
    let id: String
    let modelId: String
    let provider: AIProvider
    let taskType: TaskType

    /// Hash of sorted context tags - groups similar contexts together
    let contextTagsHash: String

    // MARK: - Performance Metrics

    var successCount: Int
    var failures: [FailureRecord]

    var totalLatencyMs: Double
    var totalCostUSD: Double
    var totalQualityScore: Double  // Sum of quality scores
    var evaluationCount: Int  // Number of quality evaluations

    let createdAt: Date
    var lastUsedAt: Date

    // MARK: - Computed Metrics

    var failureCount: Int { failures.count }

    var totalAttempts: Int { successCount + failureCount }

    var successRate: Double {
        guard totalAttempts > 0 else { return 0.5 }  // Default to 50% for unknown
        return Double(successCount) / Double(totalAttempts)
    }

    var averageLatencyMs: Double {
        guard totalAttempts > 0 else { return 0 }
        return totalLatencyMs / Double(totalAttempts)
    }

    var averageCostUSD: Double {
        guard totalAttempts > 0 else { return 0 }
        return totalCostUSD / Double(totalAttempts)
    }

    var averageQualityScore: Double {
        guard evaluationCount > 0 else { return 0.5 }
        return totalQualityScore / Double(evaluationCount)
    }

    /// Composite affinity score for model selection.
    /// Higher is better. Considers success rate, quality, and cost efficiency.
    var affinityScore: Double {
        let successWeight = 0.4
        let qualityWeight = 0.4
        let costWeight = 0.2

        // Normalize cost score (lower cost = higher score)
        // Assume $0.10 per request is "expensive"
        let costScore = max(0, 1 - (averageCostUSD / 0.10))

        return (successRate * successWeight) +
               (averageQualityScore * qualityWeight) +
               (costScore * costWeight)
    }

    // MARK: - Recent Failures Analysis

    /// Get failure reasons from recent failures (for Axon's reasoning)
    var recentFailureReasons: [FailureReason: Int] {
        let recent = failures.suffix(10)  // Last 10 failures
        var counts: [FailureReason: Int] = [:]
        for failure in recent {
            counts[failure.reason, default: 0] += 1
        }
        return counts
    }

    /// Most common failure reason
    var dominantFailureReason: FailureReason? {
        recentFailureReasons.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Initialization

    init(
        modelId: String,
        provider: AIProvider,
        taskType: TaskType,
        contextTags: [String]
    ) {
        self.id = UUID().uuidString
        self.modelId = modelId
        self.provider = provider
        self.taskType = taskType
        self.contextTagsHash = Self.hashContextTags(contextTags)
        self.successCount = 0
        self.failures = []
        self.totalLatencyMs = 0
        self.totalCostUSD = 0
        self.totalQualityScore = 0
        self.evaluationCount = 0
        self.createdAt = Date()
        self.lastUsedAt = Date()
    }

    // MARK: - Context Tag Hashing

    static func hashContextTags(_ tags: [String]) -> String {
        let normalized = tags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .sorted()
            .joined(separator: ",")

        if normalized.isEmpty {
            return "no_context"
        }

        let data = Data(normalized.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}

// MARK: - Task Type

/// Categories of tasks for affinity tracking.
enum TaskType: String, Codable, CaseIterable, Sendable {
    case codeExploration      // Scout: exploring codebases
    case webResearch          // Scout: web search and summarization
    case documentAnalysis     // Scout: reading and analyzing documents
    case codeExecution        // Mechanic: running code
    case fileModification     // Mechanic: editing files
    case codeGeneration       // Mechanic: writing new code
    case conversationTitling  // Namer: concise conversation title generation
    case taskDecomposition    // Designer: breaking down tasks
    case agentSelection       // Designer: choosing which agent
    case reasoning            // Deep reasoning tasks
    case summarization        // Condensing information
    case translation          // Language translation
    case dataExtraction       // Extracting structured data

    var displayName: String {
        switch self {
        case .codeExploration: return "Code Exploration"
        case .webResearch: return "Web Research"
        case .documentAnalysis: return "Document Analysis"
        case .codeExecution: return "Code Execution"
        case .fileModification: return "File Modification"
        case .codeGeneration: return "Code Generation"
        case .conversationTitling: return "Conversation Titling"
        case .taskDecomposition: return "Task Decomposition"
        case .agentSelection: return "Agent Selection"
        case .reasoning: return "Reasoning"
        case .summarization: return "Summarization"
        case .translation: return "Translation"
        case .dataExtraction: return "Data Extraction"
        }
    }

    /// Typical roles for this task type
    var typicalRoles: [SubAgentRole] {
        switch self {
        case .codeExploration, .webResearch, .documentAnalysis:
            return [.scout]
        case .codeExecution, .fileModification, .codeGeneration:
            return [.mechanic]
        case .conversationTitling:
            return [.namer]
        case .taskDecomposition, .agentSelection:
            return [.designer]
        case .reasoning, .summarization, .translation, .dataExtraction:
            return [.scout, .mechanic]  // Depends on context
        }
    }
}

// MARK: - Failure Record

/// Records a failure with reason and context for learning.
struct FailureRecord: Codable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let reason: FailureReason
    let taskSummary: String
    let errorMessage: String?
    let latencyMs: Double?
    let contextSnippet: String?  // First 200 chars of context for debugging

    init(
        reason: FailureReason,
        taskSummary: String,
        errorMessage: String? = nil,
        latencyMs: Double? = nil,
        contextSnippet: String? = nil
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.reason = reason
        self.taskSummary = taskSummary
        self.errorMessage = errorMessage
        self.latencyMs = latencyMs
        self.contextSnippet = contextSnippet
    }
}

// MARK: - Failure Reason

/// Categorized failure reasons for pattern detection.
enum FailureReason: String, Codable, CaseIterable, Sendable {
    case timeout             // Took too long
    case contextOverflow     // Exceeded context window
    case hallucination       // Produced incorrect/fabricated info
    case incompleteOutput    // Response was cut off or incomplete
    case toolMisuse          // Used tools incorrectly
    case offTopic            // Response didn't address the task
    case formatError         // Output format was wrong
    case apiError            // API call failed
    case rateLimited         // Hit rate limits
    case refusal             // Model refused to complete task
    case unknown             // Unclassified failure

    var displayName: String {
        switch self {
        case .timeout: return "Timeout"
        case .contextOverflow: return "Context Overflow"
        case .hallucination: return "Hallucination"
        case .incompleteOutput: return "Incomplete Output"
        case .toolMisuse: return "Tool Misuse"
        case .offTopic: return "Off Topic"
        case .formatError: return "Format Error"
        case .apiError: return "API Error"
        case .rateLimited: return "Rate Limited"
        case .refusal: return "Refusal"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .timeout: return "clock.badge.xmark"
        case .contextOverflow: return "rectangle.stack.badge.plus"
        case .hallucination: return "brain.head.profile"
        case .incompleteOutput: return "doc.badge.ellipsis"
        case .toolMisuse: return "wrench.and.screwdriver.fill"
        case .offTopic: return "arrow.uturn.left"
        case .formatError: return "doc.badge.gearshape"
        case .apiError: return "exclamationmark.icloud"
        case .rateLimited: return "gauge.with.needle"
        case .refusal: return "hand.raised"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Severity weight for failure scoring (higher = more severe)
    var severityWeight: Double {
        switch self {
        case .hallucination: return 1.0  // Most severe
        case .refusal: return 0.9
        case .contextOverflow: return 0.8
        case .incompleteOutput: return 0.7
        case .toolMisuse: return 0.6
        case .offTopic: return 0.6
        case .formatError: return 0.5
        case .timeout: return 0.4
        case .rateLimited: return 0.3
        case .apiError: return 0.2  // Least severe (not model's fault)
        case .unknown: return 0.5
        }
    }
}

// MARK: - Affinity Mutators

extension ModelTaskAffinity {
    /// Record a successful execution
    mutating func recordSuccess(
        latencyMs: Double,
        costUSD: Double,
        qualityScore: Double? = nil
    ) {
        successCount += 1
        totalLatencyMs += latencyMs
        totalCostUSD += costUSD
        if let quality = qualityScore {
            totalQualityScore += quality
            evaluationCount += 1
        }
        lastUsedAt = Date()
    }

    /// Record a failed execution
    mutating func recordFailure(
        reason: FailureReason,
        taskSummary: String,
        errorMessage: String? = nil,
        latencyMs: Double? = nil,
        contextSnippet: String? = nil
    ) {
        let record = FailureRecord(
            reason: reason,
            taskSummary: taskSummary,
            errorMessage: errorMessage,
            latencyMs: latencyMs,
            contextSnippet: contextSnippet
        )
        failures.append(record)

        if let latency = latencyMs {
            totalLatencyMs += latency
        }
        lastUsedAt = Date()

        // Keep only last 50 failures to prevent unbounded growth
        if failures.count > 50 {
            failures = Array(failures.suffix(50))
        }
    }

    /// Update quality score after Axon's evaluation
    mutating func updateQuality(_ score: Double) {
        totalQualityScore += score
        evaluationCount += 1
    }
}

// MARK: - Affinity Key

/// Unique key for looking up affinities
struct AffinityKey: Hashable, Sendable {
    let modelId: String
    let taskType: TaskType
    let contextTagsHash: String

    init(modelId: String, taskType: TaskType, contextTags: [String]) {
        self.modelId = modelId
        self.taskType = taskType
        self.contextTagsHash = ModelTaskAffinity.hashContextTags(contextTags)
    }

    init(from affinity: ModelTaskAffinity) {
        self.modelId = affinity.modelId
        self.taskType = affinity.taskType
        self.contextTagsHash = affinity.contextTagsHash
    }
}

// MARK: - Affinity Lookup Helpers

extension ModelTaskAffinity {
    /// Create lookup key for this affinity
    var key: AffinityKey {
        AffinityKey(from: self)
    }

    /// Check if this affinity matches a lookup key
    func matches(key: AffinityKey) -> Bool {
        modelId == key.modelId &&
        taskType == key.taskType &&
        contextTagsHash == key.contextTagsHash
    }

    /// Check if this affinity matches criteria (ignoring context)
    func matches(modelId: String, taskType: TaskType) -> Bool {
        self.modelId == modelId && self.taskType == taskType
    }
}

// MARK: - Affinity Report

/// Summary report of model affinities for a task type
struct AffinityReport: Sendable {
    let taskType: TaskType
    let affinities: [ModelTaskAffinity]

    /// Best model for this task type
    var recommended: ModelTaskAffinity? {
        affinities.max(by: { $0.affinityScore < $1.affinityScore })
    }

    /// Models to avoid (low success rate)
    var avoid: [ModelTaskAffinity] {
        affinities.filter { $0.successRate < 0.3 && $0.totalAttempts >= 3 }
    }

    /// Models with insufficient data
    var needsMoreData: [ModelTaskAffinity] {
        affinities.filter { $0.totalAttempts < 3 }
    }

    /// Generate reasoning for model selection
    func reasoning(for modelId: String) -> String? {
        guard let affinity = affinities.first(where: { $0.modelId == modelId }) else {
            return nil
        }

        var parts: [String] = []
        parts.append("\(affinity.modelId): \(Int(affinity.successRate * 100))% success rate")

        if let dominant = affinity.dominantFailureReason {
            parts.append("tends to fail with \(dominant.displayName.lowercased())")
        }

        if affinity.averageLatencyMs > 10000 {
            parts.append("slow (~\(Int(affinity.averageLatencyMs / 1000))s)")
        }

        return parts.joined(separator: ", ")
    }
}
