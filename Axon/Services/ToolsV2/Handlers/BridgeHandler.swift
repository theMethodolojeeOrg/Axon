//
//  BridgeHandler.swift
//  Axon
//
//  V2 Handler for Mac bridge/system tools
//

import Foundation
import os.log

/// Handler for Mac bridge tools
///
/// Registered handlers:
/// - `bridge` → mac_* tools (clipboard, notification, spotlight, file, app, screenshot, network, shell)
@MainActor
final class BridgeHandler: ToolHandlerV2 {
    
    let handlerId = "bridge"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "BridgeHandler"
    )
    
    private let connectionManager = BridgeConnectionManager.shared
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        // Check bridge connection
        guard connectionManager.isConnected else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Bridge not connected. Please connect to a Mac or VS Code instance first."
            )
        }
        
        // Route to MacSystemToolExecutor
        return try await executeBridgeTool(toolId: toolId, inputs: inputs, manifest: manifest)
    }
    
    // MARK: - Bridge Tool Execution
    
    private func executeBridgeTool(
        toolId: String,
        inputs: [String: Any],
        manifest: ToolManifest
    ) async throws -> ToolResultV2 {
        guard let bridgeMethod = manifest.execution.bridgeMethod else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Tool missing bridge method configuration"
            )
        }
        
        logger.info("Executing bridge tool: \(toolId) via \(bridgeMethod)")
        
        do {
            // Use MacSystemToolExecutor for the actual execution
            let executor = MacSystemToolExecutor.shared
            let result = try await executor.execute(manifest: manifest, inputs: inputs)
            
            return ToolResultV2.success(
                toolId: toolId,
                output: result.result ?? "Completed",
                structured: nil
            )
        } catch {
            return ToolResultV2.failure(
                toolId: toolId,
                error: error.localizedDescription
            )
        }
    }
}
