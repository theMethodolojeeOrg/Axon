//
//  BridgeToolDefinitions.swift
//  Axon
//
//  Defines the AI-facing tools for VS Code bridge operations.
//  These tools become available when a VS Code workspace is connected.
//

import Foundation

// MARK: - Bridge Tool IDs

/// Tool IDs for VS Code bridge operations
enum BridgeToolId: String, CaseIterable {
    case readFile = "vscode_read_file"
    case writeFile = "vscode_write_file"
    case listFiles = "vscode_list_files"
    case runTerminal = "vscode_run_terminal"

    var displayName: String {
        switch self {
        case .readFile: return "Read File (VS Code)"
        case .writeFile: return "Write File (VS Code)"
        case .listFiles: return "List Files (VS Code)"
        case .runTerminal: return "Run Terminal (VS Code)"
        }
    }

    var description: String {
        switch self {
        case .readFile:
            return "Read the contents of a file from the connected VS Code workspace"
        case .writeFile:
            return "Write or create a file in the connected VS Code workspace"
        case .listFiles:
            return "List files and directories in the connected VS Code workspace"
        case .runTerminal:
            return "Execute a terminal command in the connected VS Code workspace"
        }
    }

    var icon: String {
        switch self {
        case .readFile: return "doc.text.magnifyingglass"
        case .writeFile: return "doc.badge.plus"
        case .listFiles: return "folder.badge.gearshape"
        case .runTerminal: return "terminal"
        }
    }

    /// Whether this tool requires biometric approval
    var requiresApproval: Bool {
        switch self {
        case .readFile, .listFiles:
            return false  // Read-only operations are safe
        case .writeFile, .runTerminal:
            return true   // Mutations require approval
        }
    }

    /// Risk level for approval UI
    var riskLevel: String {
        switch self {
        case .readFile, .listFiles: return "low"
        case .writeFile: return "medium"
        case .runTerminal: return "high"
        }
    }

    /// Maps to the corresponding BridgeMethod
    var bridgeMethod: BridgeMethod {
        switch self {
        case .readFile: return .fileRead
        case .writeFile: return .fileWrite
        case .listFiles: return .fileList
        case .runTerminal: return .terminalRun
        }
    }
}

// MARK: - System Prompt Generation

extension BridgeToolId {
    /// Generate the system prompt section for all bridge tools
    static func generateSystemPrompt(workspaceName: String, workspaceRoot: String) -> String {
        """

        ## VS Code Bridge Tools

        You have access to a connected VS Code workspace: **\(workspaceName)**
        Workspace root: `\(workspaceRoot)`

        You can read, write, and execute code directly in this workspace. Use these tools to help the user with coding tasks.

        ### vscode_read_file
        Read the contents of a file from the workspace.
        ```tool_request
        {"tool": "vscode_read_file", "query": "path/to/file.ts"}
        ```

        ### vscode_write_file
        Write or create a file in the workspace. **Requires user approval.**
        The query format is: `path|content`
        ```tool_request
        {"tool": "vscode_write_file", "query": "path/to/file.ts|const greeting = 'Hello, World!';\\nexport default greeting;"}
        ```

        ### vscode_list_files
        List files and directories. Use `.` for workspace root.
        ```tool_request
        {"tool": "vscode_list_files", "query": "src/components"}
        ```

        ### vscode_run_terminal
        Execute a terminal command. **Requires user approval.**
        ```tool_request
        {"tool": "vscode_run_terminal", "query": "npm test"}
        ```
        For commands with a working directory, use: `command|cwd`
        ```tool_request
        {"tool": "vscode_run_terminal", "query": "npm install lodash|src/project"}
        ```

        **Important:** File paths are relative to the workspace root. The workspace is isolated - you cannot access files outside of it.

        """
    }
}

// MARK: - Tool Execution

/// Service for executing bridge tools
@MainActor
class BridgeToolExecutor {

    static let shared = BridgeToolExecutor()

    private let bridgeServer = BridgeServer.shared
    private let toolApprovalService = ToolApprovalService.shared

    private init() {}

    /// Check if bridge tools are available
    var isAvailable: Bool {
        bridgeServer.isConnected && bridgeServer.connectedSession != nil
    }

    /// Get the connected workspace info for system prompt
    var workspaceInfo: (name: String, root: String)? {
        guard let session = bridgeServer.connectedSession else { return nil }
        return (session.workspaceName, session.workspaceRoot)
    }

