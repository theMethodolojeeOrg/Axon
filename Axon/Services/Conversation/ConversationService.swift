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
            let firstMessage: String?
        }

        struct CreateConversationResponse: Decodable {
            let conversation: Conversation
            let message: String?
        }

        let request = CreateConversationRequest(
            title: title,
            projectId: defaultProjectId,
            firstMessage: firstMessage
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
            let conversation: Conversation = try await apiClient.requestWrapped(
                endpoint: "/apiGetConversation?conversationId=\(id)",
                method: .get
            )
            self.currentConversation = conversation
            return conversation
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func updateConversation(id: String, title: String) async throws -> Conversation {
        struct UpdateRequest: Encodable {
            let conversationId: String
            let title: String
        }

        let request = UpdateRequest(conversationId: id, title: title)

        do {
            let conversation: Conversation = try await apiClient.requestWrapped(
                endpoint: "/apiUpdateConversation",
                method: .post,
                body: request
            )

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

    func deleteConversation(id: String) async throws {
        struct DeleteRequest: Encodable {
            let conversationId: String
        }

        let request = DeleteRequest(conversationId: id)

        do {
            struct EmptyResponse: Decodable {}
            let _: EmptyResponse = try await apiClient.requestWrapped(
                endpoint: "/apiDeleteConversation",
                method: .post,
                body: request
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

        do {
            let (messages, _) = try await apiClient.requestWrappedList(
                endpoint: "/apiGetMessages?conversationId=\(conversationId)&limit=\(limit)",
                method: .get
            ) as ([Message], PaginationMeta?)
            self.messages = messages
            return messages
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
            let apiKeys: APIKeys
            let options: OrchestrateOptions
        }

        struct APIKeys: Encodable {
            let anthropic: String?
            let openai: String?
            let gemini: String?
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

        // Load provider from settings (fallback to anthropic)
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        let providerString = settings.defaultProvider.rawValue

        let request = OrchestrateRequest(
            conversationId: conversationId,
            message: content,
            provider: providerString,
            apiKeys: APIKeys(
                anthropic: anthropicKey,
                openai: openaiKey,
                gemini: geminiKey
            ),
            options: OrchestrateOptions(
                createArtifacts: true,
                saveMemories: true,
                executeTools: false
            )
        )

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

            // Add AI assistant response
            messages.append(response.assistantMessage)

            return response.assistantMessage
        } catch {
            // Remove optimistic message on error
            messages.removeAll { $0.content == content && $0.role == .user }
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

