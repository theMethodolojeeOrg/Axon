//
//  SalienceService.swift
//  Axon
//
//  Automatic memory injection service.
//  Ranks and injects salient memories into LLM context without explicit tool calls.
//

import Foundation
import Combine

// MARK: - Salience Service

/// Service for automatically injecting relevant memories into LLM context
@MainActor
class SalienceService: ObservableObject {
    static let shared = SalienceService()

    private let epistemicEngine = EpistemicEngine.shared
    private let predicateLogger = PredicateLogger.shared

    /// Estimated tokens per character (rough approximation)
    private let tokensPerChar: Double = 0.25

    private init() {}

    // MARK: - Main Injection Method

    /// Generate salient memory injection for a conversation
    /// - Parameter userName: Optional user's display name for personalized headers
    func injectSalient(
        conversation: [Message],
        memories: [Memory],
        availableTokens: Int,
        correlationId: String,
        settings: MemoryInjectionSettings = .default,
        userName: String? = nil
    ) -> SalienceInjectionResult {
        // Use full memory access scope by default (host sessions)
        return injectSalientWithScope(
            conversation: conversation,
            memories: memories,
            availableTokens: availableTokens,
            sessionScope: .full,
            correlationId: correlationId,
            settings: settings,
            userName: userName
        )
    }

    /// Generate salient memory injection with scope-based filtering (for guest sessions)
    /// - Parameter sessionScope: Memory access scope to filter by (guests get egoicOnly)
    func injectSalientWithScope(
        conversation: [Message],
        memories: [Memory],
        availableTokens: Int,
        sessionScope: MemoryAccessScope,
        correlationId: String,
        settings: MemoryInjectionSettings = .default,
        userName: String? = nil
    ) -> SalienceInjectionResult {
        // 0. Filter memories based on session scope FIRST
        let scopedMemories = filterMemoriesForScope(memories, scope: sessionScope)

        // 1. Extract context from recent conversation
        let conversationContext = extractConversationContext(from: conversation)

        // 2. Get epistemic grounding
        let epistemicContext = epistemicEngine.ground(
            userMessage: conversationContext.recentQuery,
            memories: scopedMemories,
            correlationId: correlationId
        )

        // 3. Rank memories by salience
        let rankedMemories = rankBySalience(
            memories: scopedMemories,
            context: conversationContext,
            settings: settings
        )

        // 4. Select memories within token budget
        let (selectedMemories, usedTokens) = selectWithinBudget(
            rankedMemories: rankedMemories,
            availableTokens: availableTokens,
            settings: settings
        )

        // 5. Format injection block with personalized name
        let injectionBlock = formatInjectionBlock(
            memories: selectedMemories,
            epistemicContext: epistemicContext,
            settings: settings,
            userName: userName,
            scope: sessionScope
        )

        // 6. Log predicate
        predicateLogger.logSalienceInjection(
            memoryCount: selectedMemories.count,
            tokenCount: usedTokens,
            correlationId: correlationId
        )

        return SalienceInjectionResult(
            injectionBlock: injectionBlock,
            selectedMemories: selectedMemories,
            epistemicContext: epistemicContext,
            tokenCount: usedTokens,
            totalCandidates: memories.count,
            scopedCandidates: scopedMemories.count,
            appliedScope: sessionScope
        )
    }

    // MARK: - Scope-Based Filtering

    /// Filter memories based on access scope (used for guest sessions)
    private func filterMemoriesForScope(_ memories: [Memory], scope: MemoryAccessScope) -> [Memory] {
        switch scope {
        case .full:
            // Host sessions get all memories
            return memories

        case .egoicOnly:
            // Guest sessions only get egoic (learned patterns) memories
            // Filter out allocentric (personal facts) and low-confidence memories
            let sharingSettings = SettingsViewModel.shared.settings.sharingSettings
            let excludedTags = Set(sharingSettings.excludedTags)

            return memories.filter { memory in
                // Must be egoic type
                let isEgoic = memory.type == .egoic || memory.type.toNewSchema == .egoic

                // Must have reasonable confidence
                let hasConfidence = memory.confidence >= 0.7

                // Must not have excluded tags
                let hasExcludedTag = !memory.tags.filter { excludedTags.contains($0.lowercased()) }.isEmpty

                return isEgoic && hasConfidence && !hasExcludedTag
            }

        case .none:
            // No memory access
            return []
        }
    }

