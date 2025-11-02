//
//  ConversationService.swift
//  Axon
//
//  Service for managing conversations and messages
//

import Foundation
import Combine

@MainActor
class ConversationService: ObservableObject {
    static let shared = ConversationService()

    private let apiClient = APIClient.shared

    // Default project ID - can be made configurable later
    private let defaultProjectId = "default"

    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    // MARK: - Helper: Get Provider and Model with Overrides

    private func getProviderAndModel(for conversationId: String, settings: AppSettings) -> (provider: String, modelName: String, providerName: String) {
        // Check for conversation overrides
        let overridesKey = "conversation_overrides_\(conversationId)"
        if let data = UserDefaults.standard.data(forKey: overridesKey),
           let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {

            // Custom provider override
            if let customProviderId = overrides.customProviderId,
               let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }),
               let customModelId = overrides.customModelId,
               let customModel = customProvider.models.first(where: { $0.id == customModelId }) {
                // Prefer explicitly saved display names; fall back to friendlyName/providerName
                let modelDisplayName = overrides.modelDisplayName ?? customModel.friendlyName ?? customProvider.providerName
                let providerDisplay = overrides.providerDisplayName ?? customProvider.providerName
                return ("openai-compatible", modelDisplayName, providerDisplay)
            }

            // Built-in provider override
            if let builtInProvider = overrides.builtInProvider,
               let provider = AIProvider(rawValue: builtInProvider),
               let builtInModel = overrides.builtInModel,
               let model = provider.availableModels.first(where: { $0.id == builtInModel }) {
                let modelDisplayName = overrides.modelDisplayName ?? model.name
                let providerDisplay = overrides.providerDisplayName ?? provider.displayName
                return (provider.rawValue, modelDisplayName, providerDisplay)
            }
        }

        // Fallback to global settings (custom)
        if let customProviderId = settings.selectedCustomProviderId,
           let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }),
           let customModelId = settings.selectedCustomModelId,
           let customModel = customProvider.models.first(where: { $0.id == customModelId }) {
            let modelDisplayName = customModel.friendlyName ?? customProvider.providerName
            return ("openai-compatible", modelDisplayName, customProvider.providerName)
        }

        // Default: built-in provider
        let provider = settings.defaultProvider
        let model = provider.availableModels.first(where: { $0.id == settings.defaultModel }) ?? provider.availableModels.first
        return (provider.rawValue, model?.name ?? "Unknown", provider.displayName)
    }

    // MARK: - Conversations

    func listConversations(limit: Int = 50, offset: Int = 0) async throws {
        isLoading = true
        defer { isLoading = false }

        struct ListConversationsResponse: Decodable {
            let conversations: [Conversation]
            let pagination: PaginationMeta?
            let metadata: AnyCodable?
        }

        do {
            let response: ListConversationsResponse = try await apiClient.request(
                endpoint: "/apiListConversations?projectId=\(defaultProjectId)&limit=\(limit)&offset=\(offset)",
                method: .get
            )
            self.conversations = response.conversations
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func createConversation(title: String, firstMessage: String? = nil) async throws -> Conversation {
        isLoading = true
        defer { isLoading = false }

        struct CreateConversationRequest: Encodable {
            let title: String
            let projectId: String
            let initialMessage: String?
        }

        struct CreateConversationResponse: Decodable {
            let conversation: Conversation
            let message: String?
        }

        let request = CreateConversationRequest(
            title: title,
            projectId: defaultProjectId,
            initialMessage: firstMessage
        )

        do {
            // This endpoint returns { "conversation": {...}, "message": "..." }
            let response: CreateConversationResponse = try await apiClient.request(
                endpoint: "/apiCreateConversation",
                method: .post,
                body: request
            )
            self.conversations.insert(response.conversation, at: 0)
            self.currentConversation = response.conversation
            return response.conversation
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func getConversation(id: String) async throws -> Conversation {
        isLoading = true
        defer { isLoading = false }

        do {
            struct GetConversationResponse: Decodable {
                let conversation: Conversation
            }
            let response: GetConversationResponse = try await apiClient.request(
                endpoint: "/apiGetConversation/\(id)",
                method: .get
            )
            self.currentConversation = response.conversation
            return response.conversation
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func updateConversation(id: String, title: String) async throws -> Conversation {
        struct UpdateRequest: Encodable {
            let title: String
        }

        let request = UpdateRequest(title: title)

        do {
            struct UpdateConversationResponse: Decodable {
                let conversation: Conversation
                let message: String?
            }
            let response: UpdateConversationResponse = try await apiClient.request(
                endpoint: "/apiUpdateConversation/\(id)",
                method: .patch,
                body: request
            )

            let conversation = response.conversation

            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index] = conversation
            }

            if currentConversation?.id == id {
                currentConversation = conversation
            }

            return conversation
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func deleteConversation(id: String, hardDelete: Bool = true) async throws {
        do {
            struct DeleteConversationResponse: Decodable { let message: String; let hardDelete: Bool? }
            let _: DeleteConversationResponse = try await apiClient.request(
                endpoint: "/apiDeleteConversation/\(id)?hardDelete=\(hardDelete)",
                method: .delete
            )
            conversations.removeAll { $0.id == id }

            if currentConversation?.id == id {
                currentConversation = nil
                messages = []
            }
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Messages

    func getMessages(conversationId: String, limit: Int = 50) async throws -> [Message] {
        isLoading = true
        defer { isLoading = false }

        struct GetMessagesResponse: Decodable {
            let messages: [Message]
            let pagination: PaginationMeta?
        }

        do {
            let response: GetMessagesResponse = try await apiClient.request(
                endpoint: "/apiGetMessages?conversationId=\(conversationId)&limit=\(limit)",
                method: .get
            )
            self.messages = response.messages
            return response.messages
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func sendMessage(conversationId: String, content: String) async throws -> Message {
        struct OrchestrateRequest: Encodable {
            let conversationId: String
            let message: String
            let provider: String
            let model: String?
            let apiKeys: APIKeys
            let options: OrchestrateOptions
            let openaiCompatible: OpenAICompatible?
        }

        struct APIKeys: Encodable {
            let anthropic: String?
            let openai: String?
            let gemini: String?
        }

        struct OpenAICompatible: Encodable {
            let apiKey: String
            let baseUrl: String
        }

        struct OrchestrateOptions: Encodable {
            let createArtifacts: Bool
            let saveMemories: Bool
            let executeTools: Bool
        }

        struct OrchestrateResponse: Decodable {
            let userMessage: Message
            let assistantMessage: Message
            let artifacts: [AnyCodable]?
            let memories: [AnyCodable]?
            let tools: [AnyCodable]?
            let conversationUpdated: Bool?
            let metadata: AnyCodable?
        }

        // Get API keys from storage
        let apiKeysStorage = APIKeysStorage.shared
        let anthropicKey = try? apiKeysStorage.getAPIKey(for: .anthropic)
        let openaiKey = try? apiKeysStorage.getAPIKey(for: .openai)
        let geminiKey = try? apiKeysStorage.getAPIKey(for: .gemini)

        #if DEBUG
        print("[ConversationService] API Key Debug:")
        print("  Anthropic: \(anthropicKey != nil ? "✓ Retrieved (\(anthropicKey!.count) chars, starts: \(String(anthropicKey!.prefix(15)))...)" : "✗ Not found")")
        print("  OpenAI: \(openaiKey != nil ? "✓ Retrieved" : "✗ Not found")")
        print("  Gemini: \(geminiKey != nil ? "✓ Retrieved" : "✗ Not found")")
        #endif

        // Load provider/model from settings with conversation overrides
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        let (providerString, modelName, providerDisplayName) = getProviderAndModel(for: conversationId, settings: settings)

        // Handle custom provider API key, endpoint, and model code
        var openaiCompatibleConfig: OpenAICompatible? = nil
        var modelCode: String? = nil
        
        if providerString == "openai-compatible" {
            // Get custom provider ID from conversation overrides or global settings
            let overridesKey = "conversation_overrides_\(conversationId)"
            var customProviderId: UUID? = nil
            var customModelId: UUID? = nil
            
            // Check conversation overrides first
            if let data = UserDefaults.standard.data(forKey: overridesKey),
               let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {
                customProviderId = overrides.customProviderId
                customModelId = overrides.customModelId
            } else {
                // Fall back to global settings
                customProviderId = settings.selectedCustomProviderId
                customModelId = settings.selectedCustomModelId
            }
            
            // Get custom provider config and API key
            if let providerId = customProviderId,
               let customProvider = settings.customProviders.first(where: { $0.id == providerId }) {
                
                // Get the model code
                if let modelId = customModelId,
                   let customModel = customProvider.models.first(where: { $0.id == modelId }) {
                    modelCode = customModel.modelCode
                }
                
                // Retrieve API key from keychain
                if let apiKey = try? apiKeysStorage.getCustomProviderAPIKey(providerId: providerId), !apiKey.isEmpty {
                    openaiCompatibleConfig = OpenAICompatible(
                        apiKey: apiKey,
                        baseUrl: customProvider.apiEndpoint
                    )
                    
                    #if DEBUG
                    print("[ConversationService] Custom Provider Config:")
                    print("  Provider: \(customProvider.providerName)")
                    print("  Model Code: \(modelCode ?? "none")")
                    print("  Endpoint: \(customProvider.apiEndpoint)")
                    print("  API Key: ✓ Retrieved (\(apiKey.count) chars)")
                    #endif
                } else {
                    #if DEBUG
                    print("[ConversationService] WARNING: Custom provider '\(customProvider.providerName)' selected but no API key found!")
                    #endif
                }
            }
        }

        let request = OrchestrateRequest(
            conversationId: conversationId,
            message: content,
            provider: providerString,
            model: modelCode,
            apiKeys: APIKeys(
                anthropic: anthropicKey,
                openai: openaiKey,
                gemini: geminiKey
            ),
            options: OrchestrateOptions(
                createArtifacts: true,
                saveMemories: true,
                executeTools: false
            ),
            openaiCompatible: openaiCompatibleConfig
        )

        #if DEBUG
        print("[ConversationService] Request Body:")
        print("  Provider: \(providerString)")
        print("  ConversationId: \(conversationId)")
        print("  Message length: \(content.count) chars")
        print("  API Keys in request body:")
        print("    anthropic: \(request.apiKeys.anthropic != nil ? "✓ Included" : "✗ nil")")
        print("    openai: \(request.apiKeys.openai != nil ? "✓ Included" : "✗ nil")")
        print("    gemini: \(request.apiKeys.gemini != nil ? "✓ Included" : "✗ nil")")
        #endif

        // Prepare provider API key headers for orchestrator (backend may expect headers)
        var providerHeaders: [String: String] = [:]
        if let anthropicKey, !anthropicKey.isEmpty {
            providerHeaders["X-Anthropic-Api-Key"] = anthropicKey
        }
        if let openaiKey, !openaiKey.isEmpty {
            providerHeaders["X-OpenAI-Api-Key"] = openaiKey
        }
        if let geminiKey, !geminiKey.isEmpty {
            providerHeaders["X-Gemini-Api-Key"] = geminiKey
        }

        do {
            // Add user message optimistically
            let userMessage = Message(
                conversationId: conversationId,
                role: .user,
                content: content
            )
            messages.append(userMessage)

            // Use the orchestrator - handles everything in one call
            let response: OrchestrateResponse = try await apiClient.request(
                endpoint: "/apiOrchestrate",
                method: .post,
                body: request,
                headers: providerHeaders
            )

            // Replace optimistic message with actual user message
            if let index = messages.firstIndex(where: { $0.id == userMessage.id }) {
                messages[index] = response.userMessage
            }

            // Add AI assistant response with model metadata
            var assistantMessage = response.assistantMessage
            // If backend didn't provide model info, add it from our settings
            if assistantMessage.modelName == nil || assistantMessage.providerName == nil {
                assistantMessage = Message(
                    id: assistantMessage.id,
                    conversationId: assistantMessage.conversationId,
                    role: assistantMessage.role,
                    content: assistantMessage.content,
                    timestamp: assistantMessage.timestamp,
                    tokens: assistantMessage.tokens,
                    artifacts: assistantMessage.artifacts,
                    toolCalls: assistantMessage.toolCalls,
                    isStreaming: assistantMessage.isStreaming,
                    modelName: modelName,
                    providerName: providerDisplayName
                )
            }
            messages.append(assistantMessage)

            return assistantMessage
        } catch {
            // Remove optimistic message on error
            messages.removeAll { $0.content == content && $0.role == .user }
            self.error = error.localizedDescription
            throw error
        }
    }

    func regenerateAssistantMessage(conversationId: String, messageId: String) async throws -> Message {
        struct RegenerateRequest: Encodable {
            let provider: String
            let options: Options
            let anthropic: String?
            let openai: String?
            let gemini: String?

            struct Options: Encodable {
                let model: String?
                let temperature: Double?
                let maxTokens: Int?
                let includeMemories: Bool
                let replaceLastMessage: Bool
                let projectId: String?
            }
        }

        struct RegenerateResponse: Decodable {
            let userMessage: Message?
            let assistantMessage: Message
            let conversationUpdated: Bool?
            let metadata: AnyCodable?
            let replacedMessageId: String?
        }

        // Load provider from settings (fallback to anthropic)
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        let providerString = settings.defaultProvider.rawValue

        // Try to include user-provided provider API keys (optional)
        let apiKeysStorage = APIKeysStorage.shared
        let anthropicKey = try? apiKeysStorage.getAPIKey(for: .anthropic)
        let openaiKey = try? apiKeysStorage.getAPIKey(for: .openai)
        let geminiKey = try? apiKeysStorage.getAPIKey(for: .gemini)

        // Build request body per MD contract. We choose to replace the last assistant message by default.
        let request = RegenerateRequest(
            provider: providerString,
            options: .init(
                model: nil,
                temperature: nil,
                maxTokens: nil,
                includeMemories: true,
                replaceLastMessage: true,
                projectId: defaultProjectId
            ),
            anthropic: anthropicKey,
            openai: openaiKey,
            gemini: geminiKey
        )

        do {
            // MD endpoint shape: /apiRegenerateMessage/<conversationId>/regenerate
            let response: RegenerateResponse = try await apiClient.request(
                endpoint: "/apiRegenerateMessage/\(conversationId)/regenerate",
                method: .post,
                body: request
            )

            let newAssistant = response.assistantMessage

            if let replacedId = response.replacedMessageId {
                // Replace the old assistant message with the regenerated one
                if let index = messages.firstIndex(where: { $0.id == replacedId }) {
                    messages[index] = newAssistant
                } else {
                    // If we can't find it locally, append to ensure UI shows the new response
                    messages.append(newAssistant)
                }
            } else {
                // Backend may have appended a new message (replaceLastMessage == false)
                // In that case, just append the regenerated assistant message
                messages.append(newAssistant)
            }

            return newAssistant
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func streamMessage(conversationId: String, content: String, onChunk: @escaping (String) -> Void) async throws {
        // TODO: Implement streaming support
        // For now, fall back to regular send
        _ = try await sendMessage(conversationId: conversationId, content: content)
    }

    // MARK: - Helpers

    func clearCurrentConversation() {
        currentConversation = nil
        messages = []
    }
}
