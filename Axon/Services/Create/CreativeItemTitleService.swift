//
//  CreativeItemTitleService.swift
//  Axon
//
//  Generates concise titles for creative items using Apple Intelligence Foundation Models.
//  Falls back to simple heuristics when AI is unavailable.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@Generable
struct CreativeItemDigest {
    @Guide(description: "A short 3-5 word title describing this content.")
    var title: String
}
#endif

/// Service for generating intelligent titles for creative gallery items.
///
/// Availability: iOS 18.4+, macOS 15.4+
@MainActor
final class CreativeItemTitleService {
    static let shared = CreativeItemTitleService()

    private init() {}

    // MARK: - Public API

    /// Generate a title for a creative item based on its prompt and type.
    /// - Parameters:
    ///   - prompt: The generation prompt used to create the item
    ///   - type: The type of creative item (photo, audio, video, artifact)
    /// - Returns: A short, descriptive title
    func generateTitle(prompt: String, type: CreativeItemType) async -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic guard
        guard !trimmedPrompt.isEmpty else {
            return defaultTitle(for: type)
        }

        // Try Apple Intelligence first
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                return try await generateWithFoundationModels(prompt: trimmedPrompt, type: type)
            } catch {
                print("[CreativeItemTitleService] AI generation failed: \(error), using fallback")
            }
        }

        // Fallback to simple heuristic
        return generateFallbackTitle(prompt: trimmedPrompt, type: type)
    }

    /// Generate a title for an audio item based on the text content.
    func generateAudioTitle(text: String) async -> String {
        await generateTitle(prompt: text, type: .audio)
    }

    /// Generate a title for an image based on the prompt.
    func generateImageTitle(prompt: String) async -> String {
        await generateTitle(prompt: prompt, type: .photo)
    }

    /// Generate a title for a video based on the prompt.
    func generateVideoTitle(prompt: String) async -> String {
        await generateTitle(prompt: prompt, type: .video)
    }

    // MARK: - Apple Intelligence

    @available(iOS 26.0, macOS 26.0, *)
    private func generateWithFoundationModels(prompt: String, type: CreativeItemType) async throws -> String {
        #if canImport(FoundationModels)
        let typeDescription: String
        switch type {
        case .photo: typeDescription = "image"
        case .audio: typeDescription = "audio/speech"
        case .video: typeDescription = "video"
        case .artifact: typeDescription = "code artifact"
        }

        // Truncate very long prompts to keep latency predictable
        let truncatedPrompt = String(prompt.prefix(500))

        let systemPrompt = """
        Create a short 3-5 word title for this \(typeDescription) based on its description.
        The title should be descriptive and capture the essence of the content.
        Do not use quotes or punctuation at the end.

        Description: \(truncatedPrompt)
        """

        let session = LanguageModelSession()
        let result = try await session.respond(to: systemPrompt, generating: CreativeItemDigest.self)

        return sanitizeTitle(result.content.title, type: type)
        #else
        throw TitleGenerationError.unavailable
        #endif
    }

    // MARK: - Fallback Heuristics

    private func generateFallbackTitle(prompt: String, type: CreativeItemType) -> String {
        // Extract key words from the prompt
        let words = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty && $0.count > 2 }
            .filter { !stopWords.contains($0.lowercased()) }
            .prefix(5)

        if words.isEmpty {
            return defaultTitle(for: type)
        }

        // Take first 3-4 meaningful words
        let titleWords = Array(words.prefix(4))
        var title = titleWords.joined(separator: " ")

        // Capitalize first letter
        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }

        return sanitizeTitle(title, type: type)
    }

    private func defaultTitle(for type: CreativeItemType) -> String {
        switch type {
        case .photo: return "Generated Image"
        case .audio: return "Generated Audio"
        case .video: return "Generated Video"
        case .artifact: return "Code Artifact"
        }
    }

    private func sanitizeTitle(_ raw: String, type: CreativeItemType) -> String {
        var trimmed = raw
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split into words and limit
        var words = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        if words.count > 5 {
            words = Array(words.prefix(5))
        }

        let joined = words.joined(separator: " ")
        if joined.isEmpty {
            return defaultTitle(for: type)
        }

        // Hard cap for UI safety
        let maxChars = 50
        if joined.count > maxChars {
            return String(joined.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return joined
    }

    // Common stop words to filter out
    private let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
        "be", "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "must", "shall", "can", "this",
        "that", "these", "those", "i", "you", "he", "she", "it", "we", "they",
        "me", "him", "her", "us", "them", "my", "your", "his", "its", "our",
        "their", "what", "which", "who", "whom", "when", "where", "why", "how",
        "all", "each", "every", "both", "few", "more", "most", "other", "some",
        "such", "no", "nor", "not", "only", "own", "same", "so", "than", "too",
        "very", "just", "also", "now", "here", "there", "then", "once"
    ]
}
