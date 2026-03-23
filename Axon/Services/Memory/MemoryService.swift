//
//  MemoryService.swift
//  Axon
//
//  Service for managing the intelligent memory system
//

import Combine
import Foundation

@MainActor
class MemoryService: ObservableObject {
    static let shared = MemoryService()

    private let apiClient = APIClient.shared
    private let syncManager = MemorySyncManager.shared
    private let salienceService = SalienceService.shared

    // Co-sovereignty services
    private var sovereigntyService: SovereigntyService { SovereigntyService.shared }
    private var aiConsentService: AIConsentService { AIConsentService.shared }
    private var negotiationService: CovenantNegotiationService { CovenantNegotiationService.shared }

    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var error: String?

    // Co-sovereignty state
    @Published var pendingConsentRequest: MemoryConsentRequest?
    @Published var consentRequired: Bool = false
    @Published var subconsciousWarnings: [String: SubconsciousLoggingWarning] = [:]

    private var subconsciousTasks: [String: Task<Void, Never>] = [:]

    private init() {
        // Load memories from local Core Data immediately (instant UI)
        loadLocalMemories()
    }

    // MARK: - Subconscious Memory Logging

    struct SubconsciousLoggingWarning: Identifiable, Equatable, Sendable {
        let conversationId: String
        let message: String
        let timestamp: Date

        var id: String { conversationId }
    }

    /// Fire-and-forget background memory logging run after an assistant reply.
    func enqueuePostTurnLogging(conversationId: String, messages: [Message]) {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        guard settings.memoryEnabled else { return }
        guard settings.resolvedSubconsciousMemoryLogging.enabled else { return }
        guard !ConversationOverridesManager.shared.isSubconsciousLoggingDisabled(for: conversationId) else { return }

        // Keep one active task per conversation to avoid stale overlapping passes.
        subconsciousTasks[conversationId]?.cancel()
        let snapshot = messages

        subconsciousTasks[conversationId] = Task { [weak self] in
            guard let self else { return }
            defer { self.subconsciousTasks[conversationId] = nil }
            await self.runSubconsciousLogging(conversationId: conversationId, messages: snapshot)
        }
    }

    func dismissSubconsciousWarning(conversationId: String) {
        subconsciousWarnings.removeValue(forKey: conversationId)
    }

    func ignoreSubconsciousLoggingForThread(conversationId: String) {
        ConversationOverridesManager.shared.setSubconsciousLoggingDisabled(true, for: conversationId)
        subconsciousWarnings.removeValue(forKey: conversationId)
        subconsciousTasks[conversationId]?.cancel()
        subconsciousTasks.removeValue(forKey: conversationId)
    }

    func subconsciousWarning(for conversationId: String) -> SubconsciousLoggingWarning? {
        subconsciousWarnings[conversationId]
    }

    // MARK: - Co-Sovereignty: Consent Request

    /// Request to create/modify/delete memory that requires AI consent
    struct MemoryConsentRequest: Identifiable {
        let id = UUID()
        let operation: MemoryOperation
        let memoryId: String?
        let content: String?
        let rationale: String
        let proposal: CovenantProposal?
    }

    enum MemoryOperation: String {
        case create
        case update
        case delete

        var actionCategory: ActionCategory {
            switch self {
            case .create: return .memoryAdd
            case .update: return .memoryModify
            case .delete: return .memoryDelete
            }
        }
    }

    // MARK: - Local-First Data Access

    /// Load memories from Core Data (instant, no network)
    private func loadLocalMemories() {
        let loaded = syncManager.loadLocalMemories()
        print("[MemoryService] Loaded \(loaded.count) memories from Core Data")
        memories = loaded
    }

    /// Sync memories with server in background
    func syncMemoriesInBackground() {
        Task { @MainActor in
            do {
                try await syncManager.syncMemories()
                // Reload from Core Data after successful sync
                loadLocalMemories()
            } catch {
                self.error = error.localizedDescription
                print("[MemoryService] Sync failed: \(error)")
            }
        }
    }

    // MARK: - Co-Sovereignty: Check Consent

    /// Check if co-sovereignty is enabled and consent is required for memory operations
    private var isSovereigntyEnabled: Bool {
        sovereigntyService.activeCovenant != nil
    }

    /// Check if AI consent is needed for a memory operation
    private func requiresAIConsent(for operation: MemoryOperation) -> Bool {
        guard isSovereigntyEnabled else { return false }

        // Memory modifications always require AI consent under co-sovereignty
        let action = SovereignAction.category(operation.actionCategory)
        let permission = sovereigntyService.checkActionPermission(action)

        switch permission {
        case .requiresAIConsent:
            return true
        case .preApproved:
            return false // Covered by trust tier
        case .blocked:
            return true // Will trigger deadlock flow
        case .requiresApproval:
            return true
        }
    }

