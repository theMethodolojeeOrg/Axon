//
//  ConversationSearchService.swift
//  Axon
//
//  Service for searching recent conversations to provide historical context.
//  Includes automatic injection detection for queries that reference past conversations.
//

import Foundation
import Combine

@MainActor
class ConversationSearchService: ObservableObject {
    static let shared = ConversationSearchService()

    private let syncManager = ConversationSyncManager.shared

    private init() {}

    // MARK: - Search Conversations

    /// Search recent conversations for relevant context
    /// - Parameters:
    ///   - query: The search query
    ///   - limit: Maximum number of results (default 5)
    ///   - maxAgeDays: Maximum age of conversations to search (default 7)
    /// - Returns: Array of search results sorted by relevance
    func searchConversations(
        query: String,
        limit: Int = 5,
        maxAgeDays: Int = 7
    ) async -> [ConversationSearchResult] {
        // Get recent conversations from Core Data
        let allConversations = syncManager.loadLocalConversations()

        let recentConversations = allConversations.filter {
            let daysSince = Date().timeIntervalSince($0.updatedAt) / (24 * 3600)
            return daysSince <= Double(maxAgeDays)
        }

        // Limit to top 20 recent for performance
        let toSearch = Array(recentConversations.prefix(20))

        var results: [ConversationSearchResult] = []

        for conversation in toSearch {
            // Load messages for this conversation
            let messages = syncManager.loadLocalMessages(conversationId: conversation.id)

            // Skip empty conversations
            guard !messages.isEmpty else { continue }

            // Score relevance
            let score = calculateRelevance(query: query, conversation: conversation, messages: messages)

            // Only include if relevance is above threshold
            if score > 0.1 {
                // Extract relevant snippets
                let snippets = extractRelevantSnippets(query: query, messages: messages)

                results.append(ConversationSearchResult(
                    conversationId: conversation.id,
                    title: conversation.title,
                    relevanceScore: score,
                    snippets: snippets,
                    timestamp: conversation.updatedAt
                ))
            }
        }

        // Sort by relevance and return top results
        return results
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Auto-Injection Detection

    /// Check if query likely needs conversation history context
    /// Returns true if the query references past conversations
    func shouldAutoInject(query: String, conversationTags: [String]) -> Bool {
        let queryLower = query.lowercased()

        // Explicit triggers - phrases that clearly reference past conversations
        let explicitTriggers = [
            "we discussed",
            "we talked about",
            "you mentioned",
            "you said",
            "you told me",
            "last time",
            "before",
            "earlier",
            "previously",
            "remember when",
            "remember that",
            "what did we",
            "what did you",
            "did we",
            "did you say",
            "our conversation",
            "our discussion",
            "i told you",
            "i mentioned",
            "i said",
            "continue from",
            "continue where",
            "where were we",
            "as we discussed",
            "as you mentioned"
        ]

        if explicitTriggers.contains(where: { queryLower.contains($0) }) {
            return true
        }

        // Tag similarity check - if query mentions multiple topics from past conversations
        let queryWords = Set(
            queryLower.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
        )

        let tagOverlap = conversationTags.filter { tag in
            queryWords.contains(tag.lowercased())
        }

        // If 2+ topic tags match, likely referencing past context
        if tagOverlap.count >= 2 {
            return true
        }

        return false
    }

    // MARK: - Relevance Scoring

    private func calculateRelevance(
        query: String,
        conversation: Conversation,
        messages: [Message]
    ) -> Double {
        let queryWords = Set(
            query.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
        )

        guard !queryWords.isEmpty else { return 0.0 }

        var score: Double = 0.0

        // 1. Title match (weight: 0.3)
        let titleWords = Set(
            conversation.title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
        )
        let titleOverlap = Double(queryWords.intersection(titleWords).count) / Double(queryWords.count)
        score += titleOverlap * 0.3

        // 2. Message content match (weight: 0.5)
        let allContent = messages.map { $0.content }.joined(separator: " ").lowercased()
        var contentMatches = 0
        for word in queryWords {
            if allContent.contains(word) {
                contentMatches += 1
            }
        }
        let contentScore = Double(contentMatches) / Double(queryWords.count)
        score += contentScore * 0.5

        // 3. Recency boost (weight: 0.2)
        let daysSince = Date().timeIntervalSince(conversation.updatedAt) / (24 * 3600)
        let recencyScore: Double
        if daysSince < 1 {
            recencyScore = 1.0
        } else if daysSince < 3 {
            recencyScore = 0.7
        } else if daysSince < 7 {
            recencyScore = 0.4
        } else {
            recencyScore = 0.2
        }
        score += recencyScore * 0.2

        return min(score, 1.0)
    }

    // MARK: - Snippet Extraction

    private func extractRelevantSnippets(query: String, messages: [Message]) -> [String] {
        let queryWords = Set(
            query.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
        )

        var snippets: [String] = []

        // Prefer assistant messages for context
        for message in messages where message.role == .assistant {
            let content = message.content.lowercased()

            // Check if message contains query words
            if queryWords.contains(where: { content.contains($0) }) {
                // Extract a snippet (first 200 chars)
                let snippetContent = message.content
                let snippet = snippetContent.count > 200
                    ? String(snippetContent.prefix(200)) + "..."
                    : snippetContent

                snippets.append(snippet)

                // Limit to 3 snippets
                if snippets.count >= 3 { break }
            }
        }

        // If no assistant matches, try user messages
        if snippets.isEmpty {
            for message in messages where message.role == .user {
                let content = message.content.lowercased()
                if queryWords.contains(where: { content.contains($0) }) {
                    let snippetContent = message.content
                    let snippet = snippetContent.count > 200
                        ? String(snippetContent.prefix(200)) + "..."
                        : snippetContent
                    snippets.append(snippet)
                    if snippets.count >= 2 { break }
                }
            }
        }

        return snippets
    }
}

// MARK: - Search Result Model

struct ConversationSearchResult {
    /// The ID of the matching conversation
    let conversationId: String

    /// The title of the conversation
    let title: String

    /// Relevance score (0.0 - 1.0)
    let relevanceScore: Double

    /// Relevant text snippets from the conversation
    let snippets: [String]

    /// When the conversation was last updated
    let timestamp: Date

    /// Format the result for injection into system prompt
    func formattedForInjection() -> String {
        let relativeTime = formatRelativeTime(from: timestamp)
        var result = "### \(title) (\(relativeTime))\n"

        for snippet in snippets {
            result += "> \(snippet)\n"
        }

        return result
    }

    private func formatRelativeTime(from date: Date) -> String {
        let now = Date()
        let seconds = now.timeIntervalSince(date)

        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else {
            let days = Int(seconds / 86400)
            return days == 1 ? "yesterday" : "\(days) days ago"
        }
    }
}