    /// Check if a memory is shareable with guests
    func isMemoryShareable(_ memory: Memory) -> Bool {
        let sharingSettings = SettingsViewModel.shared.settings.sharingSettings
        let excludedTags = Set(sharingSettings.excludedTags)

        // Must be egoic
        let isEgoic = memory.type == .egoic || memory.type.toNewSchema == .egoic

        // Must have reasonable confidence
        let hasConfidence = memory.confidence >= 0.7

        // Must not have excluded tags
        let hasExcludedTag = !memory.tags.filter { excludedTags.contains($0.lowercased()) }.isEmpty

        return isEgoic && hasConfidence && !hasExcludedTag
    }

    // MARK: - Context Extraction

    /// Extract relevant context from conversation history
    private func extractConversationContext(from messages: [Message]) -> ConversationContext {
        // Get recent user messages
        let userMessages = messages.filter { $0.role == .user }
        let recentUserMessages = userMessages.suffix(3)

        // Extract the most recent query
        let recentQuery = recentUserMessages.last?.content ?? ""

        // Extract topics from recent messages
        var topics: Set<String> = []
        for message in recentUserMessages {
            let words = message.content
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
                .map { $0.lowercased() }
            topics.formUnion(words)
        }

        // Calculate conversation recency
        let mostRecentTimestamp = messages.last?.timestamp ?? Date()

        return ConversationContext(
            recentQuery: recentQuery,
            topics: Array(topics),
            messageCount: messages.count,
            mostRecentTimestamp: mostRecentTimestamp
        )
    }

    // MARK: - Salience Ranking

    /// Rank memories by salience score
    private func rankBySalience(
        memories: [Memory],
        context: ConversationContext,
        settings: MemoryInjectionSettings
    ) -> [RankedMemory] {
        return memories.map { memory in
            let score = calculateSalienceScore(
                memory: memory,
                context: context,
                settings: settings
            )
            return RankedMemory(memory: memory, salienceScore: score)
        }
        .filter { $0.salienceScore >= settings.minSalienceThreshold }
        .sorted { $0.salienceScore > $1.salienceScore }
    }

    /// Calculate salience score for a memory
    private func calculateSalienceScore(
        memory: Memory,
        context: ConversationContext,
        settings: MemoryInjectionSettings
    ) -> Double {
        var score: Double = 0.0

        // 1. Relevance Score (0-0.4)
        let relevanceScore = calculateRelevanceScore(memory: memory, context: context)
        score += relevanceScore * settings.relevanceWeight

        // 2. Confidence Score (0-0.3)
        let confidenceScore = memory.confidence
        score += confidenceScore * settings.confidenceWeight

        // 3. Recency Score (0-0.2)
        let recencyScore = calculateRecencyScore(memory: memory)
        score += recencyScore * settings.recencyWeight

        // 4. Access Frequency Boost (0-0.1)
        let accessBoost = min(Double(memory.accessCount) / 10.0, 1.0) * 0.1
        score += accessBoost

        // 5. Type-based boost
        if memory.type.isNewSchema {
            score += 0.05 // Prefer allocentric/egoic over legacy types
        }

        // 6. Temporal Relevance Boost (0-0.3)
        // When user asks about specific times ("yesterday", "last week"), boost matching memories
        let temporalBoost = calculateTemporalRelevanceBoost(memory: memory, query: context.recentQuery)
        score += temporalBoost

        return min(score, 1.0)
    }

    private func calculateRelevanceScore(memory: Memory, context: ConversationContext) -> Double {
        let memoryText = (memory.content + " " + memory.tags.joined(separator: " ")).lowercased()

        // Count topic matches
        var matches = 0
        for topic in context.topics {
            if memoryText.contains(topic) {
                matches += 1
            }
        }

        // Also check against the recent query
        let queryWords = context.recentQuery
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
            .map { $0.lowercased() }

        for word in queryWords {
            if memoryText.contains(word) {
                matches += 1
            }
        }

        // Normalize by total possible matches
        let totalPossible = context.topics.count + queryWords.count
        guard totalPossible > 0 else { return 0.0 }

        return min(Double(matches) / Double(totalPossible) * 2.0, 1.0)
    }

