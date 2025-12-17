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

    private init() {
        // Load memories from local Core Data immediately (instant UI)
        loadLocalMemories()
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

