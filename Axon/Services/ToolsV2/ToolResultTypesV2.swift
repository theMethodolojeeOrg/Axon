//
//  ToolResultTypesV2.swift
//  Axon
//
//  Result types and errors for V2 tool execution.
//  Uses V2 suffix to enable parallel operation with V1 tool system.
//

import Foundation

// MARK: - Tool Result

/// Result from V2 tool execution
struct ToolResultV2: Sendable {
    /// The tool ID that produced this result
    let toolId: String
    
    /// Whether execution succeeded
    let success: Bool
    
    /// Human-readable output text
    let output: String
    
    /// Optional structured output for programmatic access
    let structuredOutput: [String: AnySendable]?
    
    /// Optional metadata about execution
    let metadata: ToolResultMetadataV2?
    
    /// Convert to V1 ToolResult for compatibility with existing code
    func toV1() -> ToolResult {
        ToolResult(
            tool: toolId,
            success: success,
            result: output,
            sources: nil,
            memoryOperation: nil
        )
    }
    
    // MARK: - Convenience Initializers
    
    /// Create a success result
    static func success(
        toolId: String,
        output: String,
        structured: [String: AnySendable]? = nil,
        metadata: ToolResultMetadataV2? = nil
    ) -> ToolResultV2 {
        ToolResultV2(
            toolId: toolId,
            success: true,
            output: output,
            structuredOutput: structured,
            metadata: metadata
        )
    }
    
    /// Create a failure result
    static func failure(
        toolId: String,
        error: String,
        metadata: ToolResultMetadataV2? = nil
    ) -> ToolResultV2 {
        ToolResultV2(
            toolId: toolId,
            success: false,
            output: error,
            structuredOutput: nil,
            metadata: metadata
        )
    }
}

// MARK: - Result Metadata

/// Metadata about tool execution
struct ToolResultMetadataV2: Sendable {
    /// Execution time in milliseconds
    let executionTimeMs: Int
    
    /// Which handler was used
    let handlerUsed: String
    
    /// Approval record if approval was required
    let approvalRecordId: String?
    
    /// Additional context-specific metadata
    let extra: [String: String]?
    
    init(
        executionTimeMs: Int,
        handlerUsed: String,
        approvalRecordId: String? = nil,
        extra: [String: String]? = nil
    ) {
        self.executionTimeMs = executionTimeMs
        self.handlerUsed = handlerUsed
        self.approvalRecordId = approvalRecordId
        self.extra = extra
    }
}

// MARK: - Errors

/// Errors specific to V2 tool execution
enum ToolExecutionErrorV2: LocalizedError, Equatable {
    case handlerNotFound(String)
    case manifestNotFound(String)
    case validationFailed([String])
    case executionFailed(String)
    case approvalDenied(String)
    case approvalTimeout
    case unsupportedExecutionType(String)
    case inputParsingFailed(String)
    case secretNotConfigured(String)
    case providerNotAvailable(String)
    
    var errorDescription: String? {
        switch self {
        case .handlerNotFound(let handlerId):
            return "No handler found for ID: \(handlerId)"
        case .manifestNotFound(let toolId):
            return "Tool manifest not found: \(toolId)"
        case .validationFailed(let errors):
            return "Validation failed: \(errors.joined(separator: ", "))"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        case .approvalDenied(let toolId):
            return "Approval denied for tool: \(toolId)"
        case .approvalTimeout:
            return "Approval request timed out"
        case .unsupportedExecutionType(let type):
            return "Unsupported execution type: \(type)"
        case .inputParsingFailed(let reason):
            return "Failed to parse inputs: \(reason)"
        case .secretNotConfigured(let key):
            return "Required secret not configured: \(key)"
        case .providerNotAvailable(let provider):
            return "Provider not available: \(provider)"
        }
    }
}

// MARK: - AnySendable Wrapper

/// Type-erased Sendable wrapper for structured output values
struct AnySendable: @unchecked Sendable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    // Type-safe accessors
    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
    var arrayValue: [Any]? { value as? [Any] }
    var dictionaryValue: [String: Any]? { value as? [String: Any] }
}

// MARK: - Batch Results

/// Container for multiple tool results (for batch execution)
struct ToolBatchResultV2: Sendable {
    let results: [ToolResultV2]
    let totalExecutionTimeMs: Int
    
    var allSucceeded: Bool {
        results.allSatisfy { $0.success }
    }
    
    var successCount: Int {
        results.filter { $0.success }.count
    }
    
    var failureCount: Int {
        results.filter { !$0.success }.count
    }
}
