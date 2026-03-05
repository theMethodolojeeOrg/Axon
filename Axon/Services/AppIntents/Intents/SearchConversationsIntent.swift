//
//  SearchConversationsIntent.swift
//  Axon
//
//  AppIntent to search conversations - "Search Axon for..."
//

import AppIntents
import Foundation

/// Intent to search Axon's conversations
/// Siri: "Search Axon for [query]"
struct SearchConversationsIntent: AppIntent {

    // MARK: - Metadata

    static var title: LocalizedStringResource = "Search Conversations"

    static var description = IntentDescription(
        "Search through your conversations in Axon",
        categoryName: "Conversations"
    )

    /// Runs in background - no need to open app
    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(
        title: "Search Query",
        description: "What to search for in conversations"
    )
    var query: String

    @Parameter(
        title: "Limit",
        description: "Maximum number of results",
        default: 5
    )
    var limit: Int

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        Summary("Search Axon conversations for \(\.$query)") {
            \.$limit
        }
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ConversationAppEntity]> {
        let localStore = LocalConversationStore.shared
        let conversations = localStore.loadConversations()

        let queryLower = query.lowercased()

        // Filter conversations by title, last message, or summary
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

        // Limit results and convert to entities
        let entities = filtered.prefix(limit).map { $0.toAppEntity() }

        return .result(value: Array(entities))
    }
}
