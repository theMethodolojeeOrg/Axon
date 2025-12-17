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
    /// All VS Code bridge tools require approval since they access external workspace
    var requiresApproval: Bool {
        switch self {
        case .readFile, .listFiles:
            return true  // Even read-only needs approval for VS Code access
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
            """
    }
}
