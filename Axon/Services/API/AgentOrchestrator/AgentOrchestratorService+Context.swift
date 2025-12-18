//
//  AgentOrchestratorService+Context.swift
//  Axon
//
//  Context building for sub-agent jobs with tag-filtered memory injection.
//
//  Sub-agents receive context based on their MemoryInjectionScope:
//  - .none: No memories
//  - .tagFiltered: Only memories matching context_injection tags
//  - .inherited: Context from parent job's silo
//  - .full: Full memory access (like main Axon)
//

import Foundation
import os.log

// MARK: - Context Extension

extension AgentOrchestratorService {

    // MARK: - Build Context for Job

    /// Build the context for a sub-agent job based on its permissions.
    func buildContextForJob(_ job: SubAgentJob) async throws -> SubAgentContext {

        switch job.permissions.memoryScope {

        case .none:
            // No memory injection
            return SubAgentContext(
                memoryInjection: "",
                inheritedContext: nil,
                toolRestrictions: job.permissions.allowedTools
            )

        case .tagFiltered:
            // Only inject memories matching specified tags
            let memoryInjection = await buildTagFilteredMemoryInjection(
                tags: job.contextInjectionTags,
                maxTokens: min(job.permissions.maxTokenBudget ?? 2000, 2000)
            )

            return SubAgentContext(
                memoryInjection: memoryInjection,
                inheritedContext: nil,
                toolRestrictions: job.permissions.allowedTools
            )

        case .inherited:
            // Get context from parent job's silo
            let inheritedContext = await buildInheritedContext(for: job)

            return SubAgentContext(
                memoryInjection: "",
                inheritedContext: inheritedContext,
                toolRestrictions: job.permissions.allowedTools
            )

        case .full:
            // Full memory access (like main Axon)
            let memoryInjection = await buildFullMemoryInjection(
                maxTokens: min(job.permissions.maxTokenBudget ?? 4000, 4000)
            )

            return SubAgentContext(
                memoryInjection: memoryInjection,
                inheritedContext: nil,
                toolRestrictions: job.permissions.allowedTools
            )
        }
    }

    // MARK: - Tag-Filtered Memory Injection

    /// Build memory injection using only memories matching specified tags.
    private func buildTagFilteredMemoryInjection(
        tags: [String],
        maxTokens: Int
    ) async -> String {
        guard !tags.isEmpty else {
            return ""
        }

        // Normalize tags
        let normalizedTags = Set(tags.map {
            $0.lowercased()
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "#", with: "")
        })

        // This would integrate with MemoryService to filter by tags
        // For now, return a placeholder that indicates the intended behavior
        let tagList = normalizedTags.joined(separator: ", ")

