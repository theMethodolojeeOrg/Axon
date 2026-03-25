//
//  ToolHandlerProtocolV2.swift
//  Axon
//
//  Protocol and context types for V2 tool handlers.
//  Uses V2 suffix to enable parallel operation with V1 tool system.
//

import Foundation

// MARK: - Handler Protocol

/// Protocol for V2 tool handlers
///
/// All tool handlers in the plugin system implement this protocol.
/// The `handlerId` must match the "handler" field in tool.json manifests.
protocol ToolHandlerV2 {
    /// Unique handler identifier (matches tool.json "handler" field)
    var handlerId: String { get }
    
    /// Execute the tool with parsed inputs
    /// - Parameters:
    ///   - inputs: Parsed input dictionary from tool request
    ///   - manifest: The tool manifest defining this tool
    ///   - context: Execution context with conversation info, approvals, etc.
    /// - Returns: Tool execution result
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2
    
    /// Validate inputs before execution
    /// - Parameters:
    ///   - inputs: Parsed input dictionary
    ///   - manifest: The tool manifest
    /// - Returns: Array of validation error messages (empty if valid)
    func validateInputs(_ inputs: [String: Any], manifest: ToolManifest) -> [String]
}

// MARK: - Default Implementation

extension ToolHandlerV2 {
    /// Default validation - checks required parameters
    func validateInputs(_ inputs: [String: Any], manifest: ToolManifest) -> [String] {
        var errors: [String] = []
        
        for (paramName, param) in manifest.parameters ?? [:] {
            let isRequired = param.required ?? false
            
            if isRequired && inputs[paramName] == nil {
                errors.append("Missing required parameter: \(paramName)")
            }
        }
        
        return errors
    }
}

// MARK: - Execution Context

/// Context passed to handlers during execution
struct ToolContextV2: Sendable {
    /// Current conversation ID (if in a conversation)
    let conversationId: String?
    
    /// Current message ID being processed
    let messageId: String?
    
    /// User identifier (for multi-user scenarios)
    let userId: String?
    
    /// Tools already approved this session (Claude Code style)
    let sessionApprovals: [String: Any]
    
    /// Pre-loaded secrets for this execution
    let secrets: [String: String]
    
    /// Creation timestamp
    let timestamp: Date
    
    /// Runtime provider name (actual provider serving current response)
    /// This is the live value, not from settings - enables accurate self-introspection
    let runtimeProvider: String?
    
    /// Runtime model ID (actual model serving current response)
    /// This is the live value, not from settings - enables accurate self-introspection
    let runtimeModel: String?
    
    init(
        conversationId: String? = nil,
        messageId: String? = nil,
        userId: String? = nil,
        sessionApprovals: [String: Any] = [:],
        secrets: [String: String] = [:],
        runtimeProvider: String? = nil,
        runtimeModel: String? = nil
    ) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.userId = userId
        self.sessionApprovals = sessionApprovals
        self.secrets = secrets
        self.timestamp = Date()
        self.runtimeProvider = runtimeProvider
        self.runtimeModel = runtimeModel
    }
    
    /// Empty context for testing
    static let empty = ToolContextV2()
}

// MARK: - Base Handler Class

/// Optional base class for handlers that provides common functionality
@MainActor
class BaseToolHandlerV2: ToolHandlerV2 {
    let handlerId: String
    
    init(handlerId: String) {
        self.handlerId = handlerId
    }
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        // Subclasses must override
        throw ToolExecutionErrorV2.executionFailed("Handler '\(handlerId)' must override executeV2")
    }
    
    func validateInputs(_ inputs: [String: Any], manifest: ToolManifest) -> [String] {
        // Default implementation checks required params
        var errors: [String] = []
        
        for (paramName, param) in manifest.parameters ?? [:] {
            if param.required == true && inputs[paramName] == nil {
                errors.append("Missing required parameter: \(paramName)")
            }
        }
        
        return errors
    }
    
    // MARK: - Helpers for Subclasses
    
    /// Extract a string value from inputs
    func stringValue(_ key: String, from inputs: [String: Any]) -> String? {
        inputs[key] as? String
    }
    
    /// Extract an integer value from inputs
    func intValue(_ key: String, from inputs: [String: Any]) -> Int? {
        if let int = inputs[key] as? Int {
            return int
        }
        if let string = inputs[key] as? String, let int = Int(string) {
            return int
        }
        return nil
    }
    
    /// Extract a double value from inputs
    func doubleValue(_ key: String, from inputs: [String: Any]) -> Double? {
        if let double = inputs[key] as? Double {
            return double
        }
        if let int = inputs[key] as? Int {
            return Double(int)
        }
        if let string = inputs[key] as? String, let double = Double(string) {
            return double
        }
        return nil
    }
    
    /// Extract a boolean value from inputs
    func boolValue(_ key: String, from inputs: [String: Any]) -> Bool? {
        if let bool = inputs[key] as? Bool {
            return bool
        }
        if let string = inputs[key] as? String {
            return string.lowercased() == "true" || string == "1"
        }
        return nil
    }
    
    /// Create a success result
    func successResult(
        toolId: String,
        output: String,
        structured: [String: Any]? = nil
    ) -> ToolResultV2 {
        ToolResultV2(
            toolId: toolId,
            success: true,
            output: output,
            structuredOutput: structured,
            metadata: nil
        )
    }
    
    /// Create a failure result
    func failureResult(
        toolId: String,
        error: String
    ) -> ToolResultV2 {
        ToolResultV2(
            toolId: toolId,
            success: false,
            output: error,
            structuredOutput: nil,
            metadata: nil
        )
    }
}

