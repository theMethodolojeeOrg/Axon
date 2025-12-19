//
//  AskAxonIntent.swift
//  Axon
//
//  AppIntent to ask Axon a quick question - "Ask Axon [question]"
//

import AppIntents
import Foundation

/// Intent to ask Axon a question and get an AI response
/// Siri: "Ask Axon [question]"
struct AskAxonIntent: AppIntent {

    // MARK: - Metadata

    static var title: LocalizedStringResource = "Ask Axon"

    static var description = IntentDescription(
        "Ask Axon a question and get an AI response",
        categoryName: "AI"
    )

    /// Runs in background - returns answer without opening app
    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(
        title: "Question",
        description: "The question to ask Axon",
        inputOptions: .init(
            capitalizationType: .sentences,
            multiline: true,
            autocorrect: true
        )
    )
    var question: String

    @Parameter(
        title: "Use Memory",
        description: "Include relevant memories for context",
        default: true
    )
    var useMemory: Bool

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Axon \(\.$question)") {
            \.$useMemory
        }
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Build orchestrator config from settings
        let config = try await buildOrchestrationConfig()

        // Build context with optional memory
        var systemPrompt = """
        You are Axon, a helpful AI assistant. Answer the user's question concisely and helpfully.
        Keep your response brief but informative - this is a quick query from Siri/Shortcuts.
        """

        if useMemory {
            // Fetch relevant memories
            let memoryService = MemoryService.shared
            let relevantMemories = try await memoryService.searchMemories(
                query: question,
                types: nil,
                limit: 3,
                minConfidence: 0.5
            )

            if !relevantMemories.isEmpty {
                let memoryContext = relevantMemories
                    .map { "- \($0.content)" }
                    .joined(separator: "\n")

                systemPrompt += """


                Relevant context from memory:
                \(memoryContext)
                """
            }
        }

        // Create a minimal orchestrator call
        let orchestrator = OnDeviceConversationOrchestrator()
        let tempConversationId = "siri-query-\(UUID().uuidString)"

        let userMessage = Message(
            conversationId: tempConversationId,
            role: .user,
            content: question
        )

        let systemMessage = Message(
            conversationId: tempConversationId,
            role: .system,
            content: systemPrompt
        )

        // Call the orchestrator with minimal tools (no heavy tools for quick queries)
        let (response, _) = try await orchestrator.sendMessage(
            conversationId: tempConversationId,
            content: question,
            attachments: [],
            enabledTools: [],  // No tools for quick Siri queries
            messages: [systemMessage, userMessage],
            config: config
        )

        // Return the response content
        return .result(value: response.content)
    }

    // MARK: - Build Config

    private func buildOrchestrationConfig() async throws -> OrchestrationConfig {
        guard let settings = SettingsStorage.shared.loadSettings() else {
            throw AskAxonError.noConfiguredProvider
        }
        let apiKeys = APIKeysStorage.shared

        var providerString = settings.defaultProvider.rawValue
        var modelId = settings.defaultModel
        var providerDisplayName = settings.defaultProvider.displayName
        var customBaseUrl: String? = nil
        var customApiKey: String? = nil

        // Handle custom providers
        if let customProviderId = settings.selectedCustomProviderId,
           let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }),
           let customModelId = settings.selectedCustomModelId,
           let customModel = customProvider.models.first(where: { $0.id == customModelId }) {
            providerString = "openai-compatible"
            modelId = customModel.modelCode
            providerDisplayName = customProvider.providerName
            customBaseUrl = customProvider.apiEndpoint
            if let key = try? apiKeys.getCustomProviderAPIKey(providerId: customProviderId) {
                customApiKey = key
            }
        }

        // Normalize provider name
        if providerString == "xai" {
            providerString = "grok"
        }

        let contextWindowLimit = AIProvider.contextWindowForModel(modelId, settings: settings)

        return OrchestrationConfig(
            provider: providerString,
            model: modelId,
            providerName: providerDisplayName,
            contextWindowLimit: contextWindowLimit,
            anthropicKey: try? apiKeys.getAPIKey(for: .anthropic),
            openaiKey: try? apiKeys.getAPIKey(for: .openai),
            geminiKey: try? apiKeys.getAPIKey(for: .gemini),
            grokKey: try? apiKeys.getAPIKey(for: .xai),
            perplexityKey: try? apiKeys.getAPIKey(for: .perplexity),
            deepseekKey: try? apiKeys.getAPIKey(for: .deepseek),
            zaiKey: try? apiKeys.getAPIKey(for: .zai),
            minimaxKey: try? apiKeys.getAPIKey(for: .minimax),
            mistralKey: try? apiKeys.getAPIKey(for: .mistral),
            customBaseUrl: customBaseUrl,
            customApiKey: customApiKey
        )
    }
}

// MARK: - Errors

enum AskAxonError: LocalizedError {
    case noConfiguredProvider
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noConfiguredProvider:
            return "No AI provider configured. Please set up Axon with an API key first."
        case .apiError(let message):
            return "AI request failed: \(message)"
        }
    }
}