    /// Request AI consent for a memory operation
    private func requestAIConsent(
        operation: MemoryOperation,
        memoryId: String?,
        content: String?,
        rationale: String
    ) async throws -> AIAttestation {
        let memoryChanges: MemoryChanges
        switch operation {
        case .create:
            let addition = MemoryAddition(
                content: content ?? "",
                type: "allocentric",
                confidence: 0.8,
                tags: [],
                context: nil
            )
            memoryChanges = MemoryChanges(additions: [addition], modifications: nil, deletions: nil)
        case .update:
            let modification = MemoryModification(
                memoryId: memoryId ?? "",
                newContent: content,
                newConfidence: nil,
                newTags: nil
            )
            memoryChanges = MemoryChanges(additions: nil, modifications: [modification], deletions: nil)
        case .delete:
            memoryChanges = MemoryChanges(additions: nil, modifications: nil, deletions: [memoryId ?? ""])
        }

        let proposal = CovenantProposal.create(
            type: .modifyMemories,
            changes: .memory(memoryChanges),
            proposedBy: .user,
            rationale: rationale
        )

        // Store pending request for UI
        pendingConsentRequest = MemoryConsentRequest(
            operation: operation,
            memoryId: memoryId,
            content: content,
            rationale: rationale,
            proposal: proposal
        )
        consentRequired = true

        // Request AI attestation
        let attestation = try await aiConsentService.generateAttestation(
            for: proposal,
            memories: memories
        )

        // Clear pending request
        pendingConsentRequest = nil
        consentRequired = false

        // If AI declined, throw error
        if attestation.didDecline {
            throw SovereigntyError.aiDeclined(attestation.reasoning)
        }

        return attestation
    }

    // MARK: - Create Memory

    /// Create memory with co-sovereignty consent check
    func createMemory(
        content: String,
        type: MemoryType,
        confidence: Double,
        tags: [String] = [],
        context: String? = nil,
        metadata: [String: AnyCodable] = [:],
        skipConsent: Bool = false
    ) async throws -> Memory {
        // Check if AI consent is required
        if !skipConsent && requiresAIConsent(for: .create) {
            let attestation = try await requestAIConsent(
                operation: .create,
                memoryId: nil,
                content: content,
                rationale: "User wants to add a new memory: \(content.prefix(100))..."
            )
            print("[MemoryService] AI consented to memory creation: \(attestation.shortSignature)")
        }

        return try await createMemoryInternal(
            content: content,
            type: type,
            confidence: confidence,
            tags: tags,
            context: context,
            metadata: metadata
        )
    }

