//
//  ConversationTitleOrchestrator.swift
//  Axon
//
//  Generates concise conversation titles.
//
//  Policy:
//  - Prefer Apple Intelligence / FoundationModels when available.
//  - If unavailable, fall back to the currently selected provider/model in General Settings.
//  - Titles are applied via SettingsStorage.displayNameOverride (not persisted to Conversation.title).
//

import Foundation

@MainActor
final class ConversationTitleOrchestrator {
    static let shared = ConversationTitleOrchestrator()

    private init() {}

    // MARK: - Public

    /// Generate a 3–6 word title for a conversation turn.
    func generateTitle(userMessage: Message, assistantMessage: Message) async throws -> String {
        // 1) Try Apple Intelligence first.
        do {
            let title = try await AppleIntelligenceChatTitleService.shared.generateTitle(
                userMessage: userMessage,
                assistantMessage: assistantMessage
            )
            return sanitizeTitle(title)
        } catch {
            // 2) Fallback to selected provider/model.
            // We intentionally swallow Apple errors and fall back, because Apple availability
            // can change (model downloading, feature toggled, etc.).
            let title = try await generateTitleWithSelectedProvider(
                userMessage: userMessage,
                assistantMessage: assistantMessage,
                appleFailure: error
            )
            return sanitizeTitle(title)
        }
    }

    /// Applies a generated title to displayNameOverride.
    func applyTitle(_ title: String, to conversationId: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SettingsStorage.shared.setDisplayName(trimmed, for: conversationId)
    }

    // MARK: - Private

