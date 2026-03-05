//
//  SendMessageToConversationIntent.swift
//  Axon
//
//  AppIntent to send a message to a specific Axon conversation.
//  Used by the widget's voice input feature - messages are persisted to history.
//

import AppIntents
import Foundation

/// Intent to send a message to a specific conversation and persist to history
/// Siri: "Tell Axon [message]" or triggered from widget
struct SendMessageToConversationIntent: AppIntent {

    // MARK: - Metadata

    static var title: LocalizedStringResource = "Send to Axon"

    static var description = IntentDescription(
        "Send a message to an Axon conversation and get an AI response",
        categoryName: "AI"
    )

    /// Runs in background - returns answer without opening app
    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(
        title: "Message",
        description: "The message to send to Axon",
        inputOptions: .init(
            capitalizationType: .sentences,
            multiline: true,
            autocorrect: true
        )
    )
    var message: String

    @Parameter(
        title: "Conversation",
        description: "Which conversation to send to (uses most recent if not specified)"
    )
    var conversation: ConversationAppEntity?

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) to \(\.$conversation)")
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // 1. Resolve or create conversation
        let (conversationId, conversationTitle) = try await resolveConversation()

        // 2. Load existing messages for context
        let existingMessages = try await loadMessages(for: conversationId)

        // 3. Build orchestrator config
        let config = try await buildOrchestrationConfig()

        // 4. Create user message
        let userMessage = Message(
            conversationId: conversationId,
            role: .user,
            content: message
        )

        // 5. Build system prompt
        let systemMessage = Message(
            conversationId: conversationId,
            role: .system,
            content: """
            You are Axon, a helpful AI assistant. This is a message from the user via Siri voice input.
            Keep your response conversational and moderately concise - this will be spoken aloud.
            """
        )

        // 6. Prepare message history for orchestrator
        var contextMessages = [systemMessage]
        contextMessages.append(contentsOf: existingMessages.suffix(10))  // Last 10 messages for context
        contextMessages.append(userMessage)

        // 7. Send to orchestrator
        let orchestrator = OnDeviceConversationOrchestrator()
        let (response, memories) = try await orchestrator.sendMessage(
            conversationId: conversationId,
            content: message,
            attachments: [],
            enabledTools: [],  // No tools for Siri queries
            messages: contextMessages,
            config: config
        )

        // 8. Persist both messages to CoreData
        try await persistMessages(
            userMessage: userMessage,
            assistantMessage: response,
            conversationId: conversationId
        )

        // 9. Update widget data
        await updateWidgetData(conversationId: conversationId)

        // 10. Save any generated memories
        if let memories = memories, !memories.isEmpty {
            try? await MemorySyncManager.shared.saveMemoriesToCoreData(memories)
        }

        // 11. Return response to Siri
        return .result(value: response.content)
    }

    // MARK: - Helpers

    /// Resolve the target conversation, creating a new one if needed
    @MainActor
    private func resolveConversation() async throws -> (id: String, title: String) {
        // If user specified a conversation, use it
        if let conv = conversation {
            return (conv.id, conv.title)
        }

        // Try to get most recent conversation from widget data
        if let recentId = getMostRecentConversationId() {
            let store = LocalConversationStore.shared
            if let conv = try? store.loadConversation(id: recentId) {
                return (conv.id, conv.title)
            }
        }

        // Create a new conversation
        let store = LocalConversationStore.shared
        let newConv = try store.createLocalConversation(
            title: "Siri Chat \(formattedDate())"
        )
        return (newConv.id, newConv.title)
    }

    /// Load existing messages from a conversation
    @MainActor
    private func loadMessages(for conversationId: String) async throws -> [Message] {
        let store = LocalConversationStore.shared
        return try store.loadMessages(for: conversationId, limit: 20)
    }

    /// Persist messages to CoreData
    @MainActor
    private func persistMessages(
        userMessage: Message,
        assistantMessage: Message,
        conversationId: String
    ) async throws {
        let store = LocalConversationStore.shared

        // Save user message
        try store.saveLocalMessage(userMessage, conversationId: conversationId)

        // Save assistant message
        try store.saveLocalMessage(assistantMessage, conversationId: conversationId)
    }

    /// Update widget data after message exchange
    @MainActor
    private func updateWidgetData(conversationId: String) async {
        let store = LocalConversationStore.shared

        // Load the updated conversation and messages
        guard let conv = try? store.loadConversation(id: conversationId) else { return }
        let messages = (try? store.loadMessages(for: conversationId, limit: 10)) ?? []

        // Update widget data service
        await WidgetDataService.shared.updateConversationAsync(conv, messages: messages)
    }

    /// Get most recent conversation ID from widget data
    private func getMostRecentConversationId() -> String? {
        guard let store = WidgetDataService.shared.loadDataStore() else { return nil }
        return store.recentConversations.first?.conversationId
    }

    /// Build orchestration config from settings
    private func buildOrchestrationConfig() async throws -> OrchestrationConfig {
        guard let settings = SettingsStorage.shared.loadSettings() else {
            throw SendMessageError.noConfiguredProvider
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
            customApiKey: customApiKey,
            modelParams: settings.modelGenerationSettings
        )
    }

    /// Format current date for conversation title
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: Date())
    }
}

// MARK: - Errors

enum SendMessageError: LocalizedError {
    case noConfiguredProvider
    case conversationNotFound
    case failedToPersist

    var errorDescription: String? {
        switch self {
        case .noConfiguredProvider:
            return "No AI provider configured. Please set up Axon with an API key first."
        case .conversationNotFound:
            return "Could not find the specified conversation."
        case .failedToPersist:
            return "Failed to save the message to conversation history."
        }
    }
}
