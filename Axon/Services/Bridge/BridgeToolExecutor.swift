//
//  BridgeToolExecutor.swift
//  Axon
//
//  Executes VS Code bridge tools for the ToolProxyService.
//  Provides a unified interface for executing bridge commands regardless
//  of whether we're in Local Mode (BridgeServer) or Remote Mode (BridgeClient).
//

import Foundation

@MainActor
class BridgeToolExecutor {
    static let shared = BridgeToolExecutor()

    // MARK: - Dependencies

    private let connectionManager = BridgeConnectionManager.shared

    // MARK: - Workspace Info

    /// Information about the connected workspace (if any)
    struct WorkspaceInfo {
        let name: String
        let root: String
    }

    /// Returns workspace info if connected, nil otherwise
    var workspaceInfo: WorkspaceInfo? {
        guard let session = connectionManager.connectedSession else {
            return nil
        }
        return WorkspaceInfo(
            name: session.workspaceName,
            root: session.workspaceRoot
        )
    }

    /// Whether a VS Code workspace is connected
    var isConnected: Bool {
        connectionManager.isConnected
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Tool Execution

    /// Execute a bridge tool request and return a ToolResult
    func execute(_ request: ToolRequest) async -> ToolResult {
        guard isConnected else {
            return ToolResult(
                tool: request.tool,
                success: false,
                result: "VS Code is not connected. Please connect to a workspace first.",
                sources: nil,
                memoryOperation: nil
            )
        }

        guard let toolId = BridgeToolId(rawValue: request.tool) else {
            return ToolResult(
                tool: request.tool,
                success: false,
                result: "Unknown bridge tool: \(request.tool)",
                sources: nil,
                memoryOperation: nil
            )
        }

        // Check approval if needed
        if toolId.requiresApproval {
            let approvalResult = await requestApproval(for: toolId, query: request.query)
            switch approvalResult {
            case .approved, .approvedForSession, .approvedViaTrustTier:
                break // Continue with execution
            case .denied:
                return ToolResult(
                    tool: request.tool,
                    success: false,
                    result: "⛔ Tool execution was not authorized by the user.",
                    sources: nil,
                    memoryOperation: nil
                )
            case .cancelled:
                return ToolResult(
                    tool: request.tool,
                    success: false,
                    result: "Tool execution was cancelled.",
                    sources: nil,
                    memoryOperation: nil
                )
            case .timeout:
                return ToolResult(
                    tool: request.tool,
                    success: false,
                    result: "⏱️ Tool approval request timed out.",
                    sources: nil,
                    memoryOperation: nil
                )
            case .stop:
                return ToolResult(
                    tool: request.tool,
                    success: false,
                    result: "🛑 Tool execution stopped.",
                    sources: nil,
                    memoryOperation: nil
                )
            case .blocked(let reason):
                return ToolResult(
                    tool: request.tool,
                    success: false,
                    result: "🚫 Tool blocked: \(reason)",
                    sources: nil,
                    memoryOperation: nil
                )
            case .error(let message):
                return ToolResult(
                    tool: request.tool,
                    success: false,
                    result: "Approval error: \(message)",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        // Execute the tool
        do {
            switch toolId {
            case .readFile:
                return try await executeReadFile(path: request.query)

            case .writeFile:
                // Parse path and content from query
                // Format: path|content or separate content field
                if let content = request.separateContent {
                    return try await executeWriteFile(path: request.query, content: content)
                } else if request.query.contains("|") {
                    let parts = request.query.split(separator: "|", maxSplits: 1)
                    if parts.count == 2 {
                        return try await executeWriteFile(
                            path: String(parts[0]).trimmingCharacters(in: .whitespaces),
                            content: String(parts[1])
                        )
                    }
                }
                return ToolResult(
                    tool: request.tool,
                    success: false,
                    result: "Invalid format for write_file. Use: path|content or provide content separately.",
                    sources: nil,
                    memoryOperation: nil
                )

            case .listFiles:
                // Parse path and recursive flag
                let parts = request.query.components(separatedBy: "|")
                let path = parts[0].trimmingCharacters(in: .whitespaces)
                let recursive = parts.count > 1 && parts[1].lowercased().contains("true")
                return try await executeListFiles(path: path, recursive: recursive)

            case .runTerminal:
                // Parse command and optional cwd
                let parts = request.query.components(separatedBy: "|")
                let command = parts[0].trimmingCharacters(in: .whitespaces)
                let cwd = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
                return try await executeTerminal(command: command, cwd: cwd)
            }
        } catch {
            return ToolResult(
                tool: request.tool,
                success: false,
                result: "Bridge tool error: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Tool Implementations

    private func executeReadFile(path: String) async throws -> ToolResult {
        let result = try await connectionManager.readFile(path: path)

        return ToolResult(
            tool: BridgeToolId.readFile.rawValue,
            success: true,
            result: """
                **File:** `\(path)`
                **Size:** \(result.size) bytes

                ```
                \(result.content)
                ```
                """,
            sources: nil,
            memoryOperation: nil
        )
    }

    private func executeWriteFile(path: String, content: String) async throws -> ToolResult {
        let result = try await connectionManager.writeFile(path: path, content: content)

        return ToolResult(
            tool: BridgeToolId.writeFile.rawValue,
            success: result.success,
            result: result.success
                ? "✅ File written successfully: `\(path)` (\(result.bytesWritten) bytes)"
                : "❌ Failed to write file at `\(result.path)`",
            sources: nil,
            memoryOperation: nil
        )
    }

    private func executeListFiles(path: String, recursive: Bool) async throws -> ToolResult {
        let result = try await connectionManager.listFiles(path: path, recursive: recursive)

        var output = "**Directory:** `\(path)`\n\n"

        for file in result.files.prefix(50) {
            let icon = file.type == .directory ? "📁" : "📄"
            let size = file.type == .directory ? "" : " (\(formatBytes(file.size ?? 0)))"
            output += "\(icon) `\(file.name)`\(size)\n"
        }

        if result.files.count > 50 {
            output += "\n... and \(result.files.count - 50) more entries"
        }

        return ToolResult(
            tool: BridgeToolId.listFiles.rawValue,
            success: true,
            result: output,
            sources: nil,
            memoryOperation: nil
        )
    }

    private func executeTerminal(command: String, cwd: String?) async throws -> ToolResult {
        let result = try await connectionManager.runTerminal(command: command, cwd: cwd)

        var output = "**Command:** `\(command)`\n"
        if let cwd = cwd {
            output += "**Directory:** `\(cwd)`\n"
        }
        output += "**Exit Code:** \(result.exitCode)\n\n"

        if !result.output.isEmpty {
            output += "**Output:**\n```\n\(result.output)\n```\n"
        }

        if let stderr = result.stderr, !stderr.isEmpty {
            output += "**Errors:**\n```\n\(stderr)\n```\n"
        }

        return ToolResult(
            tool: BridgeToolId.runTerminal.rawValue,
            success: result.exitCode == 0,
            result: output,
            sources: nil,
            memoryOperation: nil
        )
    }

    // MARK: - Approval

    private func requestApproval(for toolId: BridgeToolId, query: String) async -> ToolApprovalResult {
        let toolConfig = DynamicToolConfig(
            id: toolId.rawValue,
            name: toolId.displayName,
            description: toolId.description,
            category: .integration,
            enabled: true,
            icon: toolId.icon,
            requiredSecrets: [],
            pipeline: [],
            parameters: [:],
            requiresApproval: true,
            approvalScopes: ["VS Code workspace access: \(query)"]
        )

        let inputs: [String: Any] = ["query": query]
        return await ToolApprovalService.shared.requestApproval(tool: toolConfig, inputs: inputs)
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