    private func calculateRecencyScore(memory: Memory) -> Double {
        let ageInDays = Date().timeIntervalSince(memory.updatedAt) / (24 * 60 * 60)

        // Decay function: score decreases with age
        // Full score for memories < 1 day old
        // Half score at 7 days
        // Minimum 0.1 for old memories
        if ageInDays < 1 {
            return 1.0
        } else if ageInDays < 7 {
            return 1.0 - (ageInDays / 7.0) * 0.5
        } else if ageInDays < 30 {
            return 0.5 - ((ageInDays - 7) / 23.0) * 0.3
        } else {
            return max(0.1, 0.2 - (ageInDays - 30) / 365.0 * 0.1)
        }
    }

    /// Calculate temporal relevance boost based on query keywords
    /// When user asks about "yesterday" or "last week", boost memories with matching temporal tags
    private func calculateTemporalRelevanceBoost(memory: Memory, query: String) -> Double {
        let queryLower = query.lowercased()
        var boost: Double = 0.0

        // Get refreshed temporal tags for accurate matching
        let memoryTags = memory.refreshedTemporalTags

        // Temporal patterns: (query keywords, matching tags, boost value)
        let temporalPatterns: [(keywords: [String], matchTags: [String], boost: Double)] = [
            // Today/recent
            (["today", "just now", "earlier today", "this morning", "this afternoon"],
             ["today"], 0.3),

            // Yesterday
            (["yesterday", "last night", "night before"],
             ["yesterday"], 0.25),

            // This week
            (["this week", "few days ago", "recently", "the other day", "past few days"],
             ["this_week"], 0.2),

            // Specific days of week
            (["monday"], ["monday"], 0.25),
            (["tuesday"], ["tuesday"], 0.25),
            (["wednesday"], ["wednesday"], 0.25),
            (["thursday"], ["thursday"], 0.25),
            (["friday"], ["friday"], 0.25),
            (["saturday"], ["saturday"], 0.25),
            (["sunday"], ["sunday"], 0.25),

            // Last week / month
            (["last week", "week ago", "past week"],
             ["this_month"], 0.15),
            (["last month", "few weeks ago", "month ago"],
             ["this_month", "recent_months"], 0.1),

            // Seasons
            (["winter", "this winter"],
             ["winter"], 0.1),
            (["spring", "this spring"],
             ["spring"], 0.1),
            (["summer", "this summer"],
             ["summer"], 0.1),
            (["fall", "autumn", "this fall"],
             ["fall"], 0.1),
        ]

        for pattern in temporalPatterns {
            // Check if query contains any of the keywords
            if pattern.keywords.contains(where: { queryLower.contains($0) }) {
                // Check if memory has any matching temporal tag
                if memoryTags.contains(where: { tag in
                    pattern.matchTags.contains(tag.lowercased())
                }) {
                    boost = max(boost, pattern.boost)
                }
            }
        }

        return boost
    }

    // MARK: - Budget Selection

    /// Select memories within token budget
    private func selectWithinBudget(
        rankedMemories: [RankedMemory],
        availableTokens: Int,
        settings: MemoryInjectionSettings
    ) -> ([RankedMemory], Int) {
        var selected: [RankedMemory] = []
        var usedTokens = 0

        // Reserve tokens for header/footer
        let reservedTokens = 200
        let effectiveBudget = availableTokens - reservedTokens

        for rankedMemory in rankedMemories {
            // Estimate tokens for this memory
            let memoryTokens = estimateTokens(for: rankedMemory.memory)

            if usedTokens + memoryTokens <= effectiveBudget {
                selected.append(rankedMemory)
                usedTokens += memoryTokens

                // Respect max memories setting
                if selected.count >= settings.maxMemories {
                    break
                }
            }
        }

        return (selected, usedTokens + reservedTokens)
    }

    private func estimateTokens(for memory: Memory) -> Int {
        let text = memory.content + memory.tags.joined(separator: " ") + (memory.context ?? "")
        return Int(Double(text.count) * tokensPerChar) + 50 // +50 for formatting
    }

