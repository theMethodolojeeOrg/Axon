//
//  HeuristicsSynthesisEngine.swift
//  Axon
//
//  Engine for synthesizing memories into heuristics using Apple Intelligence Foundation Models.
//  Handles all four heuristic types and the meta-loop for distillation.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Generable Output Structs

/// Structured output for narrative heuristics
@Generable
struct NarrativeHeuristic {
    @Guide(description: "A 1-2 sentence insight about the core themes and patterns emerging from the user's focus areas. Written in first person (\"I...\", \"My...\").")
    var insight: String

    @Guide(description: "Confidence score from 0.0 to 1.0 based on pattern clarity.")
    var confidence: Double
}

/// Structured output for embodiment heuristics
@Generable
struct EmbodimentHeuristic {
    @Guide(description: "A 1-2 sentence actionable insight or suggestion based on the patterns. Written in first person (\"I could...\", \"I might...\").")
    var insight: String

    @Guide(description: "Confidence score from 0.0 to 1.0 based on actionability clarity.")
    var confidence: Double
}

/// Structured output for emotion heuristics
@Generable
struct EmotionHeuristic {
    @Guide(description: "A 1-2 sentence observation about the emotional resonance or feeling states around these patterns. Written in first person (\"I feel...\", \"I sense...\").")
    var insight: String

    @Guide(description: "Confidence score from 0.0 to 1.0 based on emotional pattern clarity.")
    var confidence: Double
}

/// Structured output for distillation
@Generable
struct DistilledHeuristic {
    @Guide(description: "A concise, powerful insight that captures the essential pattern across all the input heuristics. 1-2 sentences max.")
    var distilledInsight: String

    @Guide(description: "Confidence score from 0.0 to 1.0.")
    var confidence: Double
}

/// Structured output for curiosity tag selection
@Generable
struct CuriositySelection {
    @Guide(description: "The 3 most intriguing or unusual tags that warrant deeper exploration, selected from the candidate list.")
    var selectedTags: [String]
}
#endif

// MARK: - Synthesis Errors

enum HeuristicsSynthesisError: LocalizedError {
    case appleIntelligenceUnavailable
    case insufficientData
    case synthesisError(String)

    var errorDescription: String? {
        switch self {
        case .appleIntelligenceUnavailable:
            return "Apple Intelligence is unavailable on this device or OS version."
        case .insufficientData:
            return "Not enough memory data to synthesize heuristics."
        case .synthesisError(let message):
            return "Synthesis failed: \(message)"
        }
    }
}

// MARK: - Synthesis Engine

