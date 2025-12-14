//
//  ReasoningExtractor.swift
//  Axon
//
//  Unified extractor for reasoning/thinking tokens from various LLM providers.
//  Each provider exposes chain-of-thought tokens differently:
//    - DeepSeek: `reasoning_content` field in response
//    - Z.ai (Zhipu): `<think>...</think>` tags in content
//    - Perplexity: `<think>...</think>` tags in content
//    - Anthropic: `type: "thinking"` content block (handled separately)
//    - Mistral: `additionalContent['thinking']` block
//    - OpenAI/Google: Hidden (not exposed in API)
//    - MiniMax: Text prefix (informal, not standardized)
//

import Foundation

struct ReasoningExtractionResult {
    let content: String      // The main response content (reasoning stripped)
    let reasoning: String?   // The extracted reasoning/thinking tokens
}

enum ReasoningExtractor {

    // MARK: - Public API

    /// Extract reasoning from content based on provider
    /// Returns the cleaned content and extracted reasoning (if any)
    static func extract(from content: String, provider: String, model: String) -> ReasoningExtractionResult {
        let providerLower = provider.lowercased()
        let modelLower = model.lowercased()

        // Z.ai and Perplexity use <think> tags
        if providerLower == "zai" || providerLower == "perplexity" {
            return extractThinkTags(from: content)
        }

        // Check for <think> tags in any content (some providers may use them)
        if content.contains("<think>") {
            return extractThinkTags(from: content)
        }

        // For providers with dedicated fields (DeepSeek, Mistral), this is handled
        // at the API response parsing level, not here. This function is for
        // content-embedded reasoning only.

        return ReasoningExtractionResult(content: content, reasoning: nil)
    }

    /// Extract reasoning from DeepSeek response (dedicated field)
    static func extractDeepSeekReasoning(content: String?, reasoningContent: String?) -> ReasoningExtractionResult {
        return ReasoningExtractionResult(
            content: content ?? "",
            reasoning: reasoningContent?.isEmpty == false ? reasoningContent : nil
        )
    }

    /// Extract reasoning from Mistral response (additionalContent block)
    static func extractMistralReasoning(content: String?, thinkingContent: String?) -> ReasoningExtractionResult {
        return ReasoningExtractionResult(
            content: content ?? "",
            reasoning: thinkingContent?.isEmpty == false ? thinkingContent : nil
        )
    }

    /// Extract reasoning from Anthropic response (thinking block)
    /// Note: Anthropic uses a separate content block type, so this expects
    /// the thinking text to be pre-extracted from the content blocks
    static func extractAnthropicReasoning(textContent: String?, thinkingContent: String?) -> ReasoningExtractionResult {
        return ReasoningExtractionResult(
            content: textContent ?? "",
            reasoning: thinkingContent?.isEmpty == false ? thinkingContent : nil
        )
    }

    // MARK: - Private Helpers

    /// Extract content from <think>...</think> tags
    /// Used by Z.ai (Zhipu) and Perplexity
    private static func extractThinkTags(from content: String) -> ReasoningExtractionResult {
        // Pattern: <think>reasoning content</think>
        // The reasoning is typically at the start of the response
        let pattern = #"<think>([\s\S]*?)</think>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ReasoningExtractionResult(content: content, reasoning: nil)
        }

        let range = NSRange(content.startIndex..., in: content)
        var reasoning: String? = nil
        var cleanedContent = content

        // Find all <think> blocks and extract reasoning
        let matches = regex.matches(in: content, options: [], range: range)

        if !matches.isEmpty {
            // Extract all reasoning blocks
            var reasoningParts: [String] = []
            for match in matches {
                if let captureRange = Range(match.range(at: 1), in: content) {
                    let thinkContent = String(content[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !thinkContent.isEmpty {
                        reasoningParts.append(thinkContent)
                    }
                }
            }

            if !reasoningParts.isEmpty {
                reasoning = reasoningParts.joined(separator: "\n\n")
            }

            // Remove <think> blocks from content
            cleanedContent = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ReasoningExtractionResult(content: cleanedContent, reasoning: reasoning)
    }
}

// MARK: - Provider Reasoning Capabilities

extension ReasoningExtractor {

    /// Check if a model supports/exposes reasoning tokens
    static func supportsReasoning(provider: String, model: String) -> Bool {
        let providerLower = provider.lowercased()
        let modelLower = model.lowercased()

        switch providerLower {
        case "deepseek":
            // DeepSeek Reasoner (R1) exposes reasoning
            return modelLower.contains("reasoner") || modelLower.contains("r1")

        case "zai":
            // GLM-4.6 models support thinking mode
            return modelLower.contains("4.6")

        case "perplexity":
            // Sonar Reasoning models expose thinking
            return modelLower.contains("reasoning")

        case "anthropic":
            // Claude with extended thinking (requires specific API params)
            return true  // All Claude 4.5 models support it when enabled

        case "mistral":
            // Mistral Large with thinking mode
            return modelLower.contains("large")

        case "openai":
            // o1/o3 family has reasoning but it's hidden
            return false  // Not exposed in API

        case "gemini":
            // Deep Think mode exists but usually hidden
            return false

        case "minimax":
            // Informal reasoning (not standardized)
            return false

        default:
            return false
        }
    }

    /// Get a description of how reasoning is handled for this provider
    static func reasoningDescription(for provider: String) -> String {
        switch provider.lowercased() {
        case "deepseek":
            return "reasoning_content field"
        case "zai":
            return "<think> tags in content"
        case "perplexity":
            return "<think> tags in content"
        case "anthropic":
            return "thinking content block"
        case "mistral":
            return "additionalContent block"
        case "openai":
            return "Hidden (internal)"
        case "gemini":
            return "Hidden (thinking_process)"
        case "minimax":
            return "Text prefix (informal)"
        default:
            return "Not supported"
        }
    }
}
