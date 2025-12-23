//
//  ToolExecutionRouterV2.swift
//  Axon
//
//  Main router for V2 tool execution. Routes to appropriate handler based on execution type.
//  Uses V2 suffix to enable parallel operation with V1 tool system.
//

import Foundation
import Combine
import os.log

// MARK: - Execution Router

/// Main router for V2 tool execution
///
/// Handles the full tool execution lifecycle:
/// 1. Find tool manifest
/// 2. Parse inputs
/// 3. Check approvals
/// 4. Route to appropriate execution strategy
@MainActor
final class ToolExecutionRouterV2: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ToolExecutionRouterV2()
    
    // MARK: - Dependencies
    
    private let pluginLoader = ToolPluginLoader.shared
    private let handlerRegistry = InternalHandlerRegistryV2.shared
    private let approvalBridge = ToolApprovalBridgeV2.shared
    private let sovereigntyBridge = ToolSovereigntyBridgeV2.shared
    private let dynamicEngine = DynamicToolExecutionEngine.shared
    
    // MARK: - Properties
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ToolExecutionRouterV2"
    )
    
    @Published private(set) var isExecuting = false
    @Published private(set) var currentToolId: String?
    @Published private(set) var lastError: ToolExecutionErrorV2?
    
    // MARK: - Initialization
    
    private init() {
        logger.debug("ToolExecutionRouterV2 initialized")
    }
    
    // MARK: - Public API
    
    /// Execute a V2 tool by ID
    /// - Parameters:
    ///   - toolId: The tool ID to execute
    ///   - rawInput: Raw input string (will be parsed based on inputFormat)
    ///   - context: Execution context
    /// - Returns: Tool execution result
    func executeToolV2(
        toolId: String,
        rawInput: String,
        context: ToolContextV2 = .empty
    ) async throws -> ToolResultV2 {
        let startTime = Date()
        
        isExecuting = true
        currentToolId = toolId
        lastError = nil
        
        defer {
            isExecuting = false
            currentToolId = nil
        }
        
        logger.info("Executing V2 tool: \(toolId)")
        
        // 1. Find loaded tool
        guard let loadedTool = pluginLoader.loadedTools.first(where: { $0.id == toolId }) else {
            let error = ToolExecutionErrorV2.manifestNotFound(toolId)
            lastError = error
            throw error
        }
        
        // 2. Check if enabled
        guard loadedTool.isEnabled else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Tool '\(toolId)' is not enabled"
            )
        }
        
        // 3. Parse inputs based on inputFormat
        let inputs: [String: Any]
        do {
            inputs = try parseInputsV2(rawInput, manifest: loadedTool.manifest)
        } catch let error as ToolExecutionErrorV2 {
            lastError = error
            throw error
        }
        
        // 4. Validate inputs
        let validationErrors = validateInputsV2(inputs, manifest: loadedTool.manifest)
        if !validationErrors.isEmpty {
            let error = ToolExecutionErrorV2.validationFailed(validationErrors)
            lastError = error
            throw error
        }
        
        // 5. Check sovereignty and approval requirements
        let sovereigntyCheck = sovereigntyBridge.isExecutionBlocked(manifest: loadedTool.manifest)
        if sovereigntyCheck.blocked {
            return ToolResultV2.failure(
                toolId: toolId,
                error: sovereigntyCheck.reason ?? "Execution blocked by sovereignty"
            )
        }
        
        if approvalBridge.requiresApproval(manifest: loadedTool.manifest) {
            let approvalResult = await approvalBridge.requestApproval(
                manifest: loadedTool.manifest,
                inputs: inputs
            )
            if !approvalResult.isApprovedV2 {
                let error = ToolExecutionErrorV2.approvalDenied(toolId)
                lastError = error
                throw error
            }
        }
        
        // 6. Route to appropriate execution strategy
        let result = try await routeExecutionV2(
            loadedTool: loadedTool,
            inputs: inputs,
            context: context
        )
        
        let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
        logger.info("Tool \(toolId) completed in \(executionTimeMs)ms")
        
        return result
    }
    
    /// Execute multiple tools in sequence
    func executeBatchV2(
        toolRequests: [(toolId: String, rawInput: String)],
        context: ToolContextV2 = .empty
    ) async -> ToolBatchResultV2 {
        let startTime = Date()
        var results: [ToolResultV2] = []
        
        for (toolId, rawInput) in toolRequests {
            do {
                let result = try await executeToolV2(
                    toolId: toolId,
                    rawInput: rawInput,
                    context: context
                )
                results.append(result)
            } catch {
                results.append(ToolResultV2.failure(
                    toolId: toolId,
                    error: error.localizedDescription
                ))
            }
        }
        
        let totalTime = Int(Date().timeIntervalSince(startTime) * 1000)
        return ToolBatchResultV2(results: results, totalExecutionTimeMs: totalTime)
    }
    
    // MARK: - Input Parsing
    
    /// Parse raw input string based on manifest's inputFormat
    private func parseInputsV2(
        _ rawInput: String,
        manifest: ToolManifest
    ) throws -> [String: Any] {
        let style = manifest.inputFormat?.style ?? .json
        
        switch style {
        case .pipeDelimited:
            return try parsePipeDelimitedV2(rawInput, manifest: manifest)
        case .json:
            return try parseJSONInputV2(rawInput)
        case .freeform, .positional:
            return ["query": rawInput]
        case .keyValue:
            return try parseKeyValueV2(rawInput)
        }
    }
    
    /// Parse pipe-delimited format: "value1|value2|value3"
    private func parsePipeDelimitedV2(
        _ input: String,
        manifest: ToolManifest
    ) throws -> [String: Any] {
        let delimiter = manifest.inputFormat?.delimiter ?? "|"
        let parts = input.components(separatedBy: delimiter)
        
        guard let fields = manifest.inputFormat?.fields else {
            throw ToolExecutionErrorV2.inputParsingFailed(
                "Pipe-delimited format requires 'fields' in inputFormat"
            )
        }
        
        var result: [String: Any] = [:]
        
        for (index, field) in fields.enumerated() {
            if index < parts.count {
                let value = parts[index].trimmingCharacters(in: .whitespaces)
                result[field] = convertValueV2(value, forParam: field, in: manifest)
            }
        }
        
        return result
    }
    
    /// Parse JSON input
    private func parseJSONInputV2(_ input: String) throws -> [String: Any] {
        guard let data = input.data(using: .utf8) else {
            throw ToolExecutionErrorV2.inputParsingFailed("Invalid UTF-8 string")
        }
        
        do {
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return dict
            } else {
                throw ToolExecutionErrorV2.inputParsingFailed("Expected JSON object")
            }
        } catch {
            throw ToolExecutionErrorV2.inputParsingFailed(error.localizedDescription)
        }
    }
    
    /// Parse key=value format
    private func parseKeyValueV2(_ input: String) throws -> [String: Any] {
        var result: [String: Any] = [:]
        
        let pairs = input.components(separatedBy: "&")
        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        
        return result
    }
    
    /// Convert string value to appropriate type based on parameter definition
    private func convertValueV2(
        _ value: String,
        forParam paramName: String,
        in manifest: ToolManifest
    ) -> Any {
        guard let param = manifest.parameters?[paramName] else {
            return value
        }
        
        switch param.type {
        case .integer:
            return Int(value) ?? value
        case .number:
            return Double(value) ?? value
        case .boolean:
            return value.lowercased() == "true" || value == "1"
        case .array:
            // Try JSON array or comma-separated
            if let data = value.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return array
            }
            return value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        default:
            return value
        }
    }
    
    // MARK: - Validation
    
    /// Validate inputs against manifest parameter definitions
    private func validateInputsV2(
        _ inputs: [String: Any],
        manifest: ToolManifest
    ) -> [String] {
        var errors: [String] = []
        
        guard let params = manifest.parameters else {
            return errors
        }
        
        for (paramName, param) in params {
            let value = inputs[paramName]
            
            // Check required
            if param.required == true && value == nil {
                errors.append("Missing required parameter: \(paramName)")
                continue
            }
            
            // Skip further validation if value is nil and not required
            guard let value = value else { continue }
            
            // Type-specific validation
            if let stringValue = value as? String {
                // Min length
                if let minLen = param.minLength, stringValue.count < minLen {
                    errors.append("\(paramName): minimum length is \(minLen)")
                }
                // Max length
                if let maxLen = param.maxLength, stringValue.count > maxLen {
                    errors.append("\(paramName): maximum length is \(maxLen)")
                }
                // Enum validation
                if let enumValues = param.enum, !enumValues.contains(stringValue) {
                    errors.append("\(paramName): must be one of: \(enumValues.joined(separator: ", "))")
                }
            }
            
            if let numValue = value as? Double {
                // Min/max
                if let min = param.minimum, numValue < min {
                    errors.append("\(paramName): minimum value is \(min)")
                }
                if let max = param.maximum, numValue > max {
                    errors.append("\(paramName): maximum value is \(max)")
                }
            }
        }
        
        return errors
    }
    
    // MARK: - Approval (delegated to bridges)
    //
    // Approval and sovereignty checks are now handled by:
    // - ToolApprovalBridgeV2: Biometric authentication and session tracking
    // - ToolSovereigntyBridgeV2: Trust tier permissions and covenant checks
    //
    // See checkApprovalV2 logic in executeToolV2() above.
    
    // MARK: - Execution Routing
    
    /// Route execution to appropriate handler based on execution type
    private func routeExecutionV2(
        loadedTool: LoadedTool,
        inputs: [String: Any],
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let executionType = loadedTool.manifest.execution.type
        
        switch executionType {
        case .internalHandler:
            return try await executeInternalHandlerV2(
                loadedTool: loadedTool,
                inputs: inputs,
                context: context
            )
            
        case .pipeline:
            return try await executePipelineV2(
                loadedTool: loadedTool,
                inputs: inputs
            )
            
        case .providerNative:
            return try await executeProviderNativeV2(
                loadedTool: loadedTool,
                inputs: inputs
            )
            
        case .urlScheme:
            return try await executeURLSchemeV2(
                loadedTool: loadedTool,
                inputs: inputs
            )
            
        case .shortcut:
            return try await executeShortcutV2(
                loadedTool: loadedTool,
                inputs: inputs
            )
            
        case .bridge:
            return try await executeBridgeV2(
                loadedTool: loadedTool,
                inputs: inputs,
                context: context
            )
        }
    }
    
    // MARK: - Internal Handler Execution
    
    private func executeInternalHandlerV2(
        loadedTool: LoadedTool,
        inputs: [String: Any],
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        guard let handlerId = loadedTool.manifest.execution.handler else {
            throw ToolExecutionErrorV2.executionFailed(
                "internal_handler type requires 'handler' field"
            )
        }
        
        guard let handler = handlerRegistry.handlerV2(for: handlerId) else {
            throw ToolExecutionErrorV2.handlerNotFound(handlerId)
        }
        
        // Validate inputs via handler
        let validationErrors = handler.validateInputs(inputs, manifest: loadedTool.manifest)
        if !validationErrors.isEmpty {
            throw ToolExecutionErrorV2.validationFailed(validationErrors)
        }
        
        // Execute
        return try await handler.executeV2(
            inputs: inputs,
            manifest: loadedTool.manifest,
            context: context
        )
    }
    
    // MARK: - Pipeline Execution
    
    private func executePipelineV2(
        loadedTool: LoadedTool,
        inputs: [String: Any]
    ) async throws -> ToolResultV2 {
        // Wrap the existing DynamicToolExecutionEngine
        // This requires converting V2 pipeline steps to V1 format
        // For now, return a placeholder - full implementation in Phase 3
        
        logger.warning("Pipeline execution not fully implemented yet")
        
        return ToolResultV2.failure(
            toolId: loadedTool.id,
            error: "Pipeline execution type coming in Phase 3"
        )
    }
    
    // MARK: - Provider Native Execution

    private func executeProviderNativeV2(
        loadedTool: LoadedTool,
        inputs: [String: Any]
    ) async throws -> ToolResultV2 {
        guard let provider = loadedTool.manifest.execution.provider else {
            throw ToolExecutionErrorV2.executionFailed(
                "provider_native type requires 'provider' field"
            )
        }

        // Map provider name to handler ID
        // Provider handlers are registered with their provider name as the handler ID
        guard let handler = handlerRegistry.handlerV2(for: provider) else {
            throw ToolExecutionErrorV2.handlerNotFound(
                "No handler registered for provider: \(provider)"
            )
        }

        logger.info("Routing provider_native tool '\(loadedTool.id)' to handler '\(provider)'")

        // Execute via the provider handler
        // The handler receives the full manifest and can use the tool ID to determine behavior
        return try await handler.executeV2(
            inputs: inputs,
            manifest: loadedTool.manifest,
            context: .empty
        )
    }
    
    // MARK: - URL Scheme Execution
    
    private func executeURLSchemeV2(
        loadedTool: LoadedTool,
        inputs: [String: Any]
    ) async throws -> ToolResultV2 {
        guard let urlTemplate = loadedTool.manifest.execution.urlTemplate else {
            throw ToolExecutionErrorV2.executionFailed(
                "url_scheme type requires 'urlTemplate' field"
            )
        }
        
        // Substitute parameters in URL template
        var resolvedURL = urlTemplate
        for (key, value) in inputs {
            let placeholder = "{{\(key)}}"
            let stringValue = String(describing: value)
            let encoded = stringValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stringValue
            resolvedURL = resolvedURL.replacingOccurrences(of: placeholder, with: encoded)
        }
        
        guard let url = URL(string: resolvedURL) else {
            throw ToolExecutionErrorV2.executionFailed("Invalid URL: \(resolvedURL)")
        }
        
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        await UIApplication.shared.open(url)
        #endif
        
        return ToolResultV2.success(
            toolId: loadedTool.id,
            output: "Opened: \(resolvedURL)"
        )
    }
    
    // MARK: - Shortcut Execution
    
    private func executeShortcutV2(
        loadedTool: LoadedTool,
        inputs: [String: Any]
    ) async throws -> ToolResultV2 {
        guard let shortcutName = loadedTool.manifest.execution.shortcutName else {
            throw ToolExecutionErrorV2.executionFailed(
                "shortcut type requires 'shortcutName' field"
            )
        }
        
        // Build x-shortcuts:// URL
        var urlString = "shortcuts://run-shortcut?name=\(shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shortcutName)"
        
        // Add input if provided
        if let inputValue = inputs["input"] ?? inputs["query"] {
            let inputString = String(describing: inputValue)
            if let encoded = inputString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString += "&input=\(encoded)"
            }
        }
        
        guard let url = URL(string: urlString) else {
            throw ToolExecutionErrorV2.executionFailed("Invalid shortcut URL")
        }
        
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        await UIApplication.shared.open(url)
        #endif
        
        return ToolResultV2.success(
            toolId: loadedTool.id,
            output: "Ran shortcut: \(shortcutName)"
        )
    }
    
    // MARK: - Bridge Execution
    
    private func executeBridgeV2(
        loadedTool: LoadedTool,
        inputs: [String: Any],
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        // Bridge execution routes to Mac via BridgeService
        // This is a complex feature that integrates with the VS Code extension
        
        logger.warning("Bridge execution not fully implemented yet")
        
        return ToolResultV2.failure(
            toolId: loadedTool.id,
            error: "Bridge execution type deferred - requires BridgeService integration"
        )
    }
}

// MARK: - Convenience Extensions

extension ToolExecutionRouterV2 {
    
    /// Quick execute with just tool ID and query string
    func quickExecuteV2(
        toolId: String,
        query: String
    ) async throws -> String {
        let result = try await executeToolV2(
            toolId: toolId,
            rawInput: query
        )
        return result.output
    }
    
    /// Check if a tool can be executed (is loaded and enabled)
    func canExecuteV2(toolId: String) -> Bool {
        guard let tool = pluginLoader.loadedTools.first(where: { $0.id == toolId }) else {
            return false
        }
        return tool.isEnabled
    }
}

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif
