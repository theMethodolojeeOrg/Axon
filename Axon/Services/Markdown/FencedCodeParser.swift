//
//  FencedCodeParser.swift
//  Axon
//
//  Lightweight fenced-code parser for chat messages.
//  Goal: split markdown into alternating markdown and code segments so code blocks
//  can have ChatGPT/Claude-like UI (copy, language label, artifact expand).
//

import Foundation

enum MarkdownSegment: Identifiable, Equatable {
    case markdown(String)
    case code(language: String?, code: String)

    var id: String {
        switch self {
        case .markdown(let s):
            return "md_\(s.hashValue)"
        case .code(let lang, let code):
            return "code_\((lang ?? "").hashValue)_\(code.hashValue)"
        }
    }
}

enum FencedCodeParser {
    /// Splits markdown string into segments:
    /// - markdown blocks (everything outside fences)
    /// - code blocks inside ``` fences with optional language on opening fence
    ///
    /// This is best-effort and intentionally lightweight.
    static func split(_ input: String) -> [MarkdownSegment] {
        // Dot matches newlines.
        // Group 1: optional language after ```
        // Group 2: code
        let pattern = #"(?s)```\s*([A-Za-z0-9_+\-\.]*)\s*\n(.*?)\n```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.markdown(input)]
        }

        let ns = input as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: input, options: [], range: range)
        guard !matches.isEmpty else {
            return [.markdown(input)]
        }

        var segments: [MarkdownSegment] = []
        var cursor = 0

        for match in matches {
            let full = match.range(at: 0)
            guard full.location != NSNotFound else { continue }

            // Leading markdown
            if full.location > cursor {
                let mdRange = NSRange(location: cursor, length: full.location - cursor)
                let md = ns.substring(with: mdRange)
                if !md.isEmpty {
                    segments.append(.markdown(md))
                }
            }

            let langRange = match.range(at: 1)
            let codeRange = match.range(at: 2)

            let rawLang = (langRange.location != NSNotFound) ? ns.substring(with: langRange) : ""
            let language = rawLang.trimmingCharacters(in: .whitespacesAndNewlines)
            let langValue: String? = language.isEmpty ? nil : language

            let code = (codeRange.location != NSNotFound) ? ns.substring(with: codeRange) : ""
            segments.append(.code(language: langValue, code: code))

            cursor = full.location + full.length
        }

        // Trailing markdown
        if cursor < ns.length {
            let md = ns.substring(from: cursor)
            if !md.isEmpty {
                segments.append(.markdown(md))
            }
        }

        // Cleanup: drop empty markdown blocks
        return segments.compactMap { seg in
            switch seg {
            case .markdown(let s):
                return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .markdown(s)
            case .code:
                return seg
            }
        }
    }
}