    private func generateTitleWithSelectedProvider(
        userMessage: Message,
        assistantMessage: Message,
        appleFailure: Error
    ) async throws -> String {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()

        // Resolve provider and model from General Settings selection
        let provider = settings.defaultProvider
        let model = settings.defaultModel ?? ""

        // We need API keys for cloud providers.
        let apiKeysStorage = APIKeysStorage.shared

        let anthropicKey = try? apiKeysStorage.getAPIKey(for: .anthropic)
        let openaiKey = try? apiKeysStorage.getAPIKey(for: .openai)
        let geminiKey = try? apiKeysStorage.getAPIKey(for: .gemini)
        let grokKey = try? apiKeysStorage.getAPIKey(for: .xai)
        let perplexityKey = try? apiKeysStorage.getAPIKey(for: .perplexity)
        let deepseekKey = try? apiKeysStorage.getAPIKey(for: .deepseek)
        let zaiKey = try? apiKeysStorage.getAPIKey(for: .zai)
        let minimaxKey = try? apiKeysStorage.getAPIKey(for: .minimax)
        let mistralKey = try? apiKeysStorage.getAPIKey(for: .mistral)

        // Custom provider support (openai-compatible)
        // There is no dedicated AIProvider enum case for custom providers.
        // We treat custom provider selection as openai-compatible.
        var customBaseUrl: String? = nil
        var customApiKey: String? = nil
        var customModelCode: String? = nil
        if let providerId = settings.selectedCustomProviderId,
           let customProvider = settings.customProviders.first(where: { $0.id == providerId }) {
            customBaseUrl = customProvider.apiEndpoint
            customApiKey = try? apiKeysStorage.getCustomProviderAPIKey(providerId: providerId)

            if let modelId = settings.selectedCustomModelId,
               let customModel = customProvider.models.first(where: { $0.id == modelId }) {
                customModelCode = customModel.modelCode
            }
        }

        let (providerString, providerDisplayName) = provider.toProviderStringAndName(customBaseUrl: customBaseUrl)

        // Hard-disable fallback to Apple Intelligence here: Apple is handled by the primary path,
        // and titling should remain available even if Apple is temporarily unavailable.
        // If the selected provider is Apple, use OpenAI as a pragmatic fallback (if configured),
        // otherwise we will still attempt the selected provider and surface errors.
        let fallbackProviderStringIfAppleSelected: String? = {
            guard providerString == "appleFoundation" else { return nil }
            if let openai = openaiKey, !openai.isEmpty {
                return "openai"
            }
            if let anthropic = anthropicKey, !anthropic.isEmpty {
                return "anthropic"
            }
            if let gemini = geminiKey, !gemini.isEmpty {
                return "gemini"
            }
            return nil
        }()

        // If a custom provider is selected, prefer openai-compatible for the fallback.
        // This avoids coupling titling to the AIProvider enum.
        let hasCustomProviderSelection = settings.selectedCustomProviderId != nil && customBaseUrl != nil

        let effectiveProviderString: String = {
            if hasCustomProviderSelection { return "openai-compatible" }
            if let forced = fallbackProviderStringIfAppleSelected { return forced }
            return providerString
        }()

        let effectiveProviderDisplayName: String? = {
            if hasCustomProviderSelection { return "OpenAI-Compatible" }
            if let forced = fallbackProviderStringIfAppleSelected {
                switch forced {
                case "openai": return "OpenAI"
                case "anthropic": return "Anthropic"
                case "gemini": return "Gemini"
                default: return providerDisplayName
                }
            }
            return providerDisplayName
        }()

        let effectiveModel: String = {
            if hasCustomProviderSelection { return customModelCode ?? model }

            // If we had to switch providers away from Apple, also switch to that provider's
            // default model to avoid mismatched model IDs. Use registry first, fall back to enum.
            if let forced = fallbackProviderStringIfAppleSelected {
                let registry = UnifiedModelRegistry.shared
                switch forced {
                case "openai":
                    // Prefer a small/cheap default if present.
                    let models = registry.chatModels(for: .openai)
                    return models.first(where: { $0.id.contains("mini") })?.id
                        ?? models.first?.id
                        ?? AIProvider.openai.availableModels.first(where: { $0.id.contains("mini") })?.id
                        ?? "gpt-4o-mini"
                case "anthropic":
                    let models = registry.chatModels(for: .anthropic)
                    return models.last?.id
                        ?? models.first?.id
                        ?? AIProvider.anthropic.availableModels.last?.id
                        ?? "claude-haiku-4-5-20251001"
                case "gemini":
                    let models = registry.chatModels(for: .gemini)
                    return models.first?.id
                        ?? AIProvider.gemini.availableModels.first?.id
                        ?? "gemini-2.5-flash"
                default:
                    return model
                }
            }

            return model
        }()

        let config = OrchestrationConfig(
            provider: effectiveProviderString,
            model: effectiveModel,
            providerName: effectiveProviderDisplayName ?? "",
            contextWindowLimit: 4096,
            anthropicKey: anthropicKey,
            openaiKey: openaiKey,
            geminiKey: geminiKey,
            grokKey: grokKey,
            perplexityKey: perplexityKey,
            deepseekKey: deepseekKey,
            zaiKey: zaiKey,
            minimaxKey: minimaxKey,
            mistralKey: mistralKey,
            customBaseUrl: customBaseUrl,
            customApiKey: customApiKey,
            modelParams: nil  // Title generation uses hardcoded low temperature
        )

        // Minimal prompt. No salience/memory/tools/internal thread.
        let user = userMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !user.isEmpty, !assistant.isEmpty else {
            throw TitleGenerationError.insufficientContext
        }

        let prompt = """
        Return ONLY a concise 3–6 word title for this chat.
        No quotes. No punctuation.

        User: \(user)
        Assistant: \(assistant)
        """

        let response = try await MinimalTitleProviderClient.shared.generate(
            prompt: prompt,
            config: config,
            appleFailure: appleFailure
        )

        return response
    }

