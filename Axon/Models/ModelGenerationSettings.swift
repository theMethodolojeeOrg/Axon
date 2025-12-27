//
//  ModelGenerationSettings.swift
//  Axon
//
//  Settings for AI model generation parameters (temperature, top-p, top-k)
//  and custom system prompt suffix.
//

import Foundation

// MARK: - Model Generation Settings

struct ModelGenerationSettings: Codable, Equatable, Sendable {
    // Temperature (0.0-1.0): Lower = deterministic, Higher = creative
    var temperature: Double = 0.7
    var temperatureEnabled: Bool = false
    
    // Top-P / Nucleus sampling (0.0-1.0)
    var topP: Double = 1.0
    var topPEnabled: Bool = false
    
    // Top-K: Token candidates (Anthropic/Gemini only)
    var topK: Int = 40
    var topKEnabled: Bool = false

    // Repetition Penalty (Local MLX models only): Prevents repetitive/looping output
    var repetitionPenalty: Double = 1.2
    var repetitionPenaltyEnabled: Bool = true  // Enabled by default to prevent runaway generation

    // Repetition Context Size: How many tokens to look back for repetition detection
    var repetitionContextSize: Int = 64

    // Max Response Tokens (Local MLX models only): Limits response length
    var maxResponseTokens: Int = 2048
    var maxResponseTokensEnabled: Bool = false

    // Custom system prompt suffix appended after epistemic prompt
    var systemPromptSuffix: String = ""
    var systemPromptSuffixEnabled: Bool = false
}

// MARK: - Provider Parameter Support

/// Describes which generation parameters a provider supports
struct ProviderParameterSupport {
    let supportsTemperature: Bool
    let supportsTopP: Bool
    let supportsTopK: Bool
    
    static func support(for provider: String) -> ProviderParameterSupport {
        switch provider.lowercased() {
        case "anthropic":
            return ProviderParameterSupport(supportsTemperature: true, supportsTopP: true, supportsTopK: true)
        case "gemini":
            return ProviderParameterSupport(supportsTemperature: true, supportsTopP: true, supportsTopK: true)
        case "openai", "grok", "perplexity", "deepseek", "zai", "mistral", "minimax":
            return ProviderParameterSupport(supportsTemperature: true, supportsTopP: true, supportsTopK: false)
        default:
            // Custom providers - assume OpenAI-compatible
            return ProviderParameterSupport(supportsTemperature: true, supportsTopP: true, supportsTopK: false)
        }
    }
}

// MARK: - Parameter Dictionary Builder

extension ModelGenerationSettings {
    /// Build a dictionary of generation parameters for a specific provider
    /// Only includes parameters that are both enabled and supported by the provider
    func parameters(for provider: String) -> [String: Any] {
        let support = ProviderParameterSupport.support(for: provider)
        var params: [String: Any] = [:]
        
        if temperatureEnabled && support.supportsTemperature {
            params["temperature"] = temperature
        }
        
        if topPEnabled && support.supportsTopP {
            params["top_p"] = topP
        }
        
        if topKEnabled && support.supportsTopK {
            params["top_k"] = topK
        }
        
        return params
    }
    
    /// Get the system prompt suffix if enabled and non-empty
    var effectiveSystemPromptSuffix: String? {
        guard systemPromptSuffixEnabled, !systemPromptSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return systemPromptSuffix
    }
}
