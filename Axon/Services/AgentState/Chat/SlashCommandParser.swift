//
//  SlashCommandParser.swift
//  Axon
//
//  Parses and executes slash commands from user input.
//  Enables users to reference tools via /tool <name> commands.
//

import Foundation

// MARK: - Slash Command Types

/// Slash command types supported by Axon
enum SlashCommand {
    case tool(toolId: String)
    case listTools
    case help
    case unknown(command: String)
    case none
}

/// Result of executing a slash command
struct SlashCommandResult {
    let command: SlashCommand
    let displayText: String
    let resultText: String
    let success: Bool
}

// MARK: - Slash Command Parser

/// Parser for slash commands in user messages
@MainActor
class SlashCommandParser {
    static let shared = SlashCommandParser()

    private init() {}

    // MARK: - Parsing

    /// Check if a message is a slash command
    func isSlashCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/")
    }

    /// Parse a message to detect slash commands
    /// Returns the parsed command type
    func parse(_ text: String) -> SlashCommand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if message starts with /
        guard trimmed.hasPrefix("/") else {
            return .none
        }

        // Extract command and args
        let components = trimmed.split(separator: " ", maxSplits: 1)
        guard let commandText = components.first else {
            return .none
        }

        let commandStr = String(commandText.dropFirst()).lowercased() // Remove leading /
        let args = components.count > 1 ? String(components[1]).trimmingCharacters(in: .whitespaces) : nil

        // Parse known commands
        switch commandStr {
        case "tool":
            guard let toolId = args, !toolId.isEmpty else {
                return .unknown(command: "tool (missing tool ID)")
            }
            return .tool(toolId: toolId)

        case "tools", "listtools", "list_tools":
            return .listTools

        case "help":
            return .help

        default:
            return .unknown(command: commandStr)
        }
    }

    // MARK: - Execution

    /// Execute a slash command and return the result
    func execute(_ command: SlashCommand) async -> SlashCommandResult {
        switch command {
        case .tool(let toolId):
            return await executeToolCommand(toolId: toolId)

        case .listTools:
            return await executeListToolsCommand()

        case .help:
            return executeHelpCommand()

        case .unknown(let cmd):
            return SlashCommandResult(
                command: command,
                displayText: "/\(cmd)",
                resultText: """
                Unknown command: `/\(cmd)`

                **Available commands:**
                - `/tool <tool_id>` - Show full details for a specific tool
                - `/tools` - List all available tools
                - `/help` - Show this help message

                Use `/tools` to see available tool IDs.
                """,
                success: false
            )

        case .none:
            return SlashCommandResult(
                command: command,
                displayText: "",
                resultText: "",
                success: false
            )
        }
    }

    // MARK: - Command Implementations

    private func executeToolCommand(toolId: String) async -> SlashCommandResult {
        // First try to find the tool as a ToolId
        if let tool = ToolId(rawValue: toolId) {
            let details = generateToolDetails(for: tool)
            return SlashCommandResult(
                command: .tool(toolId: toolId),
                displayText: "/tool \(toolId)",
                resultText: details,
                success: true
            )
        }

        // Try case-insensitive lookup
        let normalizedId = toolId.lowercased().replacingOccurrences(of: "-", with: "_")
        if let tool = ToolId.allCases.first(where: { $0.rawValue.lowercased() == normalizedId }) {
            let details = generateToolDetails(for: tool)
            return SlashCommandResult(
                command: .tool(toolId: tool.rawValue),
                displayText: "/tool \(tool.rawValue)",
                resultText: details,
                success: true
            )
        }

        // Not found - suggest similar tools
        let suggestions = findSimilarTools(toolId)
        var resultText = "Tool not found: `\(toolId)`\n\n"

        if !suggestions.isEmpty {
            resultText += "**Did you mean:**\n"
            for suggestion in suggestions.prefix(3) {
                resultText += "- `\(suggestion.rawValue)` - \(suggestion.displayName)\n"
            }
        }

        resultText += "\nUse `/tools` to see all available tools."

        return SlashCommandResult(
            command: .tool(toolId: toolId),
            displayText: "/tool \(toolId)",
            resultText: resultText,
            success: false
        )
    }

    private func executeListToolsCommand() async -> SlashCommandResult {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        var lines: [String] = []

        // Group by category
        for category in ToolCategory.allCases {
            let tools = ToolId.tools(for: category)
            guard !tools.isEmpty else { continue }

            let enabledInCategory = tools.filter { settings.toolSettings.isToolEnabled($0) }.count
            lines.append("### \(category.displayName) (\(enabledInCategory)/\(tools.count))")

            for tool in tools {
                let isEnabled = settings.toolSettings.isToolEnabled(tool)
                let status = isEnabled ? "+" : "-"
                lines.append("\(status) `\(tool.rawValue)` - \(tool.displayName)")
            }
            lines.append("")
        }

        let resultText = """
        ## Available Tools

        \(lines.joined(separator: "\n"))

        **Legend:** `+` enabled, `-` disabled

        Use `/tool <tool_id>` to see full details for any tool.
        """

        return SlashCommandResult(
            command: .listTools,
            displayText: "/tools",
            resultText: resultText,
            success: true
        )
    }

    private func executeHelpCommand() -> SlashCommandResult {
        let resultText = """
        ## Slash Commands

        **Available commands:**

        ### /tool <tool_id>
        Show full details, parameters, and examples for a specific tool.
        Example: `/tool google_search`

        ### /tools
        List all available tools organized by category.

        ### /help
        Show this help message.

        ---

        *Tip: Tool details shown via `/tool` are visible to both you and the AI, making it easy to collaborate on tool usage.*
        """

        return SlashCommandResult(
            command: .help,
            displayText: "/help",
            resultText: resultText,
            success: true
        )
    }

    // MARK: - Helpers

    private func generateToolDetails(for tool: ToolId) -> String {
        var details = """
        ## \(tool.displayName)

        **ID:** `\(tool.rawValue)`
        **Provider:** \(tool.provider.displayName)
        **Category:** \(tool.category.displayName)

        ### Description
        \(tool.description)

        """

        // Add approval info if required
        if tool.requiresApproval {
            details += """

            ### Requires Approval
            This tool requires user approval before execution.

            **Approval scopes:**
            """
            for scope in tool.approvalScopes {
                details += "\n- \(scope)"
            }
            details += "\n"
        }

        // Add usage example
        details += """

        ### Usage
        To use this tool, the AI should include:
        ```tool_request
        {"tool": "\(tool.rawValue)", "query": "your request here"}
        ```
        """

        // Add specific examples based on tool type
        if let example = getToolExample(for: tool) {
            details += """

            ### Example
            ```tool_request
            \(example)
            ```
            """
        }

        details += "\n\n---\n*Injected via `/tool` command*"

        return details
    }

    private func getToolExample(for tool: ToolId) -> String? {
        switch tool {
        case .googleSearch:
            return "{\"tool\": \"google_search\", \"query\": \"current weather in San Francisco\"}"
        case .codeExecution:
            return "{\"tool\": \"code_execution\", \"query\": \"Calculate the factorial of 10\"}"
        case .urlContext:
            return "{\"tool\": \"url_context\", \"query\": \"Summarize https://example.com/article\"}"
        case .googleMaps:
            return "{\"tool\": \"google_maps\", \"query\": \"Best coffee shops near me\"}"
        case .createMemory:
            return "{\"tool\": \"create_memory\", \"query\": \"allocentric|0.9|preferences,communication|User prefers concise responses\"}"
        case .conversationSearch:
            return "{\"tool\": \"conversation_search\", \"query\": \"What did we discuss about the project last week?\"}"
        case .listTools:
            return "{\"tool\": \"list_tools\", \"query\": \"enabled\"}"
        case .getToolDetails:
            return "{\"tool\": \"get_tool_details\", \"query\": \"google_search\"}"
        case .heartbeatRunOnce:
            return "{\"tool\": \"heartbeat_run_once\", \"query\": \"Check in with daily summary\"}"
        default:
            return nil
        }
    }

    private func findSimilarTools(_ query: String) -> [ToolId] {
        let normalizedQuery = query.lowercased()

        // Simple similarity: contains query or query contains tool id
        return ToolId.allCases.filter { tool in
            let toolId = tool.rawValue.lowercased()
            let displayName = tool.displayName.lowercased()

            return toolId.contains(normalizedQuery) ||
                   normalizedQuery.contains(toolId) ||
                   displayName.contains(normalizedQuery) ||
                   normalizedQuery.contains(displayName)
        }
    }
}
