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
    
    init(
        conversationId: String? = nil,
        messageId: String? = nil,
        userId: String? = nil,
        sessionApprovals: [String: Any] = [:],
        secrets: [String: String] = [:]
    ) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.userId = userId
        self.sessionApprovals = sessionApprovals
        self.secrets = secrets
        self.timestamp = Date()
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
