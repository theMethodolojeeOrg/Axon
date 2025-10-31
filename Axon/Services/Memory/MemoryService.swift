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

    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    // MARK: - Create Memory

    func createMemory(
        content: String,
        type: MemoryType,
        confidence: Double,
        tags: [String] = [],
        metadata: [String: AnyCodable] = [:]
    ) async throws -> Memory {
        isLoading = true
        defer { isLoading = false }

        struct CreateMemoryRequest: Encodable {
            let content: String
            let type: String
            let confidence: Double
            let tags: [String]
            let metadata: [String: AnyCodable]
        }

        let request = CreateMemoryRequest(
            content: content,
            type: type.rawValue,
            confidence: confidence,
            tags: tags,
            metadata: metadata
        )

        do {
            let memory: Memory = try await apiClient.requestWrapped(
                endpoint: "/apiCreateMemory",
                method: .post,
                body: request
            )
            memories.insert(memory, at: 0)
            return memory
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Get Memories

    func getMemories(limit: Int = 50, offset: Int = 0, type: MemoryType? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        var endpoint = "/apiGetMemories?limit=\(limit)&offset=\(offset)"
        if let type = type {
            endpoint += "&type=\(type.rawValue)"
        }

        do {
            let response: MemoryListResponse = try await apiClient.requestWrapped(
                endpoint: endpoint,
                method: .get
            )
            self.memories = response.memories
        } catch {
            self.error = error.localizedDescription
            throw error
        }
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
        tags: [String]? = nil
    ) async throws -> Memory {
        struct UpdateMemoryRequest: Encodable {
            let memoryId: String
            let content: String?
            let confidence: Double?
            let tags: [String]?
        }

        let request = UpdateMemoryRequest(
            memoryId: id,
            content: content,
            confidence: confidence,
            tags: tags
        )

        do {
            let memory: Memory = try await apiClient.requestWrapped(
                endpoint: "/apiUpdateMemory",
                method: .post,
                body: request
            )

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
        struct DeleteMemoryRequest: Encodable {
            let memoryId: String
        }

        struct EmptyResponse: Decodable {}

        let request = DeleteMemoryRequest(memoryId: id)

        do {
            let _: EmptyResponse = try await apiClient.requestWrapped(
                endpoint: "/apiDeleteMemory",
                method: .post,
                body: request
            )
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

