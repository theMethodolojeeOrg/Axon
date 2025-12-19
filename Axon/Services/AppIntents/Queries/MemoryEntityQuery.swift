//
//  MemoryEntityQuery.swift
//  Axon
//
//  EntityQuery for searching and retrieving memories via Siri/Shortcuts
//

import AppIntents
import Foundation

/// Query provider for MemoryAppEntity - enables searching memories via Siri/Shortcuts
struct MemoryEntityQuery: EntityQuery {

    // MARK: - Entity Lookup by ID

    /// Fetch specific memories by their IDs
    func entities(for identifiers: [String]) async throws -> [MemoryAppEntity] {
        let memoryService = await MemoryService.shared
        let memories = await memoryService.memories

        return identifiers.compactMap { id in
            memories.first { $0.id == id }?.toAppEntity()
        }
    }

    // MARK: - Suggested Entities

    /// Return recently accessed/created memories for Shortcuts suggestions
    func suggestedEntities() async throws -> [MemoryAppEntity] {
        let memoryService = await MemoryService.shared
        let memories = await memoryService.memories

        // Return top 10 by confidence and recency
        let sorted = memories
            .sorted { lhs, rhs in
                // Prioritize higher confidence, then more recent
                if abs(lhs.confidence - rhs.confidence) > 0.1 {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(10)

        return sorted.map { $0.toAppEntity() }
    }
}

// MARK: - String Search Query

extension MemoryEntityQuery: EntityStringQuery {

    /// Search memories by text query - enables "Find memories about X" in Shortcuts
    func entities(matching string: String) async throws -> [MemoryAppEntity] {
        let memoryService = await MemoryService.shared

        // Use the existing search functionality
        let results = try await memoryService.searchMemories(
            query: string,
            types: nil,
            limit: 20,
            minConfidence: nil
        )

        return results.map { $0.toAppEntity() }
    }
}
