//
//  SubAgentMemorySilo.swift
//  Axon
//
//  Isolated memory storage for sub-agent outputs.
//  Implements the Peek pattern: summary() → peek() → dive()
//
//  **Architectural Commandment #2**: Axon stays in the strategic space with the
//  option to dive into the silo if the summary looks suspicious.
//

import Foundation

// MARK: - Sub-Agent Memory Silo

/// Isolated storage for sub-agent outputs.
///
/// Sub-agent outputs go here, NOT into Axon's main memory.
/// This enforces the separation between Axon's lived experience and
/// contractor work products.
struct SubAgentMemorySilo: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let jobId: String
    let role: SubAgentRole
    let createdAt: Date

    /// Entries in this silo
    var entries: [SiloEntry]

    /// Tags used for context injection into this job
    let contextTags: [String]

    /// Parent silo ID for chained sub-agent results
    let parentSiloId: String?

    // MARK: - Sealing (Immutability)

    /// Once a job completes, the silo is sealed
    var isSealed: Bool

    /// When the silo was sealed
    var sealedAt: Date?

    /// Attestation that sealed this silo
    var sealedByAttestationId: String?

    // MARK: - Retention

    /// When this silo should be purged (nil = permanent)
    var expiresAt: Date?

    /// Whether Axon has marked this as a "compacted lesson" (never expires)
    var isCompactedLesson: Bool

    // MARK: - Initialization

    init(
        jobId: String,
        role: SubAgentRole,
        contextTags: [String] = [],
        parentSiloId: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = UUID().uuidString
        self.jobId = jobId
        self.role = role
        self.createdAt = Date()
        self.entries = []
        self.contextTags = contextTags
        self.parentSiloId = parentSiloId
        self.isSealed = false
        self.expiresAt = expiresAt
        self.isCompactedLesson = false
    }

    // MARK: - Peek Pattern Implementation

    /// High-level summary for Axon's strategic view.
    /// Axon can see what's in the silo without consuming all the raw data.
    func summary() -> SiloSummary {
        let observations = entries.filter { $0.type == .observation }
        let inferences = entries.filter { $0.type == .inference }
        let artifacts = entries.filter { $0.type == .artifact }
        let questions = entries.filter { $0.type == .question }
        let recommendations = entries.filter { $0.type == .recommendation }
        let flagged = entries.filter { ($0.confidence ?? 1.0) < 0.5 }

        // Top 3 highest confidence inferences
        let topInferences = inferences
            .sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }
            .prefix(3)
            .map { $0 }

        return SiloSummary(
            siloId: id,
            jobId: jobId,
            role: role,
            observationCount: observations.count,
            inferenceCount: inferences.count,
            artifactCount: artifacts.count,
            pendingQuestions: Array(questions),
            spawnRecommendations: Array(recommendations),
            flaggedItems: Array(flagged),
            topInferences: Array(topInferences),
            totalEntries: entries.count,
            isSealed: isSealed,
            expiresAt: expiresAt
        )
    }

    /// Filtered peek at specific entry types.
    /// Use when you want just observations, or just inferences, etc.
    func peek(entryTypes: [SiloEntryType]) -> [SiloEntry] {
        entries.filter { entryTypes.contains($0.type) }
    }

    /// Peek at entries matching specific tags.
    func peek(tags: [String]) -> [SiloEntry] {
        let normalizedTags = Set(tags.map { $0.lowercased() })
        return entries.filter { entry in
            let entryTags = Set(entry.tags.map { $0.lowercased() })
            return !entryTags.isDisjoint(with: normalizedTags)
        }
    }

    /// Full dive when Axon needs all the details.
    /// Use sparingly - this is the "suspicious summary" escape hatch.
    func dive() -> [SiloEntry] {
        entries
    }

    // MARK: - Computed Properties

    var isExpired: Bool {
        guard !isCompactedLesson else { return false }
        guard let expires = expiresAt else { return false }
        return Date() > expires
    }

    var hasQuestions: Bool {
        entries.contains { $0.type == .question }
    }

    var hasSpawnRecommendations: Bool {
        entries.contains { $0.type == .recommendation }
    }

    var shortId: String {
        String(id.prefix(8))
    }
}

// MARK: - Silo Entry

/// A single entry in a memory silo.
struct SiloEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let type: SiloEntryType
    let content: String

    /// Confidence score for this entry (0-1, nil if not applicable)
    let confidence: Double?

    /// Tags for categorization and search
    let tags: [String]

    /// Source information (tool name, URL, etc.)
    let source: String?

    init(
        type: SiloEntryType,
        content: String,
        confidence: Double? = nil,
        tags: [String] = [],
        source: String? = nil
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.type = type
        self.content = content
        self.confidence = confidence
        self.tags = tags
        self.source = source
    }

    var shortId: String {
        String(id.prefix(8))
    }
}

// MARK: - Silo Entry Type

/// Types of entries that can be stored in a silo.
enum SiloEntryType: String, Codable, CaseIterable, Sendable {
    /// Raw observation from the sub-agent
    case observation

