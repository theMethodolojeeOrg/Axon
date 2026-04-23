//
//  ConversationTitleNamerCore.swift
//  Axon
//
//  Core parsing + eligibility helpers for sub-agent driven conversation titling.
//

import Foundation

// MARK: - Namer Output Parsing

enum ConversationTitleNamerOutputParser {
    private static let maxWords = 6
    private static let minWords = 3
    private static let maxCharacters = 60

    private static let greetingWords: Set<String> = [
        "hello", "hi", "hey", "greetings", "yo", "sup", "thanks", "thank", "welcome"
    ]

    /// Strict parser for namer output.
    /// Expected format: `TITLE: <3-6 word title>`
    static func parseTitle(from raw: String) -> String? {
        let lines = raw.components(separatedBy: .newlines)

        guard let titleLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("title:") }) else {
            return nil
        }

        let remainder = titleLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .dropFirst("TITLE:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalized = sanitize(String(remainder))
        guard !normalized.isEmpty else { return nil }

        let words = normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard words.count >= minWords else { return nil }

        let clippedWords = Array(words.prefix(maxWords))
        let clipped = clippedWords.joined(separator: " ")

        guard !isGreetingOnly(clippedWords) else { return nil }

        if clipped.count > maxCharacters {
            return String(clipped.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return clipped
    }

    private static func sanitize(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return "" }

        let withoutSymbols = trimmed.replacingOccurrences(
            of: "[^\\p{L}\\p{N}\\-\\s]",
            with: " ",
            options: .regularExpression
        )

        return withoutSymbols
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isGreetingOnly(_ words: [String]) -> Bool {
        let lowered = words.map { $0.lowercased() }
        guard !lowered.isEmpty else { return true }
        return lowered.allSatisfy { greetingWords.contains($0) }
    }
}

// MARK: - Eligibility

enum ConversationTitleSkipReason: Equatable {
    case manualTitleExists
    case generatedTitleExists
    case privateThread
    case archived
    case noUserMessage
    case titleNotPlaceholder
}

enum ConversationTitleEligibilityDecision: Equatable {
    case eligible(firstUserMessage: Message)
    case skipped(ConversationTitleSkipReason)
}

enum ConversationTitleEligibility {
    static func evaluate(
        conversation: Conversation,
        messages: [Message],
        hasManualTitle: Bool,
        hasGeneratedTitle: Bool
    ) -> ConversationTitleEligibilityDecision {
        if hasManualTitle {
            return .skipped(.manualTitleExists)
        }

        if hasGeneratedTitle {
            return .skipped(.generatedTitleExists)
        }

        if conversation.isPrivate == true || UserDefaults.standard.bool(forKey: "private_thread_\(conversation.id)") {
            return .skipped(.privateThread)
        }

        if conversation.archived || SettingsStorage.shared.isConversationArchived(conversation.id) {
            return .skipped(.archived)
        }

        guard let firstUserMessage = messages.first(where: { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return .skipped(.noUserMessage)
        }

        guard isPlaceholderTitle(conversation.title, firstUserMessage: firstUserMessage.content) else {
            return .skipped(.titleNotPlaceholder)
        }

        return .eligible(firstUserMessage: firstUserMessage)
    }

    static func firstUserPrefix(from content: String) -> String {
        String(content.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPlaceholderTitle(_ title: String, firstUserMessage: String) -> Bool {
        if title == "New Chat" {
            return true
        }

        let prefix = firstUserPrefix(from: firstUserMessage)
        return normalize(title) == normalize(prefix)
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Catch-up Queue State

enum ConversationTitleCatchUpOutcome: String, Codable, Equatable {
    case success
    case skipped
    case failed
}

struct ConversationTitleCatchUpAttempt: Codable, Equatable {
    var attempts: Int
    var lastAttemptAt: Date
    var lastOutcome: ConversationTitleCatchUpOutcome
    var lastError: String?
}

struct ConversationTitleCatchUpRegistry {
    private(set) var queue: [String] = []
    private(set) var queuedIds: Set<String> = []
    private(set) var attempts: [String: ConversationTitleCatchUpAttempt]

    let failureCooldown: TimeInterval

    init(
        attempts: [String: ConversationTitleCatchUpAttempt] = [:],
        failureCooldown: TimeInterval = 12 * 60 * 60
    ) {
        self.attempts = attempts
        self.failureCooldown = failureCooldown
    }

    mutating func enqueue(_ conversationId: String) -> Bool {
        guard !queuedIds.contains(conversationId) else { return false }
        queue.append(conversationId)
        queuedIds.insert(conversationId)
        return true
    }

    mutating func dequeue() -> String? {
        guard !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        queuedIds.remove(next)
        return next
    }

    func canAttempt(_ conversationId: String, now: Date = Date()) -> Bool {
        guard let attempt = attempts[conversationId] else { return true }
        guard attempt.lastOutcome == .failed else { return true }
        return now.timeIntervalSince(attempt.lastAttemptAt) >= failureCooldown
    }

    mutating func record(
        _ conversationId: String,
        outcome: ConversationTitleCatchUpOutcome,
        error: String? = nil,
        now: Date = Date()
    ) {
        var state = attempts[conversationId] ?? ConversationTitleCatchUpAttempt(
            attempts: 0,
            lastAttemptAt: now,
            lastOutcome: outcome,
            lastError: nil
        )
        state.attempts += 1
        state.lastAttemptAt = now
        state.lastOutcome = outcome
        state.lastError = error
        attempts[conversationId] = state
    }
}