actor HeuristicsSynthesisEngine {

    // MARK: - Dependencies

    private let memoryService: MemoryService
    private let settingsStorage: SettingsStorage

    // MARK: - Initialization

    init(memoryService: MemoryService = .shared, settingsStorage: SettingsStorage = .shared) {
        self.memoryService = memoryService
        self.settingsStorage = settingsStorage
    }

    // MARK: - Availability Check

    /// Check if Apple Intelligence is available for synthesis
    var isAppleIntelligenceAvailable: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if canImport(FoundationModels)
            return true
            #else
            return false
            #endif
        }
        return false
    }

    // MARK: - Main Synthesis Entry Point

    /// Synthesize heuristics for a specific type
    func synthesize(type: HeuristicType) async throws -> [Heuristic] {
        let memories = await memoryService.memories
        let settings = settingsStorage.loadSettings()?.heuristicsSettings ?? HeuristicsSettings()

        let synthesisRunId = UUID().uuidString

        switch type {
        case .frequency:
            return try await synthesizeFrequency(memories: memories, settings: settings, runId: synthesisRunId)
        case .recency:
            return try await synthesizeRecency(memories: memories, settings: settings, runId: synthesisRunId)
        case .curiosity:
            return try await synthesizeCuriosity(memories: memories, settings: settings, runId: synthesisRunId)
        case .interest:
            return try await synthesizeInterest(memories: memories, settings: settings, runId: synthesisRunId)
        }
    }

    /// Synthesize all heuristic types
    func synthesizeAll() async throws -> [Heuristic] {
        var allHeuristics: [Heuristic] = []

        for type in HeuristicType.allCases {
            let heuristics = try await synthesize(type: type)
            allHeuristics.append(contentsOf: heuristics)
        }

        return allHeuristics
    }

    /// Meta-synthesis: distill old heuristics into their cores
    func distillHeuristics(_ heuristics: [Heuristic]) async throws -> [Heuristic] {
        guard !heuristics.isEmpty else { return [] }

        let synthesisRunId = UUID().uuidString
        var distilled: [Heuristic] = []

        // Group by type and dimension
        let grouped = Dictionary(grouping: heuristics) { "\($0.type.rawValue)-\($0.dimension.rawValue)" }

        for (_, groupHeuristics) in grouped {
            guard let first = groupHeuristics.first else { continue }

            // Combine content from all heuristics in this group
            let combinedContent = groupHeuristics.map(\.content).joined(separator: "\n\n")
            let allTags = Set(groupHeuristics.flatMap(\.sourceTagSample))
            let totalMemoryCount = groupHeuristics.map(\.memoryCount).reduce(0, +)

            // Try Apple Intelligence distillation
            let (distilledContent, confidence) = await distillWithAppleIntelligence(
                type: first.type,
                dimension: first.dimension,
                content: combinedContent,
                heuristicCount: groupHeuristics.count
            )

            let heuristic = Heuristic(
                type: first.type,
                dimension: first.dimension,
                content: distilledContent,
                sourceTagSample: Array(allTags.prefix(10)),
                memoryCount: totalMemoryCount,
                confidence: confidence,
                synthesisRunId: synthesisRunId,
                distilledFrom: groupHeuristics.map(\.id)
            )

            distilled.append(heuristic)
        }

        return distilled
    }

    // MARK: - Apple Intelligence Distillation

    private func distillWithAppleIntelligence(
        type: HeuristicType,
        dimension: HeuristicDimension,
        content: String,
        heuristicCount: Int
    ) async -> (String, Double) {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if canImport(FoundationModels)
            do {
                let prompt = """
                Distill the following \(heuristicCount) \(type.displayName) heuristics (\(dimension.displayName) dimension) into their core essence:

                \(content.prefix(2000))

                Provide a concise, powerful insight that captures the essential pattern across all these observations. Write in first person ("I...", "My...").
                """

                let session = LanguageModelSession()
                let result = try await session.respond(to: prompt, generating: DistilledHeuristic.self)
                return (result.content.distilledInsight, min(1.0, max(0.0, result.content.confidence)))
            } catch {
                print("[HeuristicsSynthesisEngine] Apple Intelligence distillation failed: \(error)")
            }
            #endif
        }

        // Fallback
        let avgConfidence = 0.7
        return ("Distilled insight from \(heuristicCount) \(type.displayName) heuristics: \(content.prefix(200))...", avgConfidence)
    }

    // MARK: - Type-Specific Synthesis

    /// Frequency: Analyze non-temporal tag frequency
    private func synthesizeFrequency(memories: [Memory], settings: HeuristicsSettings, runId: String) async throws -> [Heuristic] {
        // Get non-temporal tags with frequency
        let tagCounts = analyzeTagFrequency(memories: memories, excludeTemporal: true)
        let topTags = tagCounts
            .filter { $0.value >= settings.minTagFrequency }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        guard !topTags.isEmpty else { return [] }

        // Sample memories for these tags
        let sampledMemories = sampleMemories(for: Array(topTags), from: memories, limit: 20)

        // Generate heuristics for each dimension using Apple Intelligence
        return await synthesizeAllDimensions(
            type: .frequency,
            tags: Array(topTags),
            memories: sampledMemories,
            runId: runId,
            contextDescription: "recurring themes that appear frequently in the user's thoughts"
        )
    }

    /// Recency: Analyze temporal tag patterns
    private func synthesizeRecency(memories: [Memory], settings: HeuristicsSettings, runId: String) async throws -> [Heuristic] {
        // Get recent memories (today, this_week)
        let temporalTags = ["today", "this_week", "yesterday"]
        let recentMemories = memories.filter { memory in
            memory.tags.contains { temporalTags.contains($0) }
        }

        guard !recentMemories.isEmpty else { return [] }

        // Get non-temporal tags from recent memories
        let recentTags = recentMemories
            .flatMap { $0.tags }
            .filter { !Memory.temporalTags.contains($0) }

        let tagCounts = Dictionary(grouping: recentTags, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        guard !tagCounts.isEmpty else { return [] }

        // Generate heuristics for each dimension
        return await synthesizeAllDimensions(
            type: .recency,
            tags: tagCounts,
            memories: recentMemories,
            runId: runId,
            contextDescription: "what's been on the user's mind recently (today, this week)"
        )
    }

    /// Curiosity: AI-detected intriguing patterns
    private func synthesizeCuriosity(memories: [Memory], settings: HeuristicsSettings, runId: String) async throws -> [Heuristic] {
        // For curiosity, we look for less frequent but interesting tags
        let tagCounts = analyzeTagFrequency(memories: memories, excludeTemporal: true)

        // Find tags that appear occasionally but not constantly (curiosity sweet spot)
        let candidateTags = tagCounts
            .filter { $0.value >= 2 && $0.value <= 10 }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }

        guard !candidateTags.isEmpty else { return [] }

        // Use Apple Intelligence to pick the most intriguing tags
        let curiosityTags = await selectCuriosityTags(from: Array(candidateTags), memories: memories)

        guard !curiosityTags.isEmpty else { return [] }

        let sampledMemories = sampleMemories(for: curiosityTags, from: memories, limit: 15)

        return await synthesizeAllDimensions(
            type: .curiosity,
            tags: curiosityTags,
            memories: sampledMemories,
            runId: runId,
            contextDescription: "intriguing patterns that draw the user's attention and curiosity"
        )
    }

    /// Interest: Long-term engagement patterns
    private func synthesizeInterest(memories: [Memory], settings: HeuristicsSettings, runId: String) async throws -> [Heuristic] {
        // For interest, we look at tags that appear consistently over time
        let oneMonthAgo = Date().addingTimeInterval(-30 * 86400)

        // Split memories into old and new
        let oldMemories = memories.filter { $0.createdAt < oneMonthAgo }
        let newMemories = memories.filter { $0.createdAt >= oneMonthAgo }

        // Find tags that appear in both old and new memories
        let oldTags = Set(oldMemories.flatMap { $0.tags }.filter { !Memory.temporalTags.contains($0) })
        let newTags = Set(newMemories.flatMap { $0.tags }.filter { !Memory.temporalTags.contains($0) })

        let persistentTags = oldTags.intersection(newTags)

        guard !persistentTags.isEmpty else { return [] }

        let interestTags = Array(persistentTags.prefix(5))
        let sampledMemories = sampleMemories(for: interestTags, from: memories, limit: 20)

        return await synthesizeAllDimensions(
            type: .interest,
            tags: interestTags,
            memories: sampledMemories,
            runId: runId,
            contextDescription: "long-term interests that persist over time and represent stable centers of attention"
        )
    }

    // MARK: - Apple Intelligence Synthesis

    /// Synthesize all three dimensions for a given type using Apple Intelligence
    private func synthesizeAllDimensions(
        type: HeuristicType,
        tags: [String],
        memories: [Memory],
        runId: String,
        contextDescription: String
    ) async -> [Heuristic] {
        var heuristics: [Heuristic] = []

        for dimension in HeuristicDimension.allCases {
            let (content, confidence) = await synthesizeWithAppleIntelligence(
                type: type,
                dimension: dimension,
                tags: tags,
                memories: memories,
                contextDescription: contextDescription
            )

            let heuristic = Heuristic(
                type: type,
                dimension: dimension,
                content: content,
                sourceTagSample: tags,
                memoryCount: memories.count,
                confidence: confidence,
                synthesisRunId: runId
            )

            heuristics.append(heuristic)
        }

        return heuristics
    }

    /// Use Apple Intelligence to synthesize a single heuristic
    private func synthesizeWithAppleIntelligence(
        type: HeuristicType,
        dimension: HeuristicDimension,
        tags: [String],
        memories: [Memory],
        contextDescription: String
    ) async -> (String, Double) {
        let tagList = tags.joined(separator: ", ")
        let memorySnippets = memories.prefix(5).map { $0.content.prefix(150) }.joined(separator: "\n\n")

        if #available(iOS 26.0, macOS 26.0, *) {
            #if canImport(FoundationModels)
            do {
                let prompt = buildPrompt(
                    type: type,
                    dimension: dimension,
                    tags: tagList,
                    memorySnippets: String(memorySnippets),
                    contextDescription: contextDescription
                )

                let session = LanguageModelSession()

                switch dimension {
                case .narrative:
                    let result = try await session.respond(to: prompt, generating: NarrativeHeuristic.self)
                    return (result.content.insight, min(1.0, max(0.0, result.content.confidence)))

                case .embodiment:
                    let result = try await session.respond(to: prompt, generating: EmbodimentHeuristic.self)
                    return (result.content.insight, min(1.0, max(0.0, result.content.confidence)))

                case .emotion:
                    let result = try await session.respond(to: prompt, generating: EmotionHeuristic.self)
                    return (result.content.insight, min(1.0, max(0.0, result.content.confidence)))
                }
            } catch {
                print("[HeuristicsSynthesisEngine] Apple Intelligence synthesis failed for \(type.rawValue)/\(dimension.rawValue): \(error)")
            }
            #endif
        }

        // Fallback to template-based synthesis
        return (buildFallbackContent(type: type, dimension: dimension, tags: tagList, memories: memories), 0.6)
    }

    /// Build the synthesis prompt for Apple Intelligence
    private func buildPrompt(
        type: HeuristicType,
        dimension: HeuristicDimension,
        tags: String,
        memorySnippets: String,
        contextDescription: String
    ) -> String {
        let dimensionInstruction: String
        switch dimension {
        case .narrative:
            dimensionInstruction = "Identify the core narrative or themes emerging from these patterns. What story do they tell about the user's interests?"
        case .embodiment:
            dimensionInstruction = "Suggest actionable insights or next steps based on these patterns. What could the user do or explore?"
        case .emotion:
            dimensionInstruction = "Observe the emotional resonance or feeling states around these patterns. What sense of energy, mood, or motivation do you detect?"
        }

        return """
        You are analyzing \(contextDescription).

        Tags showing this pattern: \(tags)

        Sample memories:
        \(memorySnippets)

        \(dimensionInstruction)

        Write a 1-2 sentence insight in first person ("I...", "My...", "I could..."). Be specific to the content, not generic.
        """
    }

    /// Select the most intriguing tags using Apple Intelligence
    private func selectCuriosityTags(from candidates: [String], memories: [Memory]) async -> [String] {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if canImport(FoundationModels)
            do {
                // Get memory snippets for context
                let taggedMemories = memories.filter { memory in
                    memory.tags.contains { candidates.contains($0) }
                }
                let snippets = taggedMemories.prefix(10).map { "\($0.tags.filter { candidates.contains($0) }.joined(separator: ", ")): \($0.content.prefix(100))" }.joined(separator: "\n")

                let prompt = """
                From the following tags, select the 3 most intriguing or unusual ones that might warrant deeper exploration or curiosity:

                Candidate tags: \(candidates.joined(separator: ", "))

                Context from memories:
                \(snippets)

                Select 3 tags that are most likely to represent emerging interests, unique patterns, or surprising connections.
                """

                let session = LanguageModelSession()
                let result = try await session.respond(to: prompt, generating: CuriositySelection.self)

                // Validate that selected tags are in the candidate list
                let validTags = result.content.selectedTags.filter { candidates.contains($0) }
                if !validTags.isEmpty {
                    return validTags
                }
            } catch {
                print("[HeuristicsSynthesisEngine] Curiosity tag selection failed: \(error)")
            }
            #endif
        }

        // Fallback: just take the first 3
        return Array(candidates.prefix(3))
    }

    // MARK: - Helper Methods

    /// Analyze tag frequency in memories
    private func analyzeTagFrequency(memories: [Memory], excludeTemporal: Bool) -> [String: Int] {
        var tagCounts: [String: Int] = [:]

        for memory in memories {
            for tag in memory.tags {
                if excludeTemporal && Memory.temporalTags.contains(tag) {
                    continue
                }
                tagCounts[tag, default: 0] += 1
            }
        }

        return tagCounts
    }

    /// Sample memories that contain any of the given tags
    private func sampleMemories(for tags: [String], from memories: [Memory], limit: Int) -> [Memory] {
        let tagSet = Set(tags)
        return memories
            .filter { memory in
                memory.tags.contains { tagSet.contains($0) }
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    /// Fallback content when Apple Intelligence is unavailable
    private func buildFallbackContent(type: HeuristicType, dimension: HeuristicDimension, tags: String, memories: [Memory]) -> String {
        let memorySnippets = memories.prefix(3).map { $0.content.prefix(100) }.joined(separator: "; ")

        switch (type, dimension) {
        case (.frequency, .narrative):
            return "My recurring focus on '\(tags)' suggests a deep engagement with these themes. \(memorySnippets)..."
        case (.frequency, .embodiment):
            return "I could explore how '\(tags)' manifests in my daily practice. The patterns point to actionable insights."
        case (.frequency, .emotion):
            return "I feel a sense of commitment and purpose around '\(tags)'. These themes resonate with my core interests."

        case (.recency, .narrative):
            return "This week I've been exploring '\(tags)' heavily, suggesting active focus in these areas."
        case (.recency, .embodiment):
            return "My recent work on '\(tags)' points to immediate priorities. I could consider what next steps would be most impactful."
        case (.recency, .emotion):
            return "I sense energy and momentum around '\(tags)'. These current interests feel alive and dynamic."

        case (.curiosity, .narrative):
            return "Among recent tags, '\(tags)' seem to pull at me with particular intrigue."
        case (.curiosity, .embodiment):
            return "My curiosity about '\(tags)' suggests exploring deeper. What questions are emerging?"
        case (.curiosity, .emotion):
            return "I feel a sense of wonder and discovery around '\(tags)'. I want to follow this thread."

        case (.interest, .narrative):
            return "My sustained engagement with '\(tags)' shows deep, long-term interest that transcends trends."
        case (.interest, .embodiment):
            return "The persistence of '\(tags)' in my thinking suggests building on these foundations."
        case (.interest, .emotion):
            return "'\(tags)' represents a stable center of gravity in my intellectual life. It matters to me."
        }
    }
}

// MARK: - Memory Extension for Temporal Tags

extension Memory {
    /// All temporal tags that are auto-injected
    nonisolated static let temporalTags = Set([
        "today", "yesterday", "this_week", "this_month",
        "recent_months", "older",
        "spring", "summer", "fall", "winter",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ])
}