        return """
        [Context filtered by tags: \(tagList)]

        Note: Memory injection will be populated by SalienceService.filterMemoriesByTags()
        when integrated. For now, this sub-agent operates with the following context scope:
        - Tags: \(tags.joined(separator: ", "))
        - Max tokens: \(maxTokens)
        """
    }

    // MARK: - Inherited Context

    /// Build context inherited from a parent job's silo.
    private func buildInheritedContext(for job: SubAgentJob) async -> String? {
        // First check if there's a parent job
        guard let parentJobId = job.parentJobId else {
            // No parent - check if any recent job could provide context
            return nil
        }

        // Get parent job
        guard let parentJob = (activeJobs + completedJobs).first(where: { $0.id == parentJobId }),
              let parentSiloId = parentJob.siloId,
              let parentSilo = silos[parentSiloId] else {
            return nil
        }

        // Build context from parent silo's summary
        let summary = parentSilo.summary()

        var context = """
        ## Inherited Context from \(parentJob.role.displayName) Job

        **Parent Task:** \(parentJob.task.prefix(200))
        **Status:** \(parentJob.state.displayName)

        """

        // Include top inferences
        if !summary.topInferences.isEmpty {
            context += "### Key Findings\n"
            for inference in summary.topInferences {
                let confidence = inference.confidence.map { " (\(Int($0 * 100))% confidence)" } ?? ""
                context += "- \(inference.content.prefix(300))\(confidence)\n"
            }
            context += "\n"
        }

        // Include flagged items
        if !summary.flaggedItems.isEmpty {
            context += "### Items Needing Attention\n"
            for item in summary.flaggedItems.prefix(3) {
                context += "- [\(item.type.displayName)] \(item.content.prefix(200))\n"
            }
            context += "\n"
        }

        // Include pending questions (if this job is meant to answer them)
        if !summary.pendingQuestions.isEmpty {
            context += "### Questions from Parent\n"
            for question in summary.pendingQuestions {
                context += "- \(question.content)\n"
            }
            context += "\n"
        }

        return context
    }

    // MARK: - Full Memory Injection

    /// Build full memory injection (like main Axon).
    /// Used sparingly - only for Designer agents that need full context.
    private func buildFullMemoryInjection(maxTokens: Int) async -> String {
        // This would integrate with SalienceService for full memory access
        // For now, return a placeholder
        return """
        [Full memory access enabled]

        This sub-agent has full memory access like the main Axon instance.
        Memory injection will be populated by SalienceService.injectSalient()
        when integrated.

        Max tokens: \(maxTokens)
        """
    }

    // MARK: - Context for Follow-up

    /// Build context for a follow-up job (e.g., after receiving clarification).
    func buildFollowUpContext(
        for job: SubAgentJob,
        clarification: String
    ) async throws -> SubAgentContext {
        // Get the base context
        var context = try await buildContextForJob(job)

        // Add clarification as inherited context
        let clarificationContext = """
        ## Clarification from Axon

        \(clarification)

        ---

        Please proceed with the original task, taking this clarification into account.
        """

        if let existing = context.inheritedContext {
            context = SubAgentContext(
                memoryInjection: context.memoryInjection,
                inheritedContext: existing + "\n\n" + clarificationContext,
                toolRestrictions: context.toolRestrictions
            )
        } else {
            context = SubAgentContext(
                memoryInjection: context.memoryInjection,
                inheritedContext: clarificationContext,
                toolRestrictions: context.toolRestrictions
            )
        }

        return context
    }

    // MARK: - Context Summary

    /// Generate a summary of what context was injected (for debugging/display).
    func describeContext(_ context: SubAgentContext) -> String {
        var description: [String] = []

        if !context.memoryInjection.isEmpty {
            let estimatedTokens = context.memoryInjection.count / 4
            description.append("Memory: ~\(estimatedTokens) tokens")
        }

        if context.inheritedContext != nil {
            description.append("Inherited context from parent")
        }

        if !context.toolRestrictions.isEmpty {
            description.append("\(context.toolRestrictions.count) tools available")
        } else {
            description.append("No tools")
        }

        return description.isEmpty ? "Empty context" : description.joined(separator: ", ")
    }
}

// MARK: - Sub-Agent Context

/// Context prepared for a sub-agent job.
struct SubAgentContext: Sendable {
    /// Memory injection text (from memories matching tags or full access)
    let memoryInjection: String

    /// Context inherited from parent job's silo
    let inheritedContext: String?

    /// Tools this sub-agent is allowed to use
    let toolRestrictions: [ToolId]

    /// Estimated total tokens in context
    var estimatedTokens: Int {
        let memoryTokens = memoryInjection.count / 4
        let inheritedTokens = (inheritedContext?.count ?? 0) / 4
        return memoryTokens + inheritedTokens
    }

    /// Whether this context has any content
    var isEmpty: Bool {
        memoryInjection.isEmpty && inheritedContext == nil
    }
}

// MARK: - Memory Tag Helpers

extension AgentOrchestratorService {

    /// Normalize a tag for consistent matching
    static func normalizeTag(_ tag: String) -> String {
        tag.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "_")
    }

    /// Parse tags from a context_injection string like "#Tag1, #Tag2"
    static func parseTags(from string: String) -> [String] {
        string.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { normalizeTag($0) }
            .filter { !$0.isEmpty }
    }

    /// Check if a memory's tags match the injection tags
    static func memoryMatchesTags(
        memoryTags: [String],
        injectionTags: [String]
    ) -> Bool {
        let normalizedMemoryTags = Set(memoryTags.map { normalizeTag($0) })
        let normalizedInjectionTags = Set(injectionTags.map { normalizeTag($0) })
        return !normalizedMemoryTags.isDisjoint(with: normalizedInjectionTags)
    }
}

// MARK: - Context Presets

extension SubAgentContext {
    /// Empty context for sandboxed execution
    static let empty = SubAgentContext(
        memoryInjection: "",
        inheritedContext: nil,
        toolRestrictions: []
    )

    /// Minimal context with basic tools
    static func minimal(tools: [ToolId]) -> SubAgentContext {
        SubAgentContext(
            memoryInjection: "",
            inheritedContext: nil,
            toolRestrictions: tools
        )
    }
}