    private func sanitizeTitle(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split into words; keep 3–6 words if possible.
        var words = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        if words.count > 6 {
            words = Array(words.prefix(6))
        }

        let joined = words.joined(separator: " ")
        if joined.isEmpty {
            return trimmed
        }

        // Hard cap as an extra UI safety measure.
        let maxChars = 60
        if joined.count > maxChars {
            return String(joined.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return joined
    }
}

// MARK: - Minimal Provider Client

/// A minimal client that calls providers directly with a tiny prompt, without any Axon
/// salience/memory/tool/system prompt injection.
@MainActor
final class MinimalTitleProviderClient {
    static let shared = MinimalTitleProviderClient()

    private init() {}

    func generate(prompt: String, config: OrchestrationConfig, appleFailure: Error) async throws -> String {
        // Prevent accidental loops: if the selected provider is Apple and Apple failed,
        // bubble the original error.
        if config.provider == "appleFoundation" {
            throw appleFailure
        }

        // Call provider with a single user turn.
        // Note: using empty system prompt keeps overhead minimal.
        switch config.provider {
        case "anthropic":
            guard let apiKey = config.anthropicKey else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callAnthropic(apiKey: apiKey, model: config.model, prompt: prompt)

        case "openai":
            guard let apiKey = config.openaiKey else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callOpenAICompatible(apiKey: apiKey, baseUrl: "https://api.openai.com/v1", model: config.model, prompt: prompt)

        case "gemini":
            guard let apiKey = config.geminiKey else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callGemini(apiKey: apiKey, model: config.model, prompt: prompt)

        case "grok":
            guard let apiKey = config.grokKey else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callOpenAICompatible(apiKey: apiKey, baseUrl: "https://api.x.ai/v1", model: config.model, prompt: prompt)

        case "perplexity":
            guard let apiKey = config.perplexityKey else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callOpenAICompatible(apiKey: apiKey, baseUrl: "https://api.perplexity.ai", model: config.model, prompt: prompt)

        case "deepseek":
            guard let apiKey = config.deepseekKey else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callOpenAICompatible(apiKey: apiKey, baseUrl: "https://api.deepseek.com", model: config.model, prompt: prompt)

        case "zai":
            guard let apiKey = config.zaiKey else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callOpenAICompatible(apiKey: apiKey, baseUrl: "https://api.z.ai/api/paas/v4", model: config.model, prompt: prompt)

        case "minimax":
            guard let apiKey = config.minimaxKey else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callMiniMax(apiKey: apiKey, model: config.model, prompt: prompt)

        case "mistral":
            guard let apiKey = config.mistralKey else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callOpenAICompatible(apiKey: apiKey, baseUrl: "https://api.mistral.ai/v1", model: config.model, prompt: prompt)

        case "openai-compatible":
            guard let apiKey = config.customApiKey, let baseUrl = config.customBaseUrl else { throw APIError.unauthorized }
            return try await MinimalProviderHTTPClient.callOpenAICompatible(apiKey: apiKey, baseUrl: baseUrl, model: config.model, prompt: prompt)

        case "localMLX", "appleFoundation":
            // Not supported here (Apple path handled earlier; MLX would add more code).
            throw APIError.networkError("Provider \(config.provider) not supported for title fallback")

        default:
            throw APIError.networkError("Provider \(config.provider) not supported for title fallback")
        }
    }
}

/// Minimal HTTP client for title generation.
/// Kept intentionally small + deterministic.
private enum MinimalProviderHTTPClient {
    static func callAnthropic(apiKey: String, model: String, prompt: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 64,
            "messages": [
                ["role": "user", "content": [["type": "text", "text": prompt]]]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct AnthropicResponse: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    static func callOpenAICompatible(apiKey: String, baseUrl: String, model: String, prompt: String) async throws -> String {
        let url = URL(string: "\(baseUrl)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 64,
            "temperature": 0.2
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    static func callGemini(apiKey: String, model: String, prompt: String) async throws -> String {
        let modelId = model.starts(with: "models/") ? model : "models/\(model)"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(modelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": prompt]]]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return decoded.candidates?.first?.content.parts.first?.text ?? ""
    }

    static func callMiniMax(apiKey: String, model: String, prompt: String) async throws -> String {
        let url = URL(string: "https://api.minimax.io/v1/text/chatcompletion_v2")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["sender_type": "USER", "sender_name": "User", "text": prompt]
            ],
            "temperature": 0.2
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct MiniMaxResponse: Decodable {
            struct Choices: Decodable {
                struct Message: Decodable { let text: String }
                let messages: [Message]
            }
            let choices: Choices?
            let reply: String?
        }

        let decoded = try JSONDecoder().decode(MiniMaxResponse.self, from: data)
        return decoded.reply ?? decoded.choices?.messages.first?.text ?? ""
    }
}

// MARK: - AIProvider Helpers

private extension AIProvider {
    /// Map selected provider to provider string used in OrchestrationConfig.
    func toProviderStringAndName(customBaseUrl: String?) -> (provider: String, name: String?) {
        switch self {
        case .anthropic: return ("anthropic", self.displayName)
        case .openai: return ("openai", self.displayName)
        case .gemini: return ("gemini", self.displayName)
        case .xai: return ("grok", self.displayName) // internal routing uses "grok"
        case .perplexity: return ("perplexity", self.displayName)
        case .deepseek: return ("deepseek", self.displayName)
        case .zai: return ("zai", self.displayName)
        case .minimax: return ("minimax", self.displayName)
        case .mistral: return ("mistral", self.displayName)
        case .appleFoundation: return ("appleFoundation", self.displayName)
        case .localMLX: return ("localMLX", self.displayName)
        }
    }
}
