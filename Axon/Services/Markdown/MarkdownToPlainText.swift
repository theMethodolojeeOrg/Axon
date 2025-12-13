//
//  MarkdownToPlainText.swift
//  Axon
//
//  Fast, non-LLM markdown → plain-text conversion for TTS.
//

import Foundation

/// Lightweight markdown-to-plain-text utilities.
///
/// Goal: produce readable text for speech synthesis while being fast, deterministic,
/// and offline (no LLM). This is *not* a fully-compliant Markdown parser.
enum MarkdownToPlainText {

    /// Convert markdown-ish text into readable plain text.
    ///
    /// - Keeps link text (drops URLs)
    /// - Removes emphasis markers, inline code ticks
    /// - Replaces list markers with bullets
    /// - Removes fenced code block markers (keeps contents)
    /// - Removes headings markers
    /// - Collapses excessive whitespace
    static func renderedPlainText(from input: String) -> String {
        var text = input

        // Normalize newlines
        text = text.replacingOccurrences(of: "\r\n", with: "\n")

        // Remove fenced code block delimiters ```lang and ```
        // Keep the content inside.
        text = text.replacingOccurrences(of: "(?m)^```.*$", with: "", options: .regularExpression)

        // Replace ATX headings (e.g., "### Title") -> "Title"
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)

        // Strip blockquote markers ("> ")
        text = text.replacingOccurrences(of: #"(?m)^\s*>\s?"#, with: "", options: .regularExpression)

        // Convert unordered list markers to bullet.
        // "- item" / "* item" / "+ item" -> "• item"
        text = text.replacingOccurrences(of: #"(?m)^\s*[-*+]\s+"#, with: "• ", options: .regularExpression)

        // Convert ordered list markers to a spoken-friendly numbering: "1. item" -> "1) item"
        text = text.replacingOccurrences(of: #"(?m)^(\s*)(\d+)\.\s+"#, with: "$1$2) ", options: .regularExpression)

        // Inline links: [label](url) -> label
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\(([^\)]+)\)"#, with: "$1", options: .regularExpression)

        // Reference-style links: [label][id] -> label
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\[[^\]]*\]"#, with: "$1", options: .regularExpression)

        // Images: ![alt](url) -> alt
        text = text.replacingOccurrences(of: #"!\[([^\]]*)\]\(([^\)]+)\)"#, with: "$1", options: .regularExpression)

        // Remove emphasis markers (best-effort): **bold**, *italic*, __bold__, _italic_
        // Do this after link removal to avoid eating link syntax.
        text = text.replacingOccurrences(of: #"(\*\*|__)(.*?)\1"#, with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(\*|_)(.*?)\1"#, with: "$2", options: .regularExpression)

        // Remove inline code ticks: `code` -> code
        text = text.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)

        // Remove horizontal rules
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}(-{3,}|\*{3,}|_{3,})\s*$"#, with: "", options: .regularExpression)

        // Remove leftover markdown table pipes (keep content spacing reasonable)
        text = text.replacingOccurrences(of: "|", with: " ")

        // Collapse 3+ newlines to 2 newlines
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        // Trim lines and collapse internal repeated spaces (but keep newlines)
        text = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let collapsed = trimmed.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
                return collapsed
            }
            .joined(separator: "\n")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Optional second-pass normalization to make TTS more natural.
    /// This is intentionally conservative (we still want it to match what the user sees).
    static func spokenFriendly(from plainText: String) -> String {
        var text = plainText

        // If the caller didn't strip markdown first, still try to avoid reading code fences.
        text = replaceFencedCodeBlocksForSpeech(in: text)

        // Expand some common symbols that are read awkwardly.
        text = text.replacingOccurrences(of: "->", with: " to ")
        text = text.replacingOccurrences(of: "=>", with: " to ")

        // Collapse excessive whitespace again.
        text = text.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Code blocks

    /// Replaces fenced code blocks (```lang ... ```) with a short spoken placeholder.
    /// This mirrors the behavior of some chat apps that avoid reading code aloud.
    private static func replaceFencedCodeBlocksForSpeech(in input: String) -> String {
        // Dot-matches-newlines:
        // - Group 1: optional language after ```
        // - Group 2: code contents (ignored)
        let pattern = #"(?s)```\s*([A-Za-z0-9_+-]+)?\s*\n(.*?)\n```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }

        let ns = input as NSString
        let matches = regex.matches(in: input, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }

        var out = input

        // Replace from the end so indices stay valid
        for match in matches.reversed() {
            let langRange = match.range(at: 1)
            let language: String?
            if langRange.location != NSNotFound {
                let raw = ns.substring(with: langRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                language = raw.isEmpty ? nil : raw
            } else {
                language = nil
            }

            let replacement: String
            if let language {
                replacement = "You can see the \(language) code in our conversation history."
            } else {
                replacement = "You can see the code in our conversation history."
            }

            out = (out as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return out
    }
}
