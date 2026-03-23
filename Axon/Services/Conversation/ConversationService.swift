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
    private let syncManager = ConversationSyncManager.shared
    private let localStore = LocalConversationStore.shared

    // Default project ID - can be made configurable later
    private let defaultProjectId = "default"

    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isSyncing = false

    // Offline mode support
    @Published var isOfflineMode = false
    @Published var pendingOperationsCount = 0

    // Track recently deleted conversations to prevent resurrection from sync
    private var recentlyDeletedIds: Set<String> = []
    private var deletedIdsTimestamps: [String: Date] = [:]
    private let deletionRetentionPeriod: TimeInterval = 300 // 5 minutes to prevent resurrection

    // Track ephemeral conversations (created but not yet persisted)
    // These are conversations shown in UI but not saved to Core Data until first message is sent
    private var ephemeralConversationIds: Set<String> = []

    private init() {
        // Load conversations from local Core Data immediately (instant UI)
        loadLocalConversations()

        // Update pending operations count
        pendingOperationsCount = localStore.pendingOperationCount
    }

    // MARK: - Local-First Data Access

    /// Load conversations from Core Data (instant, no network)
    private func loadLocalConversations() {
        // Clean up old deletion records (older than retention period)
        cleanupOldDeletionRecords()

        var loaded = syncManager.loadLocalConversations()

        // CRITICAL: Filter out recently deleted conversations to prevent resurrection
        if !recentlyDeletedIds.isEmpty {
            let beforeCount = loaded.count
            loaded = loaded.filter { !recentlyDeletedIds.contains($0.id) }
            if beforeCount != loaded.count {
                print("[ConversationService] Filtered out \(beforeCount - loaded.count) recently deleted conversations")
            }
        }

        print("[ConversationService] Loaded \(loaded.count) conversations from Core Data")
        conversations = loaded
    }

    /// Clean up deletion records older than retention period
    private func cleanupOldDeletionRecords() {
        let now = Date()
        let expiredIds = deletedIdsTimestamps.filter { now.timeIntervalSince($0.value) > deletionRetentionPeriod }.keys
        for id in expiredIds {
            recentlyDeletedIds.remove(id)
            deletedIdsTimestamps.removeValue(forKey: id)
        }
        if !expiredIds.isEmpty {
            print("[ConversationService] Cleaned up \(expiredIds.count) expired deletion records")
        }
    }

    /// Mark a conversation as recently deleted (prevents resurrection during sync)
    private func markAsRecentlyDeleted(_ id: String) {
        recentlyDeletedIds.insert(id)
        deletedIdsTimestamps[id] = Date()
        print("[ConversationService] Marked conversation \(id) as recently deleted")
    }

    /// Sync conversations with server in background
    func syncConversationsInBackground() {
        Task { @MainActor in
            isSyncing = true
            defer { isSyncing = false }

            do {
                // First, process any pending local operations
                await localStore.processPendingOperations()
                pendingOperationsCount = localStore.pendingOperationCount

                // Then sync with server
                try await syncManager.syncConversations()
                // Reload from Core Data after successful sync
                loadLocalConversations()

                isOfflineMode = false
            } catch {
                self.error = error.localizedDescription
                print("[ConversationService] Sync failed: \(error)")
                isOfflineMode = true
            }
        }
    }

    /// Process pending offline operations
    func syncPendingOperations() async {
        await localStore.processPendingOperations()
        
        // Update the count - this will be 0 if operations were cleared (no backend configured)
        pendingOperationsCount = localStore.pendingOperationCount
        
        print("[ConversationService] Pending operations after sync: \(pendingOperationsCount)")

        // Reload conversations to reflect any ID changes from synced local conversations
        loadLocalConversations()
    }

    // MARK: - Helper: Get Provider and Model with Overrides

    /// Returns (providerString, modelId, modelDisplayName, providerDisplayName)
    /// - modelId: The API model identifier to send to the provider (e.g., "claude-haiku-4-5-20251001")
    /// - modelDisplayName: The human-readable name for UI display (e.g., "Claude Haiku 4.5")
    private func getProviderAndModel(for conversationId: String, settings: AppSettings) -> (provider: String, modelId: String, modelDisplayName: String, providerName: String) {
        let resolved = ConversationModelResolver.resolve(conversationId: conversationId, settings: settings)
        return (resolved.normalizedProvider, resolved.modelId, resolved.modelDisplayName, resolved.providerName)
    }

    // MARK: - Conversations

    /// List conversations - loads from Core Data first, then syncs in background
    func listConversations(limit: Int = 50, offset: Int = 0) async throws {
        // Load from Core Data immediately (instant)
        loadLocalConversations()

        // Trigger background sync (non-blocking)
        syncConversationsInBackground()
    }

    func createConversation(title: String, firstMessage: String? = nil) async throws -> Conversation {
        isLoading = true
        defer { isLoading = false }

        // If there is no backend configured, always create locally.
        // This is required for “device-direct CloudLLM” mode.
        guard apiClient.isBackendConfigured else {
            return try createConversationOffline(title: title)
        }

        // Try online creation first, fall back to offline if it fails
        do {
            return try await createConversationOnline(title: title, firstMessage: firstMessage)
        } catch {
            print("[ConversationService] Online creation failed, trying offline: \(error)")

            // Fall back to local-only creation
            return try createConversationOffline(title: title)
        }
    }

    /// Create conversation via API (online mode)
    private func createConversationOnline(title: String, firstMessage: String? = nil) async throws -> Conversation {
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

        // This endpoint returns { "conversation": {...}, "message": "..." }
        let response: CreateConversationResponse = try await apiClient.request(
            endpoint: "/apiCreateConversation",
            method: .post,
            body: request
        )

        // Save new conversation to Core Data immediately so it appears in sidebar
        try await syncManager.saveConversationsToCoreData([response.conversation])

        // Add to in-memory array and set as current
        self.conversations.insert(response.conversation, at: 0)
        self.currentConversation = response.conversation
        return response.conversation
    }

    /// Create conversation locally (offline mode)
    func createConversationOffline(title: String) throws -> Conversation {
        let conversation = try localStore.createLocalConversation(title: title, projectId: defaultProjectId)

        // Add to in-memory array and set as current
        self.conversations.insert(conversation, at: 0)
        self.currentConversation = conversation
        self.pendingOperationsCount = localStore.pendingOperationCount

        print("[ConversationService] Created offline conversation: \(conversation.id)")
        return conversation
    }

    // MARK: - Ephemeral Conversations

    /// Create an ephemeral conversation (in-memory only, not persisted until first message)
    /// This prevents empty "New Chat" conversations from cluttering the sidebar
    func createEphemeralConversation(title: String) -> Conversation {
        let localId = "ephemeral_\(UUID().uuidString)"
        let now = Date()

        let conversation = Conversation(
            id: localId,
            userId: nil,
            title: title,
            projectId: defaultProjectId,
            createdAt: now,
            updatedAt: now,
            messageCount: 0,
            lastMessageAt: nil,
            archived: false
        )

        // Track as ephemeral (not persisted)
        ephemeralConversationIds.insert(localId)

        // Add to in-memory array and set as current
        self.conversations.insert(conversation, at: 0)
        self.currentConversation = conversation

        print("[ConversationService] Created ephemeral conversation: \(localId)")
        return conversation
    }

    /// Check if a conversation is ephemeral (not yet persisted)
    func isEphemeral(_ conversationId: String) -> Bool {
        return ephemeralConversationIds.contains(conversationId)
    }

    /// Persist an ephemeral conversation to Core Data
    /// Called when the first message is sent to the conversation
    func persistEphemeralConversation(_ conversationId: String, title: String? = nil) throws -> Conversation {
        guard ephemeralConversationIds.contains(conversationId) else {
            // Not ephemeral, return existing conversation
            if let existing = conversations.first(where: { $0.id == conversationId }) {
                return existing
            }
            throw ConversationError.notFound
        }

        // Remove from ephemeral tracking
        ephemeralConversationIds.remove(conversationId)

        // Find the ephemeral conversation in memory
        guard let ephemeralIndex = conversations.firstIndex(where: { $0.id == conversationId }) else {
            throw ConversationError.notFound
        }
        let ephemeral = conversations[ephemeralIndex]

        // Create a real persisted conversation
        let persistedConversation = try localStore.createLocalConversation(
            title: title ?? ephemeral.title,
            projectId: defaultProjectId
        )

        // Replace ephemeral with persisted in the array
        conversations[ephemeralIndex] = persistedConversation

        // Update current conversation reference if needed
        if currentConversation?.id == conversationId {
            currentConversation = persistedConversation
        }

        self.pendingOperationsCount = localStore.pendingOperationCount

        print("[ConversationService] Persisted ephemeral conversation: \(conversationId) -> \(persistedConversation.id)")
        return persistedConversation
    }

    /// Discard an ephemeral conversation without persisting
    /// Called when user navigates away from a new chat without sending a message
    func discardEphemeralConversation(_ conversationId: String) {
        guard ephemeralConversationIds.contains(conversationId) else {
            return // Not ephemeral, nothing to discard
        }

        // Remove from ephemeral tracking
        ephemeralConversationIds.remove(conversationId)

        // Remove from in-memory array
        conversations.removeAll { $0.id == conversationId }

        // Clear current if it was this conversation
        if currentConversation?.id == conversationId {
            currentConversation = nil
        }

        print("[ConversationService] Discarded ephemeral conversation: \(conversationId)")
    }

    /// Discard all ephemeral conversations
    /// Called on app cleanup or when explicitly clearing empty chats
    func discardAllEphemeralConversations() {
        let ephemeralIds = ephemeralConversationIds
        for id in ephemeralIds {
            discardEphemeralConversation(id)
        }
    }

    func getConversation(id: String) async throws -> Conversation {
        isLoading = true
        defer { isLoading = false }

        // Try local first
        if let localConversation = conversations.first(where: { $0.id == id }) {
            self.currentConversation = localConversation
            return localConversation
        }

        // If backend not configured, we can only use local data
        guard apiClient.isBackendConfigured else {
            throw ConversationError.notFound
        }

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
        // Find existing conversation
        guard let existingIndex = conversations.firstIndex(where: { $0.id == id }) else {
            throw ConversationError.notFound
        }
        let existing = conversations[existingIndex]

        if apiClient.isBackendConfigured {
            // Cloud mode: Update via API
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
                conversations[existingIndex] = conversation

                if currentConversation?.id == id {
                    currentConversation = conversation
                }

                return conversation
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        } else {
            // Local-first mode: Update locally
            try localStore.updateLocalConversation(id: id, title: title)

            // Create updated conversation model
            let updatedConversation = Conversation(
                id: existing.id,
                userId: existing.userId,
                title: title,
                projectId: existing.projectId,
                createdAt: existing.createdAt,
                updatedAt: Date(),
                messageCount: existing.messageCount,
                lastMessageAt: existing.lastMessageAt,
                archived: existing.archived,
                summary: existing.summary,
                lastMessage: existing.lastMessage,
                tags: existing.tags,
                isPinned: existing.isPinned
            )

            conversations[existingIndex] = updatedConversation

            if currentConversation?.id == id {
                currentConversation = updatedConversation
            }

            print("[ConversationService] Updated local conversation: \(id)")
            return updatedConversation
        }
    }

    func deleteConversation(id: String, hardDelete: Bool = true) async throws {
        // CRITICAL: Mark as recently deleted FIRST to prevent resurrection during sync
        markAsRecentlyDeleted(id)

        // Optimistic update - remove from UI immediately
        conversations.removeAll { $0.id == id }
        if currentConversation?.id == id {
            currentConversation = nil
            messages = []
        }

        // For local-only conversations OR when no backend configured, hard delete immediately
        if id.hasPrefix("local_") || !apiClient.isBackendConfigured {
            try localStore.deleteLocalConversation(id: id)
            // For synced conversations without backend, also hard delete
            if !id.hasPrefix("local_") && !apiClient.isBackendConfigured {
                try localStore.hardDeleteLocalConversation(id: id)
            }
            pendingOperationsCount = localStore.pendingOperationCount
            print("[ConversationService] Deleted conversation locally: \(id)")
            recentlyDeletedIds.remove(id)
            deletedIdsTimestamps.removeValue(forKey: id)
            return
        }

        // Soft-delete from Core Data first (sets syncStatus = "deleted")
        // This prevents resurrection during sync until server confirms deletion
        try localStore.deleteLocalConversation(id: id)
        pendingOperationsCount = localStore.pendingOperationCount
        print("[ConversationService] Soft-deleted conversation locally: \(id)")

        // Try API deletion
        do {
            struct DeleteConversationResponse: Decodable { let message: String; let hardDelete: Bool? }
            let _: DeleteConversationResponse = try await apiClient.request(
                endpoint: "/apiDeleteConversation/\(id)?hardDelete=\(hardDelete)",
                method: .delete
            )

            print("[ConversationService] ✅ Server confirmed deletion of conversation \(id)")

            // Server confirmed - hard delete the tombstone
            try localStore.hardDeleteLocalConversation(id: id)

            // Can safely remove from recentlyDeletedIds now
            recentlyDeletedIds.remove(id)
            deletedIdsTimestamps.removeValue(forKey: id)
        } catch {
            // Server delete failed, but soft-delete tombstone remains
            // The pending operation queue will retry the API deletion
            // Tombstone prevents resurrection on next sync
            print("[ConversationService] ⚠️ Server delete failed for \(id), tombstone preserved: \(error.localizedDescription)")
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Messages

    func getMessages(conversationId: String, limit: Int = 50) async throws -> [Message] {
        print("[ConversationService] 📥 getMessages called")
        print("[ConversationService] Conversation ID: \(conversationId)")
        print("[ConversationService] Limit: \(limit)")

        // For local-only conversations, always use local store
        if conversationId.hasPrefix("local_") {
            let localMessages = localStore.loadMessages(conversationId: conversationId)
            print("[ConversationService] ✅ Loaded \(localMessages.count) messages from local store (offline conversation)")
            self.messages = localMessages
            return localMessages
        }

        // Get the conversation to check expected message count
        let conversation = conversations.first(where: { $0.id == conversationId })
        let expectedMessageCount = conversation?.messageCount ?? 0
        print("[ConversationService] Expected message count from conversation: \(expectedMessageCount)")

        // First, load from Core Data (instant)
        let localMessages = syncManager.loadLocalMessages(conversationId: conversationId)
        print("[ConversationService] Local messages in Core Data: \(localMessages.count)")

        // If no backend configured, always use local messages
        if !apiClient.isBackendConfigured {
            print("[ConversationService] ✅ No backend configured, using \(localMessages.count) local messages")
            self.messages = localMessages
            return localMessages
        }

        // Only use local messages if we have ALL of them
        if !localMessages.isEmpty && localMessages.count >= expectedMessageCount {
            print("[ConversationService] ✅ Loaded \(localMessages.count) messages from Core Data (complete)")
            self.messages = localMessages
            return localMessages
        }

        // If no local messages OR incomplete, fetch from API
        if localMessages.isEmpty {
            print("[ConversationService] ⚠️ No local messages found, fetching from API...")
        } else {
            print("[ConversationService] ⚠️ Incomplete messages in Core Data (\(localMessages.count)/\(expectedMessageCount)), fetching from API...")
        }
        return try await refreshMessages(conversationId: conversationId, limit: limit)
    }

    /// Force refresh messages from API (for pull-to-refresh)
    func refreshMessages(conversationId: String, limit: Int = 50) async throws -> [Message] {
        print("[ConversationService] 🔄 refreshMessages called")
        print("[ConversationService] Conversation ID: \(conversationId)")

        // If no backend configured, just return local messages
        guard apiClient.isBackendConfigured else {
            let localMessages = syncManager.loadLocalMessages(conversationId: conversationId)
            print("[ConversationService] No backend configured, returning \(localMessages.count) local messages")
            self.messages = localMessages
            return localMessages
        }

        print("[ConversationService] API Endpoint: /apiGetMessages?conversationId=\(conversationId)&limit=\(limit)")

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

            print("[ConversationService] 📨 API Response received")
            print("[ConversationService] Messages count: \(response.messages.count)")

            if response.messages.isEmpty {
                print("[ConversationService] ⚠️ WARNING: API returned 0 messages!")
                print("[ConversationService] Pagination info: \(String(describing: response.pagination))")
            } else {
                print("[ConversationService] ✅ Successfully fetched \(response.messages.count) messages")
                print("[ConversationService] First message ID: \(response.messages.first?.id ?? "N/A")")
                print("[ConversationService] First message role: \(response.messages.first?.role.rawValue ?? "N/A")")
                print("[ConversationService] First message preview: \(response.messages.first?.content.prefix(50) ?? "N/A")")
            }

            self.messages = response.messages

            // Save fetched messages to Core Data, replacing old ones
            if !response.messages.isEmpty {
                try await syncManager.saveMessagesToCoreData(response.messages, conversationId: conversationId)
                print("[ConversationService] 💾 Saved messages to Core Data")
            }

            return response.messages
        } catch {
            print("[ConversationService] ❌ Error refreshing messages: \(error)")
            print("[ConversationService] Error type: \(type(of: error))")
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Orchestration

    private let cloudOrchestrator = CloudConversationOrchestrator()
    private let onDeviceOrchestrator = OnDeviceConversationOrchestrator()

    private func getOrchestrator(settings: AppSettings) -> ConversationOrchestrator {
        // Use the unified setting - deviceModeConfig.aiProcessing is the single source of truth
        // The legacy deviceMode toggle and useOnDeviceOrchestration flag are deprecated
        let useOnDevice = settings.deviceModeConfig.aiProcessing == .onDevice
        return useOnDevice ? onDeviceOrchestrator : cloudOrchestrator
    }

    func sendMessage(conversationId: String, content: String, attachments: [MessageAttachment] = [], enabledTools: [String] = []) async throws -> Message {
        // Get API keys from storage
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

        // Load provider/model from settings with conversation overrides
        // modelId is the API identifier (e.g., "claude-haiku-4-5-20251001")
        // modelDisplayName is for UI display (e.g., "Claude Haiku 4.5")
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        var (providerString, modelId, _, providerDisplayName) = getProviderAndModel(for: conversationId, settings: settings)
        let runtimeOverrides = ConversationRuntimeOverrideManager.shared.resolve(
            conversationId: conversationId,
            baseProvider: providerString,
            baseModel: modelId,
            baseProviderDisplayName: providerDisplayName,
            baseModelParams: settings.modelGenerationSettings
        )
        providerString = runtimeOverrides.provider
        modelId = runtimeOverrides.model
        providerDisplayName = runtimeOverrides.providerDisplayName
        let resolvedModelParams = runtimeOverrides.modelParams

        if !attachments.isEmpty {
            let policy = AttachmentMimePolicyService.resolvePolicy(conversationId: conversationId, settings: settings)
            let validation = AttachmentMimePolicyService.validate(attachments: attachments, policy: policy)
            if case .rejected(let failures) = validation {
                throw APIError.networkError(
                    AttachmentMimePolicyService.validationErrorMessage(
                        failures: failures,
                        policy: policy
                    )
                )
            }
        }
        
        // Fix for Grok: map "xai" to "grok"
        if providerString == "xai" {
            providerString = "grok"
        }

        // Handle custom provider API key, endpoint, and model code
        var customBaseUrl: String? = nil
        var customApiKey: String? = nil
        // For built-in providers, modelId is already the API identifier
        // For custom providers, we may need to fetch the modelCode separately
        var modelCode: String? = modelId
        
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
                
                customBaseUrl = customProvider.apiEndpoint
                
                // Get the model code
                if let modelId = customModelId,
                   let customModel = customProvider.models.first(where: { $0.id == modelId }) {
                    modelCode = customModel.modelCode
                }
                
                // Retrieve API key from keychain
                if let apiKey = try? apiKeysStorage.getCustomProviderAPIKey(providerId: providerId), !apiKey.isEmpty {
                    customApiKey = apiKey
                }
            }
        }

        let contextWindowLimit = AIProvider.contextWindowForModel(modelCode ?? modelId, settings: settings)
        let config = OrchestrationConfig(
            provider: providerString,
            model: modelCode ?? modelId,
            providerName: providerDisplayName,
            contextWindowLimit: contextWindowLimit,
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
            modelParams: resolvedModelParams
        )

        do {
            // Add user message optimistically
            let userMessage = Message(
                conversationId: conversationId,
                role: .user,
                content: content,
                attachments: attachments
            )
            messages.append(userMessage)

            // Select orchestrator based on unified aiProcessing setting
            let orchestrator = getOrchestrator(settings: settings)
            let orchestratorType = orchestrator is OnDeviceConversationOrchestrator ? "OnDevice" : "Cloud"
            print("[ConversationService] Using \(orchestratorType) orchestrator (aiProcessing=\(settings.deviceModeConfig.aiProcessing.rawValue))")
            if !enabledTools.isEmpty {
                print("[ConversationService] Enabled tools: \(enabledTools)")
            }

            // Call orchestrator
            let (assistantMessage, memories) = try await orchestrator.sendMessage(
                conversationId: conversationId,
                content: content,
                attachments: attachments,
                enabledTools: enabledTools,
                messages: messages, // Pass full history including the new user message
                config: config
            )

            // Replace optimistic message with actual user message (if needed, or just keep it)
            // The orchestrator returns the assistant message.
            // We assume the user message we created is fine.
            
            messages.append(assistantMessage)
            ConversationRuntimeOverrideManager.shared.consumeTurnLeaseOnSuccessfulReply(conversationId: conversationId)

            // Save both messages to Core Data immediately
            try await syncManager.saveMessagesToCoreData([userMessage, assistantMessage], conversationId: conversationId)

            // After the assistant completes its response, attempt to generate a concise chat title
            // using Apple Intelligence (FoundationModels). This does NOT replace the existing
            // initial-title method; it just upgrades the title post-response.
            Task { @MainActor in
                await self.tryAutoRenameConversationAfterFirstReply(
                    conversationId: conversationId,
                    userMessage: userMessage,
                    assistantMessage: assistantMessage
                )
            }

            // Process and save memories if any were created
            if let memories = memories, !memories.isEmpty {
                // Save memories to Core Data via MemorySyncManager
                let memorySyncManager = MemorySyncManager.shared
                try await memorySyncManager.saveMemoriesToCoreData(memories)

                // Update MemoryService in-memory array so they appear in the Memory tab
                let memoryService = MemoryService.shared
                for memory in memories {
                    // Insert at beginning to show newest first
                    if !memoryService.memories.contains(where: { $0.id == memory.id }) {
                        memoryService.memories.insert(memory, at: 0)
                    }
                }
            }

            // Update widget data so home screen widget shows latest messages
            if let conversation = currentConversation ?? conversations.first(where: { $0.id == conversationId }) {
                Task { @MainActor in
                    await WidgetDataService.shared.updateConversationAsync(conversation, messages: self.messages)
                }
            }

            return assistantMessage
        } catch {
            // Remove optimistic message on error
            messages.removeAll { $0.id == messages.last?.id && $0.role == .user }
            self.error = error.localizedDescription
            throw error
        }
    }

    func regenerateAssistantMessage(conversationId: String, messageId: String) async throws -> Message {
        // Load provider from settings (fallback to anthropic)
        // modelId is the API identifier (e.g., "claude-haiku-4-5-20251001")
        // modelDisplayName is for UI display (e.g., "Claude Haiku 4.5")
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        var (providerString, modelId, modelDisplayName, providerDisplayName) = getProviderAndModel(for: conversationId, settings: settings)
        
        // Fix for Grok: map "xai" to "grok"
        if providerString == "xai" {
            providerString = "grok"
        }
        
        // Get API keys
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

        // Handle custom provider (simplified for regen, assuming same logic as sendMessage)
        var customBaseUrl: String? = nil
        var customApiKey: String? = nil
        // For built-in providers, modelId is already the API identifier
        var modelCode: String? = modelId
        
        if providerString == "openai-compatible" {
             // ... (Same logic as sendMessage to get custom config)
             // For brevity, we might want to extract this config creation logic
             // But for now, we'll just use the basic settings if overrides aren't easily accessible without duplicating code
             // Or we can rely on getProviderAndModel to give us the right provider/model, but we need the keys.
             
             // Re-implementing custom provider key fetch for regeneration:
             if let customProviderId = settings.selectedCustomProviderId,
                let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }) {
                 customBaseUrl = customProvider.apiEndpoint
                 if let apiKey = try? apiKeysStorage.getCustomProviderAPIKey(providerId: customProviderId) {
                     customApiKey = apiKey
                 }
                 if let modelId = settings.selectedCustomModelId,
                    let customModel = customProvider.models.first(where: { $0.id == modelId }) {
                     modelCode = customModel.modelCode
                 }
             }
        }

        let contextWindowLimit = AIProvider.contextWindowForModel(modelCode ?? modelId, settings: settings)
        let config = OrchestrationConfig(
            provider: providerString,
            model: modelCode ?? modelId,
            providerName: providerDisplayName,
            contextWindowLimit: contextWindowLimit,
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
            modelParams: settings.modelGenerationSettings
        )

        do {
            let orchestrator = getOrchestrator(settings: settings)

            let newAssistant = try await orchestrator.regenerateAssistantMessage(
                conversationId: conversationId,
                messageId: messageId,
                messages: messages,
                config: config
            )

            // Update local state
            // Logic depends on whether we replaced the message or appended
            // The orchestrator returns the new message.
            // We'll assume we replace the last assistant message if it matches messageId, or append.
            
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index] = newAssistant
            } else {
                messages.append(newAssistant)
            }

            // Save regenerated message to Core Data
            try await syncManager.saveMessagesToCoreData([newAssistant], conversationId: conversationId)

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

    // MARK: - Auto Title

    /// Attempts to auto-rename a conversation after the assistant completes a reply.
    ///
    /// - Important: Will not override user manual renames (displayNameOverride).
    /// - Important: Uses only the last (user, assistant) messages to keep latency predictable.
    @MainActor
    private func tryAutoRenameConversationAfterFirstReply(
        conversationId: String,
        userMessage: Message,
        assistantMessage: Message
    ) async {
        // Do not override a manual rename.
        if SettingsStorage.shared.displayName(for: conversationId) != nil {
            print("[ConversationService] ℹ️ Auto-title skipped: manual rename exists")
            return
        }

        // Only attempt when we have a conversation loaded.
        guard let conv = conversations.first(where: { $0.id == conversationId }) else {
            print("[ConversationService] ⚠️ Auto-title skipped: conversation not in memory")
            return
        }

        // Heuristic: only auto-rename if the current title looks like the placeholder
        // (the app currently uses the first user message prefix).
        let placeholderTitle = String(userMessage.content.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholder = conv.title == "New Chat" || conv.title == placeholderTitle
        guard isPlaceholder else {
            print("[ConversationService] ℹ️ Auto-title skipped: title already non-placeholder ('\(conv.title)')")
            return
        }

        do {
            let generated = try await ConversationTitleOrchestrator.shared.generateTitle(
                userMessage: userMessage,
                assistantMessage: assistantMessage
            )

            let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                print("[ConversationService] ⚠️ Auto-title generation produced empty title; skipping")
                return
            }

            // 1) Update UI immediately via local display name override.
            ConversationTitleOrchestrator.shared.applyTitle(trimmed, to: conversationId)

            // 2) Persist/sync as the official conversation title (if possible).
            do {
                _ = try await updateConversation(id: conversationId, title: trimmed)
            } catch {
                // In local-only / offline mode this can still succeed (local store), but if it
                // fails we keep the displayNameOverride so the UI still shows the new title.
                print("[ConversationService] ⚠️ Auto-title could not persist server-side: \(error.localizedDescription)")
            }

            print("[ConversationService] ✅ Auto-renamed conversation \(conversationId) -> '\(trimmed)'")
        } catch {
            // Leave the existing title as-is.
            print("[ConversationService] ⚠️ Auto-title generation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Message Editing & Deletion

    /// Edit a user message's content (preserves edit history)
    func editMessage(conversationId: String, messageId: String, content: String) async throws -> Message {
        // Verify the message exists and is a user message
        guard let existingIndex = messages.firstIndex(where: { $0.id == messageId }) else {
            throw ConversationError.notFound
        }

        let existingMessage = messages[existingIndex]
        guard existingMessage.role == .user else {
            throw ConversationError.invalidData  // Can only edit user messages
        }

        // Update in local store (with edit history)
        try localStore.updateLocalMessage(id: messageId, content: content, conversationId: conversationId)

        // Build the new edit history
        var newEditHistory = existingMessage.editHistory ?? []
        let editEntry = MessageEdit(
            id: UUID().uuidString,
            content: existingMessage.content,
            timestamp: Date(),
            version: existingMessage.currentVersion ?? 0
        )
        newEditHistory.append(editEntry)

        // Create updated message model
        let updatedMessage = Message(
            id: existingMessage.id,
            conversationId: existingMessage.conversationId,
            role: existingMessage.role,
            content: content,
            hiddenReason: existingMessage.hiddenReason,
            timestamp: existingMessage.timestamp,
            tokens: existingMessage.tokens,
            artifacts: existingMessage.artifacts,
            toolCalls: existingMessage.toolCalls,
            isStreaming: existingMessage.isStreaming,
            modelName: existingMessage.modelName,
            providerName: existingMessage.providerName,
            attachments: existingMessage.attachments,
            groundingSources: existingMessage.groundingSources,
            memoryOperations: existingMessage.memoryOperations,
            reasoning: existingMessage.reasoning,
            editHistory: newEditHistory,
            currentVersion: (existingMessage.currentVersion ?? 0) + 1,
            contextDebugInfo: existingMessage.contextDebugInfo,
            liveToolCalls: existingMessage.liveToolCalls,
            isDeleted: existingMessage.isDeleted
        )

        // Update in-memory array
        messages[existingIndex] = updatedMessage

        print("[ConversationService] Edited message: \(messageId)")
        return updatedMessage
    }

    /// Delete a user message (soft-delete - shows placeholder)
    func deleteMessage(conversationId: String, messageId: String) async throws {
        // Verify the message exists and is a user message
        guard let existingIndex = messages.firstIndex(where: { $0.id == messageId }) else {
            throw ConversationError.notFound
        }

        let existingMessage = messages[existingIndex]
        guard existingMessage.role == .user else {
            throw ConversationError.invalidData  // Can only delete user messages
        }

        // Update in local store
        try localStore.deleteLocalMessage(id: messageId, conversationId: conversationId)

        // Create updated message model with isDeleted flag
        let deletedMessage = Message(
            id: existingMessage.id,
            conversationId: existingMessage.conversationId,
            role: existingMessage.role,
            content: existingMessage.content,
            hiddenReason: existingMessage.hiddenReason,
            timestamp: existingMessage.timestamp,
            tokens: existingMessage.tokens,
            artifacts: existingMessage.artifacts,
            toolCalls: existingMessage.toolCalls,
            isStreaming: existingMessage.isStreaming,
            modelName: existingMessage.modelName,
            providerName: existingMessage.providerName,
            attachments: existingMessage.attachments,
            groundingSources: existingMessage.groundingSources,
            memoryOperations: existingMessage.memoryOperations,
            reasoning: existingMessage.reasoning,
            editHistory: existingMessage.editHistory,
            currentVersion: existingMessage.currentVersion,
            contextDebugInfo: existingMessage.contextDebugInfo,
            liveToolCalls: existingMessage.liveToolCalls,
            isDeleted: true
        )

        // Update in-memory array
        messages[existingIndex] = deletedMessage

        print("[ConversationService] Deleted message: \(messageId)")
    }

    /// Edit a user message and regenerate the AI response (cascade delete subsequent messages)
    func editAndRegenerate(conversationId: String, messageId: String, content: String, enabledTools: [String] = []) async throws -> Message {
        // Verify the message exists and is a user message
        guard let existingIndex = messages.firstIndex(where: { $0.id == messageId }) else {
            throw ConversationError.notFound
        }

        let existingMessage = messages[existingIndex]
        guard existingMessage.role == .user else {
            throw ConversationError.invalidData  // Can only edit user messages
        }

        // 1. Delete all messages after this one (cascade)
        try localStore.deleteMessagesAfter(messageId: messageId, conversationId: conversationId)

        // Remove from in-memory array too
        let messageIndex = messages.firstIndex(where: { $0.id == messageId })!
        messages = Array(messages.prefix(through: messageIndex))

        // 2. Edit the user message
        _ = try await editMessage(conversationId: conversationId, messageId: messageId, content: content)

        // 3. Regenerate AI response by sending the edited content
        let assistantMessage = try await sendMessage(
            conversationId: conversationId,
            content: content,
            attachments: existingMessage.attachments ?? [],
            enabledTools: enabledTools
        )

        print("[ConversationService] Edit & regenerate completed for message: \(messageId)")
        return assistantMessage
    }

    // MARK: - Helpers

    func clearCurrentConversation() {
        currentConversation = nil
        messages = []
    }
}

// MARK: - Conversation Errors

enum ConversationError: LocalizedError {
    case notFound
    case invalidData
    case backendNotConfigured

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Conversation not found"
        case .invalidData:
            return "Invalid conversation data"
        case .backendNotConfigured:
            return "No backend configured"
        }
    }
}
