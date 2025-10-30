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
            let memory: Memory = try await apiClient.post("/api/memory", body: request)
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

        var endpoint = "/api/memories?limit=\(limit)&offset=\(offset)"
        if let type = type {
            endpoint += "&type=\(type.rawValue)"
        }

        do {
            let response: MemoryListResponse = try await apiClient.get(endpoint)
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
            return try await apiClient.get("/api/memory/\(id)")
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
            let content: String?
            let confidence: Double?
            let tags: [String]?
        }

        let request = UpdateMemoryRequest(
            content: content,
            confidence: confidence,
            tags: tags
        )

        do {
            let memory: Memory = try await apiClient.put("/api/memory/\(id)", body: request)

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
        struct EmptyResponse: Decodable {}

        do {
            let _: EmptyResponse = try await apiClient.delete("/api/memory/\(id)")
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
            let response: MemoryListResponse = try await apiClient.post(
                "/api/memories/search",
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
        struct RelevantMemoriesResponse: Decodable {
            let memories: [Memory]
        }

        do {
            let response: RelevantMemoriesResponse = try await apiClient.get(
                "/api/conversations/\(conversationId)/relevant-memories?limit=\(limit)"
            )
            return response.memories
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Memory Analytics

    func getMemoryStats() async throws -> MemoryStats {
        do {
            return try await apiClient.get("/api/memories/stats")
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
