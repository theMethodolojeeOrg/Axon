//
//  BridgeHandler.swift
//  Axon
//
//  V2 Handler for bridge tools - supports both Mac system tools and VS Code workspace tools
//

import Foundation
import os.log

/// Handler for bridge-type tools
///
/// Supports two bridge targets:
/// - Mac system tools (`mac_*`) → Execute locally via MacSystemToolExecutor
/// - VS Code tools (`vscode_*`) → Execute via WebSocket bridge to VS Code extension
///
/// Registered handlers:
/// - `bridge` → Routes based on manifest.execution.bridgeTarget
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

        if toolId == "debug_bridge" {
            return executeDebugBridgeTool(toolId: toolId)
        }

        let bridgeTarget = manifest.execution.bridgeTarget ?? "mac"
        
        // Route based on bridge target
        switch bridgeTarget {
        case "vscode":
            return try await executeVSCodeTool(toolId: toolId, inputs: inputs, manifest: manifest)
        case "mac":
            return try await executeMacTool(toolId: toolId, inputs: inputs, manifest: manifest)
        default:
            // Default to Mac execution for backward compatibility
            return try await executeMacTool(toolId: toolId, inputs: inputs, manifest: manifest)
        }
    }
    
    // MARK: - VS Code Bridge Execution
    
    /// Execute a tool via the VS Code WebSocket bridge
    private func executeVSCodeTool(
        toolId: String,
        inputs: [String: Any],
        manifest: ToolManifest
    ) async throws -> ToolResultV2 {
        // VSCode tools always require bridge connection
        guard connectionManager.isConnected else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "VS Code bridge not connected. Start the Bridge Server and connect VS Code extension first."
            )
        }
        
        guard let bridgeMethod = manifest.execution.bridgeMethod else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Tool missing bridge method configuration"
            )
        }
        
        logger.info("Executing VS Code tool: \(toolId) via \(bridgeMethod)")
        
        do {
            let result = try await executeVSCodeMethod(bridgeMethod: bridgeMethod, inputs: inputs)
            return ToolResultV2.success(
                toolId: toolId,
                output: result,
                structured: nil
            )
        } catch {
            return ToolResultV2.failure(
                toolId: toolId,
                error: error.localizedDescription
            )
        }
    }
    
    /// Route to the appropriate BridgeConnectionManager method
    private func executeVSCodeMethod(bridgeMethod: String, inputs: [String: Any]) async throws -> String {
        switch bridgeMethod {
        case "file/read":
            guard let path = inputs["path"] as? String else {
                throw BridgeError(code: .invalidParams, message: "Missing required parameter: path")
            }
            let result = try await connectionManager.readFile(path: path)
            return formatFileReadResult(result)
            
        case "file/write":
            guard let path = inputs["path"] as? String,
                  let content = inputs["content"] as? String else {
                throw BridgeError(code: .invalidParams, message: "Missing required parameters: path, content")
            }
            let result = try await connectionManager.writeFile(path: path, content: content)
            return formatFileWriteResult(result)
            
        case "file/list":
            guard let path = inputs["path"] as? String else {
                throw BridgeError(code: .invalidParams, message: "Missing required parameter: path")
            }
            let recursive = inputs["recursive"] as? Bool ?? false
            let result = try await connectionManager.listFiles(path: path, recursive: recursive)
            return formatFileListResult(result)
            
        case "terminal/run":
            guard let command = inputs["command"] as? String else {
                throw BridgeError(code: .invalidParams, message: "Missing required parameter: command")
            }
            let cwd = inputs["cwd"] as? String
            let result = try await connectionManager.runTerminal(command: command, cwd: cwd)
            return formatTerminalResult(result)
            
        case "workspace/info":
            let result = try await connectionManager.getWorkspaceInfo()
            return formatWorkspaceInfoResult(result)
            
        default:
            throw BridgeError(code: .methodNotFound, message: "Unknown bridge method: \(bridgeMethod)")
        }
    }
    
    // MARK: - Mac System Tool Execution
    
    /// Execute a Mac system tool (locally on macOS, via bridge on iOS)
    private func executeMacTool(
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
        
        logger.info("Executing Mac tool: \(toolId) via \(bridgeMethod)")
        
        #if os(macOS)
        // On macOS, execute locally via MacSystemToolExecutor
        do {
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
        #else
        // On iOS, Mac tools require bridge connection to a Mac
        guard connectionManager.isConnected else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Bridge not connected. Connect to a Mac to use Mac system tools."
            )
        }
        
        do {
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
        #endif
    }
    
    // MARK: - Result Formatting

    /// Execute debug_bridge in V2 without requiring bridgeMethod metadata.
    private func executeDebugBridgeTool(toolId: String) -> ToolResultV2 {
        let server = BridgeServer.shared
        let logs = BridgeLogService.shared.entries.prefix(15)

        var output = "## VS Code Bridge Status\n\n"
        output += "- **Running:** \(server.isRunning ? "Yes" : "No")\n"
        output += "- **Connected:** \(server.isConnected ? "Yes" : "No")\n"
        output += "- **Connections:** \(server.connectionCount)\n"

        if let session = server.connectedSession {
            output += "- **Session:** \(session.displayName) (v\(session.extensionVersion))\n"
        }

        if let error = server.lastError {
            output += "- **Last Error:** \(error)\n"
        }

        output += "\n### Recent Logs (Last 15)\n\n"

        if logs.isEmpty {
            output += "*No logs available.*\n"
        } else {
            for log in logs {
                let direction = log.direction == .incoming ? "←" : "→"
                output += "`\(log.formattedTimestamp)` \(direction) [\(log.messageType.rawValue)] \(log.summary)\n"
            }
        }

        output += "\n\n*View full logs in Settings -> Axon Bridge -> Bridge Inspector*"

        return ToolResultV2.success(
            toolId: toolId,
            output: output,
            structured: nil
        )
    }

    private func formatFileReadResult(_ result: FileReadResult) -> String {
        var output = "📄 **File:** \(result.path)\n"
        output += "📏 **Size:** \(formatBytes(result.size))\n"
        output += "🔤 **Encoding:** \(result.encoding)\n\n"
        output += "```\n\(result.content)\n```"
        return output
    }
    
    private func formatFileWriteResult(_ result: FileWriteResult) -> String {
        var output = result.created ? "✅ Created new file" : "✅ Updated file"
        output += "\n📄 **Path:** \(result.path)"
        output += "\n📏 **Bytes written:** \(result.bytesWritten)"
        return output
    }
    
    private func formatFileListResult(_ result: FileListResult) -> String {
        var output = "📁 **Directory:** \(result.path)\n\n"
        
        for file in result.files {
            let icon = file.type == .directory ? "📁" : "📄"
            let size = file.size.map { " (\(formatBytes($0)))" } ?? ""
            output += "\(icon) \(file.name)\(size)\n"
        }
        
        output += "\n**Total:** \(result.files.count) items"
        return output
    }
    
    private func formatTerminalResult(_ result: TerminalRunResult) -> String {
        var output = "🖥️ **Command executed**\n"
        output += "⏱️ **Duration:** \(result.duration)ms\n"
        output += "📊 **Exit code:** \(result.exitCode)\n\n"
        
        if !result.output.isEmpty {
            output += "**Output:**\n```\n\(result.output)\n```\n"
        }
        
        if let stderr = result.stderr, !stderr.isEmpty {
            output += "**Errors:**\n```\n\(stderr)\n```"
        }
        
        return output
    }
    
    private func formatWorkspaceInfoResult(_ result: WorkspaceInfoResult) -> String {
        var output = "🗂️ **Workspace:** \(result.name)\n\n"
        
        output += "**Folders:**\n"
        for folder in result.folders {
            output += "  📁 \(folder.name) (\(folder.path))\n"
        }
        
        if !result.openFiles.isEmpty {
            output += "\n**Open Files:**\n"
            for file in result.openFiles {
                output += "  📄 \(file)\n"
            }
        }
        
        return output
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1 {
            return "\(bytes) B"
        } else if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            return String(format: "%.1f MB", kb / 1024)
        }
    }
}