    /// Execute a bridge tool request
    func execute(_ request: ToolRequest) async -> ToolResult {
        guard let toolId = BridgeToolId(rawValue: request.tool) else {
            return ToolResult(
                tool: request.tool,
                success: false,
                result: "Unknown bridge tool: \(request.tool)",
                sources: nil,
                memoryOperation: nil
            )
        }

        guard isAvailable else {
            return ToolResult(
                tool: request.tool,
                success: false,
                result: "No VS Code workspace connected. Tap the hotspot icon to start the bridge and connect from VS Code.",
                sources: nil,
                memoryOperation: nil
            )
        }

        // Check approval if needed
        if toolId.requiresApproval {
            let approved = await requestApproval(for: toolId, query: request.query)
            if !approved {
                return ToolResult(
                    tool: request.tool,
                    success: false,
                    result: "Operation was not approved by the user.",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        // Execute the appropriate operation
        do {
            switch toolId {
            case .readFile:
                return try await executeReadFile(query: request.query)
            case .writeFile:
                return try await executeWriteFile(query: request.query)
            case .listFiles:
                return try await executeListFiles(query: request.query)
            case .runTerminal:
                return try await executeRunTerminal(query: request.query)
            }
        } catch let error as BridgeError {
            return ToolResult(
                tool: request.tool,
                success: false,
                result: "Bridge error: \(error.message)",
                sources: nil,
                memoryOperation: nil
            )
        } catch {
            return ToolResult(
                tool: request.tool,
                success: false,
                result: "Error: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Tool Implementations

    private func executeReadFile(query: String) async throws -> ToolResult {
        let path = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let result = try await bridgeServer.readFile(path: path)

        return ToolResult(
            tool: BridgeToolId.readFile.rawValue,
            success: true,
            result: """
            **File:** `\(result.path)`
            **Size:** \(formatBytes(result.size))

            ```
            \(result.content)
            ```
            """,
            sources: nil,
            memoryOperation: nil
        )
    }

    private func executeWriteFile(query: String) async throws -> ToolResult {
        // Parse path|content format
        let parts = query.components(separatedBy: "|")
        guard parts.count >= 2 else {
            return ToolResult(
                tool: BridgeToolId.writeFile.rawValue,
                success: false,
                result: """
                Invalid format. Use: `path|content`

                Example:
                ```tool_request
                {"tool": "vscode_write_file", "query": "src/hello.ts|export const greeting = 'Hello!';"}
                ```
                """,
                sources: nil,
                memoryOperation: nil
            )
        }

        let path = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        // Rejoin remaining parts in case content contains |
        let content = parts.dropFirst().joined(separator: "|")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")

        let result = try await bridgeServer.writeFile(path: path, content: content)

        return ToolResult(
            tool: BridgeToolId.writeFile.rawValue,
            success: true,
            result: """
            \(result.created ? "Created" : "Updated") file: `\(result.path)`
            Wrote \(formatBytes(result.bytesWritten))
            """,
            sources: nil,
            memoryOperation: nil
        )
    }

    private func executeListFiles(query: String) async throws -> ToolResult {
        let path = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPath = path.isEmpty ? "." : path

        let result = try await bridgeServer.listFiles(path: targetPath)

        var output = "**Directory:** `\(result.path)`\n\n"

        if result.files.isEmpty {
            output += "(empty directory)"
        } else {
            // Group by type
            let directories = result.files.filter { $0.type == .directory }
            let files = result.files.filter { $0.type == .file }

            for dir in directories.sorted(by: { $0.name < $1.name }) {
                output += "📁 \(dir.name)/\n"
            }

            for file in files.sorted(by: { $0.name < $1.name }) {
                let size = file.size.map { formatBytes($0) } ?? ""
                output += "📄 \(file.name) \(size)\n"
            }

            output += "\n\(result.files.count) items"
        }

        return ToolResult(
            tool: BridgeToolId.listFiles.rawValue,
            success: true,
            result: output,
            sources: nil,
            memoryOperation: nil
        )
    }

    private func executeRunTerminal(query: String) async throws -> ToolResult {
        // Parse command|cwd format (cwd is optional)
        let parts = query.components(separatedBy: "|")
        let command = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let cwd = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil

        guard !command.isEmpty else {
            return ToolResult(
                tool: BridgeToolId.runTerminal.rawValue,
                success: false,
                result: "Command cannot be empty",
                sources: nil,
                memoryOperation: nil
            )
        }

        let result = try await bridgeServer.runTerminal(command: command, cwd: cwd)

        var output = "**Command:** `\(command)`\n"
        if let cwd = cwd {
            output += "**Working Directory:** `\(cwd)`\n"
        }
        output += "**Exit Code:** \(result.exitCode)\n"
        output += "**Duration:** \(result.duration)ms\n\n"

        if result.timedOut {
            output += "⚠️ Command timed out\n\n"
        }

        if !result.output.isEmpty {
            output += "**Output:**\n```\n\(result.output)\n```"
        }

        if let stderr = result.stderr, !stderr.isEmpty {
            output += "\n**Stderr:**\n```\n\(stderr)\n```"
        }

        return ToolResult(
            tool: BridgeToolId.runTerminal.rawValue,
            success: result.exitCode == 0,
            result: output,
            sources: nil,
            memoryOperation: nil
        )
    }

    // MARK: - Helpers

    private func requestApproval(for tool: BridgeToolId, query: String) async -> Bool {
        // Build a dynamic tool config for approval
        let toolConfig = DynamicToolConfig(
            id: tool.rawValue,
            name: tool.displayName,
            description: tool.description,
            category: .integration,
            enabled: true,
            icon: tool.icon,
            requiredSecrets: [],
            pipeline: [],
            parameters: [:],
            outputTemplate: nil,
            requiresApproval: true,
            approvalScopes: [formatApprovalScope(tool: tool, query: query)]
        )

        let result = await toolApprovalService.requestApproval(tool: toolConfig, inputs: ["query": query])

        switch result {
        case .approved:
            return true
        case .denied, .cancelled, .timeout, .error:
            return false
        }
    }

    private func formatApprovalScope(tool: BridgeToolId, query: String) -> String {
        switch tool {
        case .writeFile:
            let path = query.components(separatedBy: "|").first ?? query
            return "Write to file: \(path)"
        case .runTerminal:
            let command = query.components(separatedBy: "|").first ?? query
            return "Execute: \(command)"
        default:
            return "\(tool.displayName): \(query)"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}
