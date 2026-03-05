//
//  AppleIntelligenceChatTitleService.swift
//  Axon
//
//  Generates concise conversation titles using Apple Intelligence Foundation Models.
//  Used to rename chats after the assistant finishes its first response.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@Generable
struct ChatDigest {
    @Guide(description: "A short 3–6 word title for this conversation.")
    var title: String
}
#endif

/// Thin wrapper around Apple Intelligence / FoundationModels title generation.
///
/// Availability: iOS 18.4+, macOS 15.4+
@MainActor
final class AppleIntelligenceChatTitleService {
    static let shared = AppleIntelligenceChatTitleService()

    private init() {}

    // MARK: - Public API

    /// Generate a 3–6 word title from the most recent (user, assistant) messages.
    /// - Important: Callers should pass only the last 2 messages to keep latency predictable.
    func generateTitle(userMessage: Message, assistantMessage: Message) async throws -> String {
        let user = userMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistant = assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic guard rails to avoid wasting calls.
        guard !user.isEmpty, !assistant.isEmpty else {
            throw TitleGenerationError.insufficientContext
        }

        // NOTE: The FoundationModels module in this Xcode SDK is gated at iOS 26 / macOS 26.
        // Even though you want iOS 18.4+/macOS 15.4+ behavior, we must also respect the
        // SDK availability to compile cleanly.
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await generateWithFoundationModels(user: user, assistant: assistant)
        } else {
            throw TitleGenerationError.unavailable
        }
    }

    // MARK: - Private

    @available(iOS 26.0, macOS 26.0, *)
    private func generateWithFoundationModels(user: String, assistant: String) async throws -> String {
        #if canImport(FoundationModels)
        // Provide minimal context: last user + last assistant.
        // Keep it very short and deterministic.
        let prompt = """
        Create a short title for a chat based on the last two messages.

        User: \(user)

        Assistant: \(assistant)
        """

        let session = LanguageModelSession()
        let result = try await session.respond(to: prompt, generating: ChatDigest.self)

        return sanitizeTitle(result.content.title)
        #else
        throw TitleGenerationError.unavailable
        #endif
    }

    private func sanitizeTitle(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split into words; keep 3–6 words if possible.
        var words = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        if words.count > 6 {
            words = Array(words.prefix(6))
        }

        let joined = words.joined(separator: " ")
        if joined.isEmpty {
            return trimmed
        }

        // Hard cap as an extra UI safety measure.
        let maxChars = 60
        if joined.count > maxChars {
            return String(joined.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return joined
    }
}

enum TitleGenerationError: LocalizedError {
    case unavailable
    case insufficientContext

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Intelligence title generation unavailable on this OS/build."
        case .insufficientContext:
            return "Not enough context to generate a title."
        }
    }
}