    /// Inference or conclusion drawn by the sub-agent
    case inference

    /// Produced content (code, text, file)
    case artifact

    /// Tool execution result
    case toolResult

    /// Question for Axon (clarification needed)
    case question

    /// Spawn recommendation (no-nesting: agent wants another agent)
    case recommendation

    var displayName: String {
        switch self {
        case .observation: return "Observation"
        case .inference: return "Inference"
        case .artifact: return "Artifact"
        case .toolResult: return "Tool Result"
        case .question: return "Question"
        case .recommendation: return "Recommendation"
        }
    }

    var icon: String {
        switch self {
        case .observation: return "eye"
        case .inference: return "lightbulb"
        case .artifact: return "doc.text"
        case .toolResult: return "wrench"
        case .question: return "questionmark.bubble"
        case .recommendation: return "arrow.triangle.branch"
        }
    }
}

// MARK: - Silo Summary

/// High-level summary of a silo's contents.
/// This is what Axon sees first before deciding to dive.
struct SiloSummary: Codable, Equatable, Sendable {
    let siloId: String
    let jobId: String
    let role: SubAgentRole

    let observationCount: Int
    let inferenceCount: Int
    let artifactCount: Int

    /// Questions requiring Axon's attention
    let pendingQuestions: [SiloEntry]

    /// Spawn recommendations (Designer wants more agents)
    let spawnRecommendations: [SiloEntry]

    /// Low-confidence items that might need review
    let flaggedItems: [SiloEntry]

    /// Top 3 highest-confidence inferences
    let topInferences: [SiloEntry]

    let totalEntries: Int
    let isSealed: Bool
    let expiresAt: Date?

    // MARK: - Display Helpers

    var oneLineSummary: String {
        var parts: [String] = []
        if observationCount > 0 { parts.append("\(observationCount) obs") }
        if inferenceCount > 0 { parts.append("\(inferenceCount) inf") }
        if artifactCount > 0 { parts.append("\(artifactCount) art") }
        if !pendingQuestions.isEmpty { parts.append("\(pendingQuestions.count) Q") }
        if !spawnRecommendations.isEmpty { parts.append("\(spawnRecommendations.count) spawn rec") }
        return parts.isEmpty ? "Empty silo" : parts.joined(separator: ", ")
    }

    var needsAttention: Bool {
        !pendingQuestions.isEmpty || !spawnRecommendations.isEmpty || !flaggedItems.isEmpty
    }

    var attentionItems: [String] {
        var items: [String] = []
        if !pendingQuestions.isEmpty {
            items.append("\(pendingQuestions.count) question(s) need answering")
        }
        if !spawnRecommendations.isEmpty {
            items.append("\(spawnRecommendations.count) agent spawn(s) recommended")
        }
        if !flaggedItems.isEmpty {
            items.append("\(flaggedItems.count) low-confidence item(s) flagged")
        }
        return items
    }
}

// MARK: - Silo Mutators

extension SubAgentMemorySilo {
    /// Add an entry to the silo (fails if sealed)
    mutating func addEntry(_ entry: SiloEntry) throws {
        guard !isSealed else {
            throw SiloError.alreadySealed
        }
        entries.append(entry)
    }

    /// Seal the silo (no more entries allowed)
    mutating func seal(attestationId: String) {
        isSealed = true
        sealedAt = Date()
        sealedByAttestationId = attestationId
    }

    /// Mark as a compacted lesson (never expires)
    mutating func markAsCompactedLesson() {
        isCompactedLesson = true
        expiresAt = nil
    }

    /// Set expiration date
    mutating func setExpiry(_ date: Date?) {
        guard !isCompactedLesson else { return }
        expiresAt = date
    }
}

// MARK: - Silo Error

enum SiloError: LocalizedError {
    case alreadySealed
    case notFound
    case expired

    var errorDescription: String? {
        switch self {
        case .alreadySealed:
            return "Cannot modify a sealed silo"
        case .notFound:
            return "Silo not found"
        case .expired:
            return "Silo has expired"
        }
    }
}

// MARK: - Silo Factory

extension SubAgentMemorySilo {
    /// Create a silo for a job, optionally inheriting context from a parent
    static func create(
        for job: SubAgentJob,
        inheritingFrom parentSilo: SubAgentMemorySilo? = nil
    ) -> SubAgentMemorySilo {
        var silo = SubAgentMemorySilo(
            jobId: job.id,
            role: job.role,
            contextTags: job.contextInjectionTags,
            parentSiloId: parentSilo?.id,
            expiresAt: job.expiresAt
        )

        // If inheriting, add parent's top inferences as initial context
        if let parent = parentSilo {
            let inherited = parent.summary().topInferences.map { inference in
                SiloEntry(
                    type: .observation,
                    content: "[Inherited from \(parent.role.displayName)] \(inference.content)",
                    confidence: inference.confidence,
                    tags: ["inherited", parent.role.rawValue] + inference.tags,
                    source: "silo:\(parent.shortId)"
                )
            }
            silo.entries.append(contentsOf: inherited)
        }

        return silo
    }
}