// MARK: - Shared V2 Input Normalization

/// Shared parser/normalizer for V2 handlers that accept tag-like string arrays.
enum ToolInputNormalizationV2 {
    /// Parse tag-like input from [String], [Any], CSV string, or JSON-array string.
    /// Output is normalized to lowercase/trimmed values with leading # removed.
    static func parseNormalizedStringArray(_ value: Any?) -> [String] {
        let rawValues = parseRawStringValues(from: value)
        return dedupePreservingOrder(rawValues.compactMap(normalizeTag))
    }

    /// Normalize a single tag-like value.
    static func normalizeTag(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasPrefix("#") {
            value.removeFirst()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Heuristic check for temporal tags (relative labels + year tags).
    static func isTemporalLikeTag(_ value: String) -> Bool {
        guard let normalized = normalizeTag(value) else { return false }
        if temporalLikeTags.contains(normalized) {
            return true
        }
        if let year = Int(normalized), (1900...2100).contains(year) {
            return true
        }
        return false
    }

    /// Generate simple semantic tags from content when explicit non-temporal tags are absent.
    /// Returns at most `maxCount` normalized tags.
    static func generateSemanticTags(
        from content: String,
        maxCount: Int = 4,
        excluding existingValues: [String] = []
    ) -> [String] {
        guard maxCount > 0 else { return [] }

        let excluded = Set(parseNormalizedStringArray(existingValues))
        let tokens = content
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        var frequencies: [String: Int] = [:]
        for token in tokens {
            guard token.count >= 3 && token.count <= 32 else { continue }
            guard Int(token) == nil else { continue }
            guard !semanticStopWords.contains(token) else { continue }
            guard !temporalNoiseWords.contains(token) else { continue }
            frequencies[token, default: 0] += 1
        }

        let sorted = frequencies.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return lhs.key < rhs.key
        }

        var suggestions: [String] = []
        for (candidate, _) in sorted {
            guard !excluded.contains(candidate) else { continue }
            suggestions.append(candidate)
            if suggestions.count >= maxCount {
                break
            }
        }

        return suggestions
    }

    // MARK: - Internals

    private static func parseRawStringValues(from value: Any?) -> [String] {
        guard let value else { return [] }

        if let stringValue = value as? String {
            return parseStringValue(stringValue)
        }

        if let stringArray = value as? [String] {
            return stringArray.flatMap(parseStringValue)
        }

        if let anyArray = value as? [Any] {
            return anyArray.flatMap(parseRawStringValues(from:))
        }

        return parseStringValue(String(describing: value))
    }

    private static func parseStringValue(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("["),
           trimmed.hasSuffix("]"),
           let data = trimmed.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return parseRawStringValues(from: jsonArray)
        }

        return trimmed
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func dedupePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            ordered.append(value)
        }
        return ordered
    }

    private static let temporalLikeTags: Set<String> = [
        "today", "yesterday", "tomorrow",
        "this_week", "this_month", "recent_months", "older",
        "spring", "summer", "fall", "autumn", "winter",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]

    private static let temporalNoiseWords: Set<String> = [
        "today", "yesterday", "tomorrow",
        "week", "weeks", "month", "months", "year", "years",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "spring", "summer", "fall", "autumn", "winter"
    ]

    private static let semanticStopWords: Set<String> = [
        "about", "above", "after", "again", "against", "also", "always", "among", "around",
        "because", "before", "being", "below", "between", "both", "could", "doing", "during",
        "each", "either", "else", "ever", "from", "have", "having", "here", "hers", "himself",
        "into", "itself", "just", "like", "make", "many", "maybe", "might", "more", "most",
        "much", "must", "need", "needed", "never", "only", "other", "ours", "ourselves",
        "over", "please", "really", "same", "should", "since", "some", "such", "than", "that",
        "their", "theirs", "them", "themselves", "then", "there", "these", "they", "this",
        "those", "through", "under", "until", "very", "want", "wants", "what", "when",
        "where", "which", "while", "with", "would", "your", "yours", "yourself", "yourselves",
        "user", "users", "assistant", "axon"
    ]
}
