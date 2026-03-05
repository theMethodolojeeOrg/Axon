//
//  ConversationEntityQuery.swift
//  Axon
//
//  EntityQuery for searching and retrieving conversations via Siri/Shortcuts
//

import AppIntents
import Foundation

/// Query provider for ConversationAppEntity - enables searching conversations via Siri/Shortcuts
struct ConversationEntityQuery: EntityQuery {

    // MARK: - Entity Lookup by ID

    /// Fetch specific conversations by their IDs
    func entities(for identifiers: [String]) async throws -> [ConversationAppEntity] {
        let localStore = await LocalConversationStore.shared
        let conversations = await localStore.loadConversations()

        return identifiers.compactMap { id in
            conversations.first { $0.id == id }?.toAppEntity()
        }
    }

    // MARK: - Suggested Entities

    /// Return recent conversations for Shortcuts suggestions
    func suggestedEntities() async throws -> [ConversationAppEntity] {
        let localStore = await LocalConversationStore.shared
        let conversations = await localStore.loadConversations()

        // Return top 10 most recent (already sorted by updatedAt)
        return conversations.prefix(10).map { $0.toAppEntity() }
    }
}

// MARK: - String Search Query

extension ConversationEntityQuery: EntityStringQuery {

    /// Search conversations by text query - enables "Find conversations about X" in Shortcuts
    func entities(matching string: String) async throws -> [ConversationAppEntity] {
        let localStore = await LocalConversationStore.shared
        let conversations = await localStore.loadConversations()

        let queryLower = string.lowercased()

        // Filter by title or last message content
        let filtered = conversations.filter { conv in
            // Check title
            if conv.title.lowercased().contains(queryLower) {
                return true
            }
            // Check last message preview
            if let lastMsg = conv.lastMessage, lastMsg.lowercased().contains(queryLower) {
                return true
            }
            // Check summary if available
            if let summary = conv.summary, summary.lowercased().contains(queryLower) {
                return true
            }
            return false
        }

        return filtered.prefix(20).map { $0.toAppEntity() }
    }
}
