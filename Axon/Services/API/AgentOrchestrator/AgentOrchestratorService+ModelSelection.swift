//
//  AgentOrchestratorService+ModelSelection.swift
//  Axon
//
//  Intelligent model selection based on tiers and learned affinities.
//
//  **Architectural Commandment #3**: ModelTaskAffinity is Axon's long-term intuition.
//  "I'm sending Grok for this because the last three times Haiku tried to map
//  a VSIX directory, it missed the activation events."
//

import Foundation
import os.log

// MARK: - Model Selection Extension

extension AgentOrchestratorService {

    // MARK: - Select Model for Job

    /// Select the optimal model for a job based on:
    /// 1. Explicit override (highest priority)
    /// 2. Learned affinities (if sufficient data)
    /// 3. Tier-based fallback (based on role)
    func selectModelForJob(_ job: SubAgentJob) throws -> (AIProvider, String) {

        // 1. Explicit override takes precedence
        if let provider = job.provider, let model = job.model {
            if isProviderConfigured(provider) {
                logger.info("Using explicit override: \(provider.rawValue)/\(model)")
                return (provider, model)
            } else {
                logger.warning("Explicit provider \(provider.rawValue) not configured, falling back")
            }
        }

        // 2. Check learned affinities for this task type
        let taskType = inferTaskType(from: job)
        let contextTags = job.contextInjectionTags

        if let (provider, model, reasoning) = selectFromAffinities(
            taskType: taskType,
            contextTags: contextTags
        ) {
            logger.info("Selected from affinities: \(provider.rawValue)/\(model) - \(reasoning)")
            return (provider, model)
        }

        // 3. Fall back to tier-based selection
        let tier = job.modelTierPreference ?? job.role.recommendedModelTiers.first ?? .balanced
        return try selectModelByTier(tier, for: job.role)
    }

    // MARK: - Affinity-Based Selection

    /// Select model based on learned task affinities.
    /// Returns nil if insufficient data for confident selection.
    private func selectFromAffinities(
        taskType: TaskType,
        contextTags: [String]
    ) -> (AIProvider, String, String)? {
        let contextHash = ModelTaskAffinity.hashContextTags(contextTags)

        // Minimum attempts required for affinity-based selection
        let minAttempts = 3

        // First try exact context match
        let exactMatches = modelAffinities
            .filter { $0.taskType == taskType && $0.contextTagsHash == contextHash }
            .filter { $0.totalAttempts >= minAttempts }
            .sorted { $0.affinityScore > $1.affinityScore }

        if let best = exactMatches.first, isProviderConfigured(best.provider) {
            let reasoning = buildAffinityReasoning(for: best)
            return (best.provider, best.modelId, reasoning)
        }

        // Fall back to any context match
        let anyContextMatches = modelAffinities
            .filter { $0.taskType == taskType }
            .filter { $0.totalAttempts >= minAttempts }
            .sorted { $0.affinityScore > $1.affinityScore }

        for match in anyContextMatches {
            if isProviderConfigured(match.provider) {
                let reasoning = buildAffinityReasoning(for: match)
                return (match.provider, match.modelId, reasoning)
            }
        }

        return nil
    }