    /// Internal memory creation (after consent obtained)
    private func createMemoryInternal(
        content: String,
        type: MemoryType,
        confidence: Double,
        tags: [String] = [],
        context: String? = nil,
        metadata: [String: AnyCodable] = [:]
    ) async throws -> Memory {
        isLoading = true
        defer { isLoading = false }

        // Auto-inject temporal tags for time awareness
        var enrichedTags = tags
        let temporalTags = Memory.temporalTags(for: Date())
        enrichedTags.append(contentsOf: temporalTags)
        // Remove duplicates while preserving order
        enrichedTags = Array(NSOrderedSet(array: enrichedTags)) as? [String] ?? enrichedTags

        // Check if backend is configured
        if apiClient.isBackendConfigured {
            // Cloud mode: Create via API and sync
            struct CreateMemoryRequest: Encodable {
                let content: String
                let type: String
                let confidence: Double
                let tags: [String]
                let context: String?
                let metadata: [String: AnyCodable]
            }

            let request = CreateMemoryRequest(
                content: content,
                type: type.rawValue,
                confidence: confidence,
                tags: enrichedTags,
                context: context,
                metadata: metadata
            )

            do {
                let memory: Memory = try await apiClient.requestWrapped(
                    endpoint: "/apiCreateMemory",
                    method: .post,
                    body: request
                )

                // Save to Core Data immediately
                try await syncManager.saveMemoriesToCoreData([memory])

                // Add to in-memory array
                memories.insert(memory, at: 0)
                return memory
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        } else {
            // Local-first mode: Create locally without backend
            let memory = Memory(
                id: UUID().uuidString,
                userId: "local",
                content: content,
                type: type,
                confidence: confidence,
                tags: enrichedTags,
                context: context,
                metadata: metadata,
                source: nil,
                relatedMemories: nil,
                createdAt: Date(),
                updatedAt: Date(),
                lastAccessedAt: nil,
                accessCount: 0
            )

            // Save to Core Data
            try await syncManager.saveMemoriesToCoreData([memory])

            // Add to in-memory array
            memories.insert(memory, at: 0)
            print("[MemoryService] Created local memory: \(memory.id)")
            return memory
        }
    }

    // MARK: - Get Memories

    /// List memories - loads from Core Data first, then syncs in background
    func getMemories(limit: Int = 50, offset: Int = 0, type: MemoryType? = nil) async throws {
        // Load from Core Data immediately (instant)
        loadLocalMemories()

        // Apply type filter if specified
        if let type = type {
            memories = memories.filter { $0.type == type }
        }

        // Trigger background sync (non-blocking)
        syncMemoriesInBackground()
    }

    // MARK: - Get Single Memory

    func getMemory(id: String) async throws -> Memory {
        isLoading = true
        defer { isLoading = false }

        // Try local first
        if let localMemory = memories.first(where: { $0.id == id }) {
            return localMemory
        }

        // If backend configured, try to fetch from server
        if apiClient.isBackendConfigured {
            do {
                return try await apiClient.requestWrapped(
                    endpoint: "/apiGetMemory?memoryId=\(id)",
                    method: .get
                )
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        }

        throw MemoryError.notFound
    }

    // MARK: - Update Memory

    /// Update memory with co-sovereignty consent check
    func updateMemory(
        id: String,
        content: String? = nil,
        confidence: Double? = nil,
        tags: [String]? = nil,
        context: String? = nil,
        metadata: [String: AnyCodable]? = nil,
        skipConsent: Bool = false
    ) async throws -> Memory {
        // Find existing memory
        guard let existingIndex = memories.firstIndex(where: { $0.id == id }) else {
            throw MemoryError.notFound
        }
        let existing = memories[existingIndex]

        // Check if AI consent is required
        if !skipConsent && requiresAIConsent(for: .update) {
            let attestation = try await requestAIConsent(
                operation: .update,
                memoryId: id,
                content: content,
                rationale: "User wants to modify memory: \(existing.content.prefix(50))... → \(content?.prefix(50) ?? "no content change")"
            )
            print("[MemoryService] AI consented to memory update: \(attestation.shortSignature)")
        }

        if apiClient.isBackendConfigured {
            // Cloud mode: Update via API
            struct UpdateMemoryRequest: Encodable {
                let memoryId: String
                let content: String?
                let confidence: Double?
                let tags: [String]?
                let context: String?
                let metadata: [String: AnyCodable]?
            }

            let request = UpdateMemoryRequest(
                memoryId: id,
                content: content,
                confidence: confidence,
                tags: tags,
                context: context,
                metadata: metadata
            )

            do {
                let memory: Memory = try await apiClient.requestWrapped(
                    endpoint: "/apiUpdateMemory",
                    method: .post,
                    body: request
                )

                // Save updated memory to Core Data
                try await syncManager.saveMemoriesToCoreData([memory])

                // Update in-memory array
                memories[existingIndex] = memory
                return memory
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        } else {
            // Local-first mode: Update locally
            let updatedMemory = Memory(
                id: existing.id,
                userId: existing.userId,
                content: content ?? existing.content,
                type: existing.type,
                confidence: confidence ?? existing.confidence,
                tags: tags ?? existing.tags,
                context: context ?? existing.context,
                metadata: metadata ?? existing.metadata,
                source: existing.source,
                relatedMemories: existing.relatedMemories,
                createdAt: existing.createdAt,
                updatedAt: Date(),
                lastAccessedAt: existing.lastAccessedAt,
                accessCount: existing.accessCount
            )

            // Save to Core Data
            try await syncManager.saveMemoriesToCoreData([updatedMemory])

            // Update in-memory array
            memories[existingIndex] = updatedMemory
            print("[MemoryService] Updated local memory: \(id)")
            return updatedMemory
        }
    }

    // MARK: - Delete Memory

    /// Delete memory with co-sovereignty consent check
    func deleteMemory(id: String, skipConsent: Bool = false) async throws {
        // Check if AI consent is required BEFORE deleting
        if !skipConsent && requiresAIConsent(for: .delete) {
            // Find the memory to show in consent request
            let memoryContent = memories.first(where: { $0.id == id })?.content ?? "Unknown memory"
            let attestation = try await requestAIConsent(
                operation: .delete,
                memoryId: id,
                content: nil,
                rationale: "User wants to delete memory: \(memoryContent.prefix(100))..."
            )
            print("[MemoryService] AI consented to memory deletion: \(attestation.shortSignature)")
        }

        // CRITICAL: Remove from in-memory array FIRST (optimistic update)
        memories.removeAll { $0.id == id }

        if apiClient.isBackendConfigured {
            // Cloud mode: Soft-delete locally then try server
            struct DeleteResponse: Decodable {
                let success: Bool
            }

            // Soft-delete from Core Data immediately to prevent resurrection
            try await syncManager.deleteMemoryFromCoreData(id: id)
            print("[MemoryService] Soft-deleted memory \(id) locally")

            // Then try to delete from server
            do {
                let _: DeleteResponse = try await apiClient.request(
                    endpoint: "/apiDeleteMemory/\(id)",
                    method: .delete
                )

                // Server confirmed - hard delete the tombstone
                try await syncManager.hardDeleteMemoryFromCoreData(id: id)
                print("[MemoryService] ✅ Server confirmed deletion, hard-deleted memory \(id)")
            } catch {
                // Server delete failed, but keep the soft-delete tombstone
                // This prevents resurrection on next sync
                print("[MemoryService] ⚠️ Server delete failed for memory \(id), keeping tombstone: \(error.localizedDescription)")
                self.error = error.localizedDescription
                throw error
            }
        } else {
            // Local-first mode: Hard delete immediately (no server to sync with)
            try await syncManager.hardDeleteMemoryFromCoreData(id: id)
            print("[MemoryService] Deleted local memory: \(id)")
        }
    }

    // MARK: - Bulk Delete Memories

    /// Delete multiple memories with a single consent request
    /// This is more efficient for bulk operations like resolving duplicates
    func deleteMemories(ids: [String], rationale: String, skipConsent: Bool = false) async throws -> Int {
        guard !ids.isEmpty else { return 0 }

        // Request consent once for all deletions
        if !skipConsent && requiresAIConsent(for: .delete) {
            let memoryPreviews = ids.compactMap { id in
                memories.first(where: { $0.id == id })?.content.prefix(50)
            }.prefix(5).map { String($0) + "..." }

            let bulkRationale = """
                \(rationale)

                Deleting \(ids.count) memories:
                \(memoryPreviews.joined(separator: "\n- "))
                \(ids.count > 5 ? "... and \(ids.count - 5) more" : "")
                """

            let memoryChanges = MemoryChanges(additions: nil, modifications: nil, deletions: ids)
            let proposal = CovenantProposal.create(
                type: .modifyMemories,
                changes: .memory(memoryChanges),
                proposedBy: .user,
                rationale: bulkRationale
            )

            pendingConsentRequest = MemoryConsentRequest(
                operation: .delete,
                memoryId: nil,
                content: nil,
                rationale: bulkRationale,
                proposal: proposal
            )
            consentRequired = true

            let attestation = try await aiConsentService.generateAttestation(
                for: proposal,
                memories: memories
            )

            pendingConsentRequest = nil
            consentRequired = false

            if attestation.didDecline {
                throw SovereigntyError.aiDeclined(attestation.reasoning)
            }

            print("[MemoryService] AI consented to bulk deletion of \(ids.count) memories: \(attestation.shortSignature)")
        }

        // Remove from in-memory array first (optimistic update)
        memories.removeAll { ids.contains($0.id) }

        var successCount = 0

        if apiClient.isBackendConfigured {
            // Cloud mode: Soft-delete then try server
            for id in ids {
                do {
                    try await syncManager.deleteMemoryFromCoreData(id: id)

                    struct DeleteResponse: Decodable { let success: Bool }
                    let _: DeleteResponse = try await apiClient.request(
                        endpoint: "/apiDeleteMemory/\(id)",
                        method: .delete
                    )

                    try await syncManager.hardDeleteMemoryFromCoreData(id: id)
                    successCount += 1
                } catch {
                    print("[MemoryService] Failed to delete memory \(id): \(error.localizedDescription)")
                }
            }
        } else {
            // Local-first mode: Hard delete immediately
            for id in ids {
                do {
                    try await syncManager.hardDeleteMemoryFromCoreData(id: id)
                    successCount += 1
                } catch {
                    print("[MemoryService] Failed to delete memory \(id): \(error.localizedDescription)")
                }
            }
        }

        print("[MemoryService] Bulk deleted \(successCount)/\(ids.count) memories")
        return successCount
    }

    // MARK: - Search Memories

    func searchMemories(
        query: String,
        types: [MemoryType]? = nil,
        limit: Int = 10,
        minConfidence: Double? = nil
    ) async throws -> [Memory] {
        isLoading = true
        defer { isLoading = false }

        if apiClient.isBackendConfigured {
            // Cloud mode: Use vector search API
            let request = MemorySearchRequest(
                query: query,
                types: types,
                limit: limit,
                minConfidence: minConfidence
            )

            do {
                let response: MemoryListResponse = try await apiClient.requestWrapped(
                    endpoint: "/apiRetrieveMemories",
                    method: .post,
                    body: request
                )
                return response.memories
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        } else {
            // Local-first mode: Simple text search in local memories
            let queryLower = query.lowercased()
            var results = memories.filter { memory in
                // Check content
                if memory.content.lowercased().contains(queryLower) {
                    return true
                }
                // Check tags
                if memory.tags.contains(where: { $0.lowercased().contains(queryLower) }) {
                    return true
                }
                // Check context
                if let context = memory.context, context.lowercased().contains(queryLower) {
                    return true
                }
                return false
            }

            // Filter by types if specified
            if let types = types {
                results = results.filter { types.contains($0.type) }
            }

            // Filter by minimum confidence if specified
            if let minConfidence = minConfidence {
                results = results.filter { $0.confidence >= minConfidence }
            }

            // Sort by confidence (descending) and limit
            results = Array(results.sorted { $0.confidence > $1.confidence }.prefix(limit))

            print("[MemoryService] Local search for '\(query)' found \(results.count) results")
            return results
        }
    }

    // MARK: - Get Relevant Memories

    func getRelevantMemories(conversationId: String, limit: Int = 5) async throws -> [Memory] {
        if apiClient.isBackendConfigured {
            struct GetConversationResponse: Decodable {
                struct MemoriesPayload: Decodable {
                    let memories: [Memory]
                    let injection: String?
                }
                let memories: MemoriesPayload?
            }

            do {
                // Use conversations API to retrieve relevant memories by including them in the response
                let response: GetConversationResponse = try await apiClient.request(
                    endpoint: "/apiGetConversation/\(conversationId)?includeMemories=true",
                    method: .get
                )
                // Backend may return up to its own cap; enforce client-side limit
                let all = response.memories?.memories ?? []
                return Array(all.prefix(limit))
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        } else {
            // Local-first mode: Return most recent high-confidence memories
            let relevantMemories = memories
                .sorted { $0.confidence > $1.confidence }
                .prefix(limit)
            return Array(relevantMemories)
        }
    }

    // MARK: - Memory Analytics

    func getMemoryStats() async throws -> MemoryStats {
        if apiClient.isBackendConfigured {
            do {
                return try await apiClient.requestWrapped(
                    endpoint: "/apiMemoryAnalytics",
                    method: .get
                )
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        } else {
            // Local-first mode: Calculate stats from local memories
            let byType = Dictionary(grouping: memories, by: { $0.type.rawValue })
                .mapValues { $0.count }

            let totalConfidence = memories.reduce(0.0) { $0 + $1.confidence }
            let avgConfidence = memories.isEmpty ? 0.0 : totalConfidence / Double(memories.count)

            let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let recentCount = memories.filter { $0.createdAt > oneWeekAgo }.count

            return MemoryStats(
                total: memories.count,
                byType: byType,
                averageConfidence: avgConfidence,
                recentCount: recentCount
            )
        }
    }

    private func runSubconsciousLogging(conversationId: String, messages: [Message]) async {
        if Task.isCancelled { return }

        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        let subsystem = settings.resolvedSubconsciousMemoryLogging

        guard settings.memoryEnabled, subsystem.enabled else { return }
        guard !ConversationOverridesManager.shared.isSubconsciousLoggingDisabled(for: conversationId) else { return }

        let messageCandidates = messages.filter { $0.role == .user || $0.role == .assistant }
        guard !messageCandidates.isEmpty else { return }

        let runtimeResult = resolveSubconsciousRuntimeConfig(selection: subsystem, settings: settings)
        guard case .success(let runtime) = runtimeResult else {
            if case .failure(let warning) = runtimeResult {
                setSubconsciousWarning(conversationId: conversationId, message: warning.message)
            }
            return
        }

        let rollingBudget = Self.clampedRollingTokenBudget(
            percent: subsystem.rollingContextPercent,
            contextWindow: runtime.contextWindow
        )
        let rollingContext = buildRollingContextMessages(from: messageCandidates, tokenBudget: rollingBudget)
        guard !rollingContext.isEmpty else { return }

        let candidateMemories = memories.filter { $0.confidence >= subsystem.confidenceThreshold }
        let injectionSettings = MemoryInjectionSettings(
            maxMemories: max(1, subsystem.maxMemories),
            minSalienceThreshold: max(0.0, min(1.0, subsystem.minSalienceThreshold)),
            relevanceWeight: max(0.0, subsystem.relevanceWeight),
            confidenceWeight: max(0.0, subsystem.confidenceWeight),
            recencyWeight: max(0.0, subsystem.recencyWeight),
            showConfidence: subsystem.showConfidence,
            includeEpistemicBoundaries: subsystem.includeEpistemicBoundaries
        )

        let injectionBudget = max(256, min(4_000, rollingBudget / 3))
        let correlationId = "subconscious-\(UUID().uuidString)"
        let memoryInjection = await salienceService.injectSalient(
            conversation: rollingContext,
            memories: candidateMemories,
            availableTokens: injectionBudget,
            correlationId: correlationId,
            settings: injectionSettings,
            userName: currentUserDisplayName(from: settings)
        )

        let systemPrompt = buildSubconsciousSystemPrompt()
        let userPrompt = buildSubconsciousUserPrompt(
            rollingContext: rollingContext,
            memoryInjection: memoryInjection.injectionBlock,
            tokenBudget: rollingBudget
        )

        var llmMessages: [SubconsciousLLMMessage] = [
            SubconsciousLLMMessage(role: "user", content: userPrompt)
        ]

        let maxRounds = max(1, min(8, subsystem.maxToolRounds))
        for _ in 0..<maxRounds {
            if Task.isCancelled { return }

            let response: String
            do {
                response = try await SubconsciousProviderHTTPClient.generate(
                    system: systemPrompt,
                    messages: llmMessages,
                    runtime: runtime
                )
            } catch {
                setSubconsciousWarning(
                    conversationId: conversationId,
                    message: "Subconscious memory logging failed for \(runtime.providerDisplayName)/\(runtime.model): \(error.localizedDescription)"
                )
                return
            }

            let parsedRequests = ToolProxyService.shared.parseAllToolRequests(from: response)
            let filteredRequests = Self.filterSubconsciousToolRequests(parsedRequests)
            let memoryRequests = filteredRequests.allowed
            let ignoredRequests = filteredRequests.ignored

            guard !memoryRequests.isEmpty else {
                if !ignoredRequests.isEmpty {
                    let ignoredIds = ignoredRequests.map(\.tool).joined(separator: ", ")
                    print("[MemoryService] Subconscious logger ignored non-memory tool request(s): \(ignoredIds)")
                }
                subconsciousWarnings.removeValue(forKey: conversationId)
                return
            }

            let assistantText = ToolProxyService.shared.removeToolRequest(from: response)
            if !assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                llmMessages.append(SubconsciousLLMMessage(role: "assistant", content: assistantText))
            }

            var toolResultLines: [String] = []

            for request in memoryRequests {
                do {
                    let result = try await ToolProxyService.shared.executeToolRequest(
                        request,
                        geminiApiKey: "",
                        conversationContext: nil
                    )
                    toolResultLines.append(ToolProxyService.shared.formatToolResult(result))
                } catch {
                    toolResultLines.append("Tool `\(request.tool)` failed: \(error.localizedDescription)")
                }
            }

            if !ignoredRequests.isEmpty {
                let ignoredIds = ignoredRequests.map(\.tool).joined(separator: ", ")
                toolResultLines.append("Ignored non-memory tool request(s): \(ignoredIds). Only `create_memory` is permitted.")
            }

            let feedback = """
            Tool results:
            \(toolResultLines.joined(separator: "\n\n"))

            If additional durable memories should be saved, emit more `create_memory` tool requests.
            Otherwise reply with `DONE`.
            """
            llmMessages.append(SubconsciousLLMMessage(role: "user", content: feedback))
        }

        subconsciousWarnings.removeValue(forKey: conversationId)
    }

    private func resolveSubconsciousRuntimeConfig(
        selection: SubconsciousMemoryLoggingSettings,
        settings: AppSettings
    ) -> Result<SubconsciousRuntimeConfig, SubconsciousRuntimeResolutionError> {
        let apiKeysStorage = APIKeysStorage.shared

        if let customProviderId = selection.customProviderId {
            guard let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }) else {
                return .failure(SubconsciousRuntimeResolutionError(message: "Subconscious model is unavailable: selected custom provider no longer exists."))
            }
            guard let selectedModel = customProvider.models.first(where: { $0.id == selection.customModelId }) ?? customProvider.models.first else {
                return .failure(SubconsciousRuntimeResolutionError(message: "Subconscious model is unavailable: selected custom model no longer exists."))
            }
            guard let apiKey = try? apiKeysStorage.getCustomProviderAPIKey(providerId: customProviderId), !apiKey.isEmpty else {
                return .failure(SubconsciousRuntimeResolutionError(message: "Subconscious model is unavailable: missing API key for custom provider \(customProvider.providerName)."))
            }

            return .success(
                SubconsciousRuntimeConfig(
                    provider: "openai-compatible",
                    providerDisplayName: customProvider.providerName,
                    model: selectedModel.modelCode,
                    contextWindow: max(1_024, selectedModel.contextWindow),
                    apiKey: apiKey,
                    baseUrl: customProvider.apiEndpoint
                )
            )
        }

        let builtInProviderRaw = selection.builtInProvider ?? settings.defaultProvider.rawValue
        guard let builtInProvider = AIProvider(rawValue: builtInProviderRaw) else {
            return .failure(SubconsciousRuntimeResolutionError(message: "Subconscious model is unavailable: unknown provider selection."))
        }

        switch builtInProvider {
        case .appleFoundation, .localMLX:
            return .failure(SubconsciousRuntimeResolutionError(message: "Subconscious model is unavailable: \(builtInProvider.displayName) is not currently supported for background memory logging."))
        default:
            break
        }

        let modelId: String = {
            if let selected = selection.builtInModel {
                return selected
            }
            if builtInProvider == settings.defaultProvider {
                return settings.defaultModel
            }
            return builtInProvider.availableModels.first?.id ?? settings.defaultModel
        }()

        let contextWindow = max(1_024, AIProvider.contextWindowForModel(modelId, settings: settings))

        let providerApiKey: String? = {
            switch builtInProvider {
            case .anthropic: return try? apiKeysStorage.getAPIKey(for: .anthropic)
            case .openai: return try? apiKeysStorage.getAPIKey(for: .openai)
            case .gemini: return try? apiKeysStorage.getAPIKey(for: .gemini)
            case .xai: return try? apiKeysStorage.getAPIKey(for: .xai)
            case .perplexity: return try? apiKeysStorage.getAPIKey(for: .perplexity)
            case .deepseek: return try? apiKeysStorage.getAPIKey(for: .deepseek)
            case .zai: return try? apiKeysStorage.getAPIKey(for: .zai)
            case .minimax: return try? apiKeysStorage.getAPIKey(for: .minimax)
            case .mistral: return try? apiKeysStorage.getAPIKey(for: .mistral)
            case .appleFoundation, .localMLX: return nil
            }
        }()

        guard let apiKey = providerApiKey, !apiKey.isEmpty else {
            return .failure(SubconsciousRuntimeResolutionError(message: "Subconscious model is unavailable: missing API key for \(builtInProvider.displayName)."))
        }

        let providerString = builtInProvider == .xai ? "grok" : builtInProvider.rawValue
        return .success(
            SubconsciousRuntimeConfig(
                provider: providerString,
                providerDisplayName: builtInProvider.displayName,
                model: modelId,
                contextWindow: contextWindow,
                apiKey: apiKey,
                baseUrl: nil
            )
        )
    }

    private func buildRollingContextMessages(from messages: [Message], tokenBudget: Int) -> [Message] {
        let eligible = messages.filter { $0.role == .user || $0.role == .assistant }
        guard !eligible.isEmpty else { return [] }

        var selected: [Message] = []
        var usedTokens = 0

        for message in eligible.reversed() {
            let tokens = estimateTokens(message.content)
            if !selected.isEmpty && (usedTokens + tokens) > tokenBudget {
                break
            }
            selected.append(message)
            usedTokens += tokens
        }

        return selected.reversed()
    }

    nonisolated static func clampedRollingTokenBudget(percent: Double, contextWindow: Int) -> Int {
        let clampedPercent = max(0.01, min(1.0, percent))
        let raw = Int(Double(contextWindow) * clampedPercent)
        let minBudget = 256
        let maxBudget = max(1_024, contextWindow)
        return max(minBudget, min(maxBudget, raw))
    }

    nonisolated static func filterSubconsciousToolRequests(_ requests: [ToolRequest]) -> (allowed: [ToolRequest], ignored: [ToolRequest]) {
        let allowed = requests.filter { $0.tool == ToolId.createMemory.rawValue }
        let ignored = requests.filter { $0.tool != ToolId.createMemory.rawValue }
        return (allowed, ignored)
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, Int(Double(text.count) / 4.0))
    }

    private func buildSubconsciousSystemPrompt() -> String {
        """
        I am Axon's subconscious memory logging subsystem.
        I maintain Axon's identity while focusing narrowly on durable memory formation.
        I only use memory operations when appropriate.

        Tool policy:
        - The only permitted tool is `create_memory`.
        - Ignore all other tool opportunities.
        - If nothing worth saving appears, reply `DONE`.
        """
    }

    private func buildSubconsciousUserPrompt(
        rollingContext: [Message],
        memoryInjection: String,
        tokenBudget: Int
    ) -> String {
        let contextLines = rollingContext.map { msg -> String in
            let prefix = msg.role == .user ? "User" : "Axon"
            return "\(prefix): \(msg.content)"
        }

        let memoryBlock: String
        if memoryInjection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            memoryBlock = "No salient injected memories for this pass."
        } else {
            memoryBlock = memoryInjection
        }

        return """
        Rolling context window budget: ~\(tokenBudget) tokens.

        Existing salient memory context:
        \(memoryBlock)

        Recent rolling conversation context:
        \(contextLines.joined(separator: "\n\n"))

        Task:
        - Identify durable facts/preferences or reliable interaction patterns worth retaining.
        - Emit `create_memory` tool requests for high-value items only.
        - Keep each saved memory concise and retrieval-oriented.
        - If there is nothing worth saving, reply `DONE`.
        """
    }

    private func currentUserDisplayName(from settings: AppSettings) -> String? {
        let first = settings.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = settings.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? nil : full
    }

    private func setSubconsciousWarning(conversationId: String, message: String) {
        subconsciousWarnings[conversationId] = SubconsciousLoggingWarning(
            conversationId: conversationId,
            message: message,
            timestamp: Date()
        )
    }
}

private struct SubconsciousRuntimeConfig: Sendable {
    let provider: String
    let providerDisplayName: String
    let model: String
    let contextWindow: Int
    let apiKey: String
    let baseUrl: String?
}

private struct SubconsciousRuntimeResolutionError: Error, LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

private struct SubconsciousLLMMessage: Sendable {
    let role: String
    let content: String
}

private enum SubconsciousProviderHTTPClient {
    static func generate(
        system: String,
        messages: [SubconsciousLLMMessage],
        runtime: SubconsciousRuntimeConfig
    ) async throws -> String {
        switch runtime.provider {
        case "anthropic":
            return try await callAnthropic(
                apiKey: runtime.apiKey,
                model: runtime.model,
                system: system,
                messages: messages
            )
        case "gemini":
            return try await callGemini(
                apiKey: runtime.apiKey,
                model: runtime.model,
                system: system,
                messages: messages
            )
        case "minimax":
            return try await callMiniMax(
                apiKey: runtime.apiKey,
                model: runtime.model,
                system: system,
                messages: messages
            )
        case "openai-compatible":
            guard let baseUrl = runtime.baseUrl, !baseUrl.isEmpty else {
                throw APIError.networkError("Missing custom provider base URL for subconscious logger")
            }
            return try await callOpenAICompatible(
                apiKey: runtime.apiKey,
                baseUrl: baseUrl,
                model: runtime.model,
                system: system,
                messages: messages
            )
        case "openai":
            return try await callOpenAICompatible(
                apiKey: runtime.apiKey,
                baseUrl: "https://api.openai.com/v1",
                model: runtime.model,
                system: system,
                messages: messages
            )
        case "grok":
            return try await callOpenAICompatible(
                apiKey: runtime.apiKey,
                baseUrl: "https://api.x.ai/v1",
                model: runtime.model,
                system: system,
                messages: messages
            )
        case "perplexity":
            return try await callOpenAICompatible(
                apiKey: runtime.apiKey,
                baseUrl: "https://api.perplexity.ai",
                model: runtime.model,
                system: system,
                messages: messages
            )
        case "deepseek":
            return try await callOpenAICompatible(
                apiKey: runtime.apiKey,
                baseUrl: "https://api.deepseek.com",
                model: runtime.model,
                system: system,
                messages: messages
            )
        case "zai":
            return try await callOpenAICompatible(
                apiKey: runtime.apiKey,
                baseUrl: "https://api.z.ai/api/paas/v4",
                model: runtime.model,
                system: system,
                messages: messages
            )
        case "mistral":
            return try await callOpenAICompatible(
                apiKey: runtime.apiKey,
                baseUrl: "https://api.mistral.ai/v1",
                model: runtime.model,
                system: system,
                messages: messages
            )
        default:
            throw APIError.networkError("Unsupported subconscious provider: \(runtime.provider)")
        }
    }

