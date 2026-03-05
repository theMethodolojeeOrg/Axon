//
//  ConversationSummaryService.swift
//  Axon
//
//  Service for generating and storing compact conversation summaries
//  to provide continuity between conversations.
//
//  The summary is generated locally (no API call) when switching conversations
//  and injected into the system prompt at the start of the next conversation.
//

import Foundation
import Combine

@MainActor
class ConversationSummaryService: ObservableObject {
    static let shared = ConversationSummaryService()

    /// Key for storing last conversation summary in UserDefaults
    private let lastSummaryKey = "axon_last_conversation_summary"

    private init() {}

    // MARK: - Retrieve Summary

    /// Get the last conversation summary if it's recent enough
    /// - Parameter maxAgeHours: Maximum age of summary in hours (default 24)
    /// - Returns: The summary if found and recent, nil otherwise
    func getRecentSummary(maxAgeHours: Int = 24) -> ConversationSummary? {
        guard let data = UserDefaults.standard.data(forKey: lastSummaryKey) else {
            print("[ConversationSummaryService] No summary data found in UserDefaults")
            return nil
        }

        guard let summary = try? JSONDecoder().decode(ConversationSummary.self, from: data) else {
            print("[ConversationSummaryService] Failed to decode summary data")
            return nil
        }

        // Check if summary is recent enough
        let hoursSince = Date().timeIntervalSince(summary.timestamp) / 3600
        guard hoursSince < Double(maxAgeHours) else {
            print("[ConversationSummaryService] Summary too old (\(Int(hoursSince))h), skipping")
            return nil
        }

        print("[ConversationSummaryService] Found recent summary: '\(summary.title)' (\(summary.messageCount) msgs, \(Int(hoursSince))h ago)")
        return summary
    }

    // MARK: - Generate Summary

    /// Generate and store summary when conversation ends
    /// Called when switching conversations or backgrounding the app
    func generateSummary(
        messages: [Message],
        conversationId: String,
        conversationTitle: String
    ) async {
        // Need at least one exchange (2 messages) to summarize
        guard messages.count >= 2 else {
            print("[ConversationSummaryService] Not enough messages to summarize (\(messages.count))")
            return
        }

        // Build summary from messages (local extraction, no API call)
        let summary = extractSummary(from: messages, title: conversationTitle)
        let topicTags = extractTopics(from: messages)

        let conversationSummary = ConversationSummary(
            conversationId: conversationId,
            title: conversationTitle,
            summary: summary,
            topicTags: topicTags,
            messageCount: messages.count,
            timestamp: Date()
        )

        // Store to UserDefaults
        if let data = try? JSONEncoder().encode(conversationSummary) {
            UserDefaults.standard.set(data, forKey: lastSummaryKey)
            print("[ConversationSummaryService] Saved summary for '\(conversationTitle)' (\(messages.count) messages, \(topicTags.count) topics)")
        }
    }

    /// Clear the stored summary
    func clearSummary() {
        UserDefaults.standard.removeObject(forKey: lastSummaryKey)
    }

    // MARK: - Summary Extraction

    /// Extract ~200 word summary from messages
    private func extractSummary(from messages: [Message], title: String) -> String {
        var summaryParts: [String] = []

        // Get user messages
        let userMessages = messages.filter { $0.role == .user }
        let assistantMessages = messages.filter { $0.role == .assistant }

        // Key user questions (first few topics discussed)
        let keyQuestions = userMessages.prefix(3).map { message in
            let content = message.content
            let truncated = content.count > 100 ? String(content.prefix(100)) + "..." : content
            return "- \(truncated)"
        }

        // Get last exchange for recent context
        let lastUser = userMessages.last?.content ?? ""
        let lastUserTruncated = lastUser.count > 80 ? String(lastUser.prefix(80)) + "..." : lastUser

        let lastAssistant = assistantMessages.last?.content ?? ""
        let lastAssistantTruncated = lastAssistant.count > 150 ? String(lastAssistant.prefix(150)) + "..." : lastAssistant

        // Build summary
        summaryParts.append("Last conversation: \"\(title)\"")

        if !keyQuestions.isEmpty {
            summaryParts.append("Key topics discussed:")
            summaryParts.append(contentsOf: keyQuestions)
        }

        if !lastUserTruncated.isEmpty {
            summaryParts.append("Final exchange: User asked about \"\(lastUserTruncated)\"")
        }

        if !lastAssistantTruncated.isEmpty {
            summaryParts.append("Assistant: \"\(lastAssistantTruncated)\"")
        }

        return summaryParts.joined(separator: "\n")
    }

    /// Extract topic tags from messages using frequency analysis
    private func extractTopics(from messages: [Message]) -> [String] {
        // Combine all message content
        let allText = messages.map { $0.content }.joined(separator: " ").lowercased()

        // Extract significant words (basic NLP)
        let words = allText.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 5 }

        // Common stop words to exclude
        let stopWords: Set<String> = [
            "should", "would", "could", "about", "there", "their", "which",
            "these", "those", "being", "having", "doing", "going", "coming",
            "making", "taking", "getting", "putting", "seeing", "knowing",
            "thinking", "saying", "looking", "wanting", "giving", "using",
            "finding", "telling", "asking", "working", "trying", "calling",
            "needing", "feeling", "becoming", "leaving", "keeping", "letting",
            "beginning", "seeming", "helping", "showing", "hearing", "playing",
            "running", "moving", "living", "believing", "bringing", "happening"
        ]

        // Frequency analysis
        var freq: [String: Int] = [:]
        for word in words where !stopWords.contains(word) {
            freq[word, default: 0] += 1
        }

        // Top 5 most frequent meaningful words
        let topWords = freq
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }

        return topWords
    }
}

// MARK: - Conversation Summary Model

struct ConversationSummary: Codable {
    /// The ID of the conversation this summary is for
    let conversationId: String

    /// The title of the conversation
    let title: String

    /// The compact summary text (~200 words)
    let summary: String

    /// Extracted topic tags for similarity matching
    let topicTags: [String]

    /// Number of messages in the conversation
    let messageCount: Int

    /// When this summary was generated
    let timestamp: Date

    /// Format the summary for injection into system prompt
    /// Uses first-person framing for intrinsic memory feel
    func formattedForInjection() -> String {
        let relativeTime = formatRelativeTime(from: timestamp)
        return """

        ## From Our Last Conversation
        *\(relativeTime)*

        \(summary)

        """
    }

    /// Format timestamp as relative time (e.g., "2 hours ago", "yesterday")
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