    /// Build human-readable reasoning for why a model was selected
    private func buildAffinityReasoning(for affinity: ModelTaskAffinity) -> String {
        var parts: [String] = []

        // Success rate
        let successPercent = Int(affinity.successRate * 100)
        parts.append("\(successPercent)% success rate (\(affinity.successCount)/\(affinity.totalAttempts))")

        // Dominant failure (if any)
        if let dominant = affinity.dominantFailureReason {
            parts.append("watch for \(dominant.displayName.lowercased())")
        }

        // Quality score (if evaluated)
        if affinity.evaluationCount > 0 {
            let qualityPercent = Int(affinity.averageQualityScore * 100)
            parts.append("\(qualityPercent)% quality")
        }

        // Cost efficiency
        if affinity.averageCostUSD > 0 {
            parts.append("~$\(String(format: "%.3f", affinity.averageCostUSD))/request")
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - Tier-Based Selection

    /// Select model based on tier preference and role.
    /// Uses a priority list of models per tier, checking availability.
    func selectModelByTier(
        _ tier: ModelTier,
        for role: SubAgentRole
    ) throws -> (AIProvider, String) {

        // Model priority list by tier
        // Format: (provider, model, tiers)
        let modelPriority: [(AIProvider, String, [ModelTier])] = [
            // Fast tier - optimized for speed
            (.anthropic, "claude-haiku-4-5-20251001", [.fast]),
            (.xai, "grok-4-fast-non-reasoning", [.fast]),
            (.gemini, "gemini-2.5-flash-lite-preview-06-17", [.fast]),
            (.openai, "gpt-4o-mini", [.fast]),

            // Cheap tier - cost optimized
            (.deepseek, "deepseek-chat", [.cheap]),
            (.minimax, "minimax-m2", [.cheap]),
            (.openai, "gpt-4o-mini", [.cheap]),
            (.gemini, "gemini-2.5-flash-lite-preview-06-17", [.cheap]),

            // Balanced tier - good all-around
            (.anthropic, "claude-sonnet-4-5-20250929", [.balanced]),
            (.openai, "gpt-4o", [.balanced]),
            (.gemini, "gemini-2.5-flash", [.balanced]),
            (.xai, "grok-4-fast-reasoning", [.balanced]),

            // Capable tier - strong reasoning
            (.gemini, "gemini-2.5-pro", [.capable]),
            (.openai, "o3", [.capable]),
            (.anthropic, "claude-sonnet-4-5-20250929", [.capable]),
            (.xai, "grok-4-reasoning", [.capable]),

            // Flagship tier - best available
            (.anthropic, "claude-opus-4-5-20251022", [.flagship]),
            (.gemini, "gemini-3-pro-preview", [.flagship]),
            (.openai, "o3-pro", [.flagship]),
            (.xai, "grok-4", [.flagship]),
        ]

        // First try exact tier match
        for (provider, model, modelTiers) in modelPriority where modelTiers.contains(tier) {
            if isProviderConfigured(provider) {
                logger.info("Tier \(tier.rawValue) selection: \(provider.rawValue)/\(model)")
                return (provider, model)
            }
        }

        // Fall back to any configured provider, prioritizing by tier proximity
        let tierOrder: [ModelTier] = {
            switch tier {
            case .fast: return [.fast, .cheap, .balanced, .capable, .flagship]
            case .cheap: return [.cheap, .fast, .balanced, .capable, .flagship]
            case .balanced: return [.balanced, .capable, .cheap, .fast, .flagship]
            case .capable: return [.capable, .balanced, .flagship, .cheap, .fast]
            case .flagship: return [.flagship, .capable, .balanced, .cheap, .fast]
            }
        }()

        for fallbackTier in tierOrder {
            for (provider, model, modelTiers) in modelPriority where modelTiers.contains(fallbackTier) {
                if isProviderConfigured(provider) {
                    logger.warning("Tier \(tier.rawValue) unavailable, using \(fallbackTier.rawValue): \(provider.rawValue)/\(model)")
                    return (provider, model)
                }
            }
        }

        throw AgentOrchestratorError.noConfiguredProviders
    }

    // MARK: - Provider Availability

    /// Check if a provider has a valid API key configured
    func isProviderConfigured(_ provider: AIProvider) -> Bool {
        switch provider {
        case .anthropic:
            return (try? apiKeysStorage.getAPIKey(for: .anthropic))?.isEmpty == false
        case .openai:
            return (try? apiKeysStorage.getAPIKey(for: .openai))?.isEmpty == false
        case .gemini:
            return (try? apiKeysStorage.getAPIKey(for: .gemini))?.isEmpty == false
        case .xai:
            return (try? apiKeysStorage.getAPIKey(for: .xai))?.isEmpty == false
        case .deepseek:
            return (try? apiKeysStorage.getAPIKey(for: .deepseek))?.isEmpty == false
        case .minimax:
            return (try? apiKeysStorage.getAPIKey(for: .minimax))?.isEmpty == false
        case .perplexity:
            return (try? apiKeysStorage.getAPIKey(for: .perplexity))?.isEmpty == false
        case .mistral:
            return (try? apiKeysStorage.getAPIKey(for: .mistral))?.isEmpty == false
        case .zai:
            return (try? apiKeysStorage.getAPIKey(for: .zai))?.isEmpty == false
        case .appleFoundation:
            #if canImport(FoundationModels)
            return true
            #else
            return false
            #endif
        case .localMLX:
            // Check if running on device with MLX support
            #if targetEnvironment(simulator)
            return false
            #else
            return true
            #endif
        }
    }

    /// Get all configured providers
    func getConfiguredProviders() -> [AIProvider] {
        AIProvider.allCases.filter { isProviderConfigured($0) }
    }

    // MARK: - Model Recommendation

    /// Get model recommendations for a role with reasoning
    func getModelRecommendations(for role: SubAgentRole) -> [ModelRecommendation] {
        var recommendations: [ModelRecommendation] = []

        // Get typical task type for role
        let taskType: TaskType
        switch role {
        case .scout: taskType = .webResearch
        case .mechanic: taskType = .codeExecution
        case .designer: taskType = .taskDecomposition
        }

        // Check affinities
        let relevantAffinities = modelAffinities
            .filter { $0.taskType == taskType && $0.totalAttempts >= 3 }
            .sorted { $0.affinityScore > $1.affinityScore }

        for affinity in relevantAffinities.prefix(3) {
            if isProviderConfigured(affinity.provider) {
                recommendations.append(ModelRecommendation(
                    provider: affinity.provider,
                    model: affinity.modelId,
                    reasoning: buildAffinityReasoning(for: affinity),
                    source: .affinity,
                    confidence: affinity.affinityScore
                ))
            }
        }

        // Add tier-based recommendations if we don't have enough affinity data
        if recommendations.count < 2 {
            for tier in role.recommendedModelTiers {
                if let (provider, model) = try? selectModelByTier(tier, for: role) {
                    let existing = recommendations.contains { $0.provider == provider && $0.model == model }
                    if !existing {
                        recommendations.append(ModelRecommendation(
                            provider: provider,
                            model: model,
                            reasoning: "Recommended for \(role.displayName) (\(tier.displayName) tier)",
                            source: .tier,
                            confidence: 0.5
                        ))
                    }
                }
            }
        }

        return recommendations
    }

    // MARK: - Avoid List

    /// Get models to avoid for a task type (low success rate)
    func getModelsToAvoid(for taskType: TaskType) -> [(AIProvider, String, String)] {
        return modelAffinities
            .filter { $0.taskType == taskType && $0.successRate < 0.3 && $0.totalAttempts >= 3 }
            .map { affinity in
                let reason: String
                if let dominant = affinity.dominantFailureReason {
                    reason = "Frequently fails with \(dominant.displayName.lowercased())"
                } else {
                    reason = "Low success rate (\(Int(affinity.successRate * 100))%)"
                }
                return (affinity.provider, affinity.modelId, reason)
            }
    }
}

// MARK: - Model Recommendation

struct ModelRecommendation: Identifiable, Sendable {
    let id = UUID()
    let provider: AIProvider
    let model: String
    let reasoning: String
    let source: RecommendationSource
    let confidence: Double

    enum RecommendationSource: Sendable {
        case affinity  // Based on learned task performance
        case tier      // Based on role's default tier
        case explicit  // User override
    }

    var displayName: String {
        "\(provider.displayName) - \(model)"
    }
}