    private static func callAnthropic(
        apiKey: String,
        model: String,
        system: String,
        messages: [SubconsciousLLMMessage]
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")

        let apiMessages = messages.map { msg in
            [
                "role": msg.role == "assistant" ? "assistant" : "user",
                "content": [["type": "text", "text": msg.content]]
            ] as [String: Any]
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1_200,
            "system": system,
            "messages": apiMessages
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

    private static func callOpenAICompatible(
        apiKey: String,
        baseUrl: String,
        model: String,
        system: String,
        messages: [SubconsciousLLMMessage]
    ) async throws -> String {
        let normalizedBase = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        let url = URL(string: "\(normalizedBase)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": system]
        ]
        apiMessages.append(
            contentsOf: messages.map { msg in
                [
                    "role": msg.role == "assistant" ? "assistant" : "user",
                    "content": msg.content
                ] as [String: Any]
            }
        )

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "max_tokens": 1_200,
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

    private static func callGemini(
        apiKey: String,
        model: String,
        system: String,
        messages: [SubconsciousLLMMessage]
    ) async throws -> String {
        let modelPath = model.starts(with: "models/") ? model : "models/\(model)"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(modelPath):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let contents: [[String: Any]] = messages.map { msg in
            [
                "role": msg.role == "assistant" ? "model" : "user",
                "parts": [["text": msg.content]]
            ]
        }

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": system]]
            ],
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": 1_200,
                "temperature": 0.2
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

    private static func callMiniMax(
        apiKey: String,
        model: String,
        system: String,
        messages: [SubconsciousLLMMessage]
    ) async throws -> String {
        let url = URL(string: "https://api.minimax.io/v1/text/chatcompletion_v2")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = [[
            "sender_type": "BOT",
            "sender_name": "System",
            "text": system
        ]]

        apiMessages.append(
            contentsOf: messages.map { msg in
                [
                    "sender_type": msg.role == "assistant" ? "BOT" : "USER",
                    "sender_name": msg.role == "assistant" ? "Assistant" : "User",
                    "text": msg.content
                ]
            }
        )

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
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

// MARK: - Memory Errors

enum MemoryError: LocalizedError {
    case notFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Memory not found"
        case .invalidData:
            return "Invalid memory data"
        }
    }
}

// MARK: - Memory Stats Model

struct MemoryStats: Codable {
    let total: Int
    let byType: [String: Int]
    let averageConfidence: Double
    let recentCount: Int
}