    // MARK: - Formatting

    /// Format the injection block for the system prompt
    /// Uses the user's first name for personalized headers
    private func formatInjectionBlock(
        memories: [RankedMemory],
        epistemicContext: EpistemicContext,
        settings: MemoryInjectionSettings,
        userName: String? = nil,
        scope: MemoryAccessScope = .full
    ) -> String {
        var lines: [String] = []

        // Only include if we have memories
        guard !memories.isEmpty else {
            return ""
        }

        // Extract first name for personalization
        let firstName = userName?.components(separatedBy: " ").first

        // Header - first-person framing for intrinsic memory
        // Adjust header based on scope (guest sessions get different framing)
        lines.append("")
        if scope == .egoicOnly {
            // Guest session - frame as shared patterns
            lines.append("## Shared Problem-Solving Patterns")
            lines.append("*These are learned approaches that may help with your task:*")
        } else if let name = firstName {
            lines.append("## What I Remember About \(name)")
        } else {
            lines.append("## What I Remember")
        }
        lines.append("")

        // Memories by type - first-person framing with personalized headers
        let allocentricMemories = memories.filter { $0.memory.type == .allocentric || $0.memory.type.toNewSchema == .allocentric }
        let egoicMemories = memories.filter { $0.memory.type == .egoic || $0.memory.type.toNewSchema == .egoic }

        // Only show allocentric memories for full access (not guest sessions)
        if !allocentricMemories.isEmpty && scope == .full {
            if let name = firstName {
                lines.append("### About \(name)")
            } else {
                lines.append("### About them")
            }
            for ranked in allocentricMemories {
                lines.append(formatMemoryLine(ranked, includeConfidence: settings.showConfidence))
            }
            lines.append("")
        }

        if !egoicMemories.isEmpty {
            if scope == .egoicOnly {
                // Guest session - neutral framing without personal references
                lines.append("### Learned Approaches")
            } else if let name = firstName {
                lines.append("### What works with \(name)")
            } else {
                lines.append("### What works")
            }
            for ranked in egoicMemories {
                lines.append(formatMemoryLine(ranked, includeConfidence: settings.showConfidence))
            }
            lines.append("")
        }

        // Epistemic boundaries (if verbose mode and full access)
        if settings.includeEpistemicBoundaries && scope == .full {
            lines.append("### Epistemic Boundaries")
            for grounded in epistemicContext.shiftLog.epistemicScope.grounded.prefix(2) {
                lines.append("- ✓ \(grounded)")
            }
            for unknown in epistemicContext.shiftLog.epistemicScope.unknown.prefix(2) {
                lines.append("- ? \(unknown)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func formatMemoryLine(_ ranked: RankedMemory, includeConfidence: Bool) -> String {
        let memory = ranked.memory
        var line = "- \(memory.content)"

        if includeConfidence {
            let conf = Int(memory.confidence * 100)
            line += " *(conf: \(conf)%)*"
        }

        if !memory.tags.isEmpty {
            line += " `[\(memory.tags.prefix(3).joined(separator: ", "))]`"
        }

        return line
    }
}

// MARK: - Supporting Types

struct ConversationContext {
    let recentQuery: String
    let topics: [String]
    let messageCount: Int
    let mostRecentTimestamp: Date
}

struct RankedMemory {
    let memory: Memory
    let salienceScore: Double
}

struct SalienceInjectionResult {
    let injectionBlock: String
    let selectedMemories: [RankedMemory]
    let epistemicContext: EpistemicContext
    let tokenCount: Int
    let totalCandidates: Int
    let scopedCandidates: Int
    let appliedScope: MemoryAccessScope

    init(
        injectionBlock: String,
        selectedMemories: [RankedMemory],
        epistemicContext: EpistemicContext,
        tokenCount: Int,
        totalCandidates: Int,
        scopedCandidates: Int? = nil,
        appliedScope: MemoryAccessScope = .full
    ) {
        self.injectionBlock = injectionBlock
        self.selectedMemories = selectedMemories
        self.epistemicContext = epistemicContext
        self.tokenCount = tokenCount
        self.totalCandidates = totalCandidates
        self.scopedCandidates = scopedCandidates ?? totalCandidates
        self.appliedScope = appliedScope
    }

    var isEmpty: Bool {
        selectedMemories.isEmpty
    }

    /// Number of memories filtered out by scope
    var memoriesFilteredByScope: Int {
        totalCandidates - scopedCandidates
    }

    /// Whether this result used scope filtering
    var usedScopeFiltering: Bool {
        appliedScope != .full
    }
}

/// Result of tag-filtered memory injection (for sub-agent context)
struct TagFilteredInjectionResult {
    let injectionBlock: String
    let selectedMemories: [RankedMemory]
    let tokenCount: Int
    let totalCandidates: Int
    let matchingCandidates: Int
    let appliedTags: [String]

    var isEmpty: Bool {
        selectedMemories.isEmpty
    }

    /// Number of memories that didn't match any tags
    var memoriesNotMatchingTags: Int {
        totalCandidates - matchingCandidates
    }

    /// Summary for debugging/display
    var summary: String {
        if isEmpty {
            return "No memories matched tags: \(appliedTags.joined(separator: ", "))"
        }
        return "\(selectedMemories.count) memories injected (\(tokenCount) tokens) from \(matchingCandidates) matches"
    }
}

struct MemoryInjectionSettings {
    var maxMemories: Int
    var minSalienceThreshold: Double
    var relevanceWeight: Double
    var confidenceWeight: Double
    var recencyWeight: Double
    var showConfidence: Bool
    var includeEpistemicBoundaries: Bool

    static let `default` = MemoryInjectionSettings(
        maxMemories: 10,
        minSalienceThreshold: 0.2,
        relevanceWeight: 0.4,
        confidenceWeight: 0.3,
        recencyWeight: 0.2,
        showConfidence: true,
        includeEpistemicBoundaries: false
    )

    static let verbose = MemoryInjectionSettings(
        maxMemories: 15,
        minSalienceThreshold: 0.15,
        relevanceWeight: 0.4,
        confidenceWeight: 0.3,
        recencyWeight: 0.2,
        showConfidence: true,
        includeEpistemicBoundaries: true
    )

    static let minimal = MemoryInjectionSettings(
        maxMemories: 5,
        minSalienceThreshold: 0.3,
        relevanceWeight: 0.5,
        confidenceWeight: 0.3,
        recencyWeight: 0.1,
        showConfidence: false,
        includeEpistemicBoundaries: false
    )
}

// MARK: - Salience Service Extensions

extension SalienceService {

    // MARK: - Tag-Based Filtering (for Sub-Agent Context Injection)

    /// Filter memories by tags for sub-agent context injection
    /// Used by AgentOrchestratorService to inject tag-filtered memories into sub-agent contexts
    ///
    /// - Parameters:
    ///   - memories: All available memories
    ///   - tags: Tags to filter by (OR logic - memory must match at least one tag)
    ///   - maxTokens: Maximum token budget for the injection
    ///   - correlationId: Correlation ID for logging
    /// - Returns: Filtered and ranked memories within token budget
    func filterMemoriesByTags(
        memories: [Memory],
        tags: [String],
        maxTokens: Int,
        correlationId: String
    ) -> TagFilteredInjectionResult {
        guard !tags.isEmpty else {
            return TagFilteredInjectionResult(
                injectionBlock: "",
                selectedMemories: [],
                tokenCount: 0,
                totalCandidates: memories.count,
                matchingCandidates: 0,
                appliedTags: []
            )
        }

        // Normalize tags for matching
        let normalizedTags = Set(tags.map { normalizeTag($0) })

        // Filter memories that match any of the specified tags
        let matchingMemories = memories.filter { memory in
            let memoryTags = Set(memory.tags.map { normalizeTag($0) })
            return !memoryTags.isDisjoint(with: normalizedTags)
        }

        guard !matchingMemories.isEmpty else {
            return TagFilteredInjectionResult(
                injectionBlock: "",
                selectedMemories: [],
                tokenCount: 0,
                totalCandidates: memories.count,
                matchingCandidates: 0,
                appliedTags: tags
            )
        }

        // Create a minimal context for ranking
        let context = ConversationContext(
            recentQuery: tags.joined(separator: " "),
            topics: tags,
            messageCount: 0,
            mostRecentTimestamp: Date()
        )

        // Rank by salience
        let rankedMemories = rankBySalience(
            memories: matchingMemories,
            context: context,
            settings: .minimal
        )

        // Select within budget
        let (selectedMemories, usedTokens) = selectWithinBudget(
            rankedMemories: rankedMemories,
            availableTokens: maxTokens,
            settings: .minimal
        )

        // Format injection block
        let injectionBlock = formatTagFilteredInjection(
            memories: selectedMemories,
            tags: tags
        )

        // Log predicate
        predicateLogger.logSalienceInjection(
            memoryCount: selectedMemories.count,
            tokenCount: usedTokens,
            correlationId: correlationId
        )

        return TagFilteredInjectionResult(
            injectionBlock: injectionBlock,
            selectedMemories: selectedMemories,
            tokenCount: usedTokens,
            totalCandidates: memories.count,
            matchingCandidates: matchingMemories.count,
            appliedTags: tags
        )
    }

    /// Normalize a tag for consistent matching (matches AgentOrchestratorService.normalizeTag)
    private func normalizeTag(_ tag: String) -> String {
        tag.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "_")
    }

    /// Format injection block for tag-filtered memories
    private func formatTagFilteredInjection(
        memories: [RankedMemory],
        tags: [String]
    ) -> String {
        guard !memories.isEmpty else { return "" }

        var lines: [String] = []

        lines.append("")
        lines.append("## Relevant Context")
        lines.append("*Memories filtered by tags: \(tags.joined(separator: ", "))*")
        lines.append("")

        // Group by type
        let allocentricMemories = memories.filter {
            $0.memory.type == .allocentric || $0.memory.type.toNewSchema == .allocentric
        }
        let egoicMemories = memories.filter {
            $0.memory.type == .egoic || $0.memory.type.toNewSchema == .egoic
        }
        let otherMemories = memories.filter {
            let type = $0.memory.type.toNewSchema
            return type != .allocentric && type != .egoic
        }

        if !allocentricMemories.isEmpty {
            lines.append("### Facts")
            for ranked in allocentricMemories {
                lines.append(formatTagFilteredMemoryLine(ranked))
            }
            lines.append("")
        }

        if !egoicMemories.isEmpty {
            lines.append("### Patterns & Approaches")
            for ranked in egoicMemories {
                lines.append(formatTagFilteredMemoryLine(ranked))
            }
            lines.append("")
        }

        if !otherMemories.isEmpty {
            lines.append("### Other")
            for ranked in otherMemories {
                lines.append(formatTagFilteredMemoryLine(ranked))
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func formatTagFilteredMemoryLine(_ ranked: RankedMemory) -> String {
        let memory = ranked.memory
        var line = "- \(memory.content)"

        // Show confidence for context
        let conf = Int(memory.confidence * 100)
        line += " *(conf: \(conf)%)*"

        // Show matching tags
        if !memory.tags.isEmpty {
            line += " `[\(memory.tags.prefix(3).joined(separator: ", "))]`"
        }

        return line
    }

    // MARK: - Quick Injection

    /// Quick injection for simple cases
    func quickInject(
        query: String,
        memories: [Memory],
        maxTokens: Int = 1000
    ) -> String {
        let correlationId = PredicateLogger.shared.startCorrelation()
        defer { PredicateLogger.shared.endCorrelation() }

        // Create a minimal message array
        let mockMessages = [
            Message(
                conversationId: "temp",
                role: .user,
                content: query
            )
        ]

        let result = injectSalient(
            conversation: mockMessages,
            memories: memories,
            availableTokens: maxTokens,
            correlationId: correlationId,
            settings: .minimal
        )

        return result.injectionBlock
    }

    /// Check if injection would be useful for a query
    func wouldBenefitFromInjection(
        query: String,
        memories: [Memory]
    ) -> Bool {
        let context = ConversationContext(
            recentQuery: query,
            topics: [],
            messageCount: 1,
            mostRecentTimestamp: Date()
        )

        let ranked = rankBySalience(
            memories: memories,
            context: context,
            settings: .default
        )

        return !ranked.isEmpty
    }
}
