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

    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var error: String?

    private init() {
        // Load memories from local Core Data immediately (instant UI)
        loadLocalMemories()
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

    // MARK: - Create Memory

    func createMemory(
        content: String,
        type: MemoryType,
        confidence: Double,
        tags: [String] = [],
        context: String? = nil,
        metadata: [String: AnyCodable] = [:]
    ) async throws -> Memory {
        isLoading = true
        defer { isLoading = false }

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
            tags: tags,
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

    // MARK: - Update Memory

    func updateMemory(
        id: String,
        content: String? = nil,
        confidence: Double? = nil,
        tags: [String]? = nil,
        context: String? = nil,
        metadata: [String: AnyCodable]? = nil
    ) async throws -> Memory {
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
            if let index = memories.firstIndex(where: { $0.id == id }) {
                memories[index] = memory
            }

            return memory
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Delete Memory

    func deleteMemory(id: String) async throws {
        struct DeleteResponse: Decodable {
            let success: Bool
        }

        do {
            let _: DeleteResponse = try await apiClient.request(
                endpoint: "/apiDeleteMemory/\(id)",
                method: .delete
            )

            // Delete from Core Data
            try await syncManager.deleteMemoryFromCoreData(id: id)

            // Remove from in-memory array
            memories.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
            throw error
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
    }

    // MARK: - Get Relevant Memories

    func getRelevantMemories(conversationId: String, limit: Int = 5) async throws -> [Memory] {
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
    }

    // MARK: - Memory Analytics

    func getMemoryStats() async throws -> MemoryStats {
        do {
            return try await apiClient.requestWrapped(
                endpoint: "/apiMemoryAnalytics",
                method: .get
            )
        } catch {
            self.error = error.localizedDescription
            throw error
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

