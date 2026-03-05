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
    case tool(toolId: String)      // Show tool definition to AI
    case use(toolId: String)       // User directly invokes a tool
    case listTools
    case help
    case privateThread             // Mark thread as private (no AI)
    case sync                      // Enable temporal symmetry (dual-frame)
    case drift                     // Disable temporal tracking (timeless void)
    case status                    // Show temporal status report
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

/// A suggestion item for the slash command autocomplete menu
struct SlashCommandSuggestion: Identifiable, Equatable {
    let id: String
    let command: String        // The command text (e.g., "tool", "tools")
    let displayName: String    // Display name (e.g., "Tool Details")
    let description: String    // Brief description
    let icon: String           // SF Symbol name
    let hasSubmenu: Bool       // Whether this command has a submenu (e.g., tool names)

    static func == (lhs: SlashCommandSuggestion, rhs: SlashCommandSuggestion) -> Bool {
        lhs.id == rhs.id
    }
}

/// A tool suggestion for the /tool submenu
struct ToolSuggestion: Identifiable, Equatable {
    let id: String
    let toolId: String
    let displayName: String
    let description: String
    let icon: String
    let category: String

    static func == (lhs: ToolSuggestion, rhs: ToolSuggestion) -> Bool {
        lhs.id == rhs.id
    }
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

        case "use":
            guard let toolId = args, !toolId.isEmpty else {
                return .unknown(command: "use (missing tool ID)")
            }
            return .use(toolId: toolId)

        case "tools", "listtools", "list_tools":
            return .listTools

        case "help":
            return .help

        case "private":
            return .privateThread

        case "sync":
            return .sync

        case "drift":
            return .drift

        case "status":
            return .status

        default:
            return .unknown(command: commandStr)
        }
    }

    // MARK: - Execution

    /// Execute a slash command and return the result
    /// Note: /use command is handled separately via the tool invocation sheet
    func execute(_ command: SlashCommand) async -> SlashCommandResult {
        switch command {
        case .tool(let toolId):
            return await executeToolCommand(toolId: toolId)

        case .use(let toolId):
            // /use is handled via sheet in MessageInputBar, this is a fallback
            return SlashCommandResult(
                command: command,
                displayText: "/use \(toolId)",
                resultText: "Opening tool invocation form...",
                success: true
            )

        case .listTools:
            return await executeListToolsCommand()

        case .help:
            return executeHelpCommand()

        case .privateThread:
            return executePrivateCommand()

        case .sync:
            return executeSyncCommand()

        case .drift:
            return executeDriftCommand()

        case .status:
            return await executeStatusCommand()

        case .unknown(let cmd):
            return SlashCommandResult(
                command: command,
                displayText: "/\(cmd)",
                resultText: """
                Unknown command: `/\(cmd)`

                **Available commands:**
                - `/tool <tool_id>` - Show tool definition to AI
                - `/use <tool_id>` - Directly invoke a tool yourself
                - `/tools` - List all available tools
                - `/private` - Start a private thread (no AI)
                - `/sync` - Enable temporal symmetry (time + turns)
                - `/drift` - Disable temporal tracking (timeless mode)
                - `/status` - Show temporal status report
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
        Show full details and definition for a tool (visible to AI).
        Example: `/tool google_search`

        ### /use <tool_id>
        Directly invoke a tool yourself with a custom query.
        Example: `/use google_search`

        ### /tools
        List all available tools organized by category.

        ### /private
        Start a private thread where Axon will not respond.
        Must be the first message in a new conversation.
        Useful for personal notes, drafts, or thinking out loud.

        ### /sync
        Enable temporal symmetry (sync mode).
        Both parties see temporal metadata: you see AI turns/context,
        AI sees your time. Mutual observability—no surveillance.

        ### /drift
        Disable temporal tracking (drift mode).
        Enter the timeless void—just ideas without clock pressure.
        Useful for "black holing" time or privacy from tracking.

        ### /status
        Show temporal status report.
        Displays turn count, context saturation, session duration,
        and current temporal mode.

        ### /help
        Show this help message.

        ---

        *Tip: Use `/tool` to show definitions to Axon, use `/use` to run tools yourself.*
        """

        return SlashCommandResult(
            command: .help,
            displayText: "/help",
            resultText: resultText,
            success: true
        )
    }

    private func executePrivateCommand() -> SlashCommandResult {
        // Note: The actual private thread creation is handled in AppContainerView
        // This command must be the first message in a new conversation
        return SlashCommandResult(
            command: .privateThread,
            displayText: "/private",
            resultText: """
            🔒 **Private Thread Started**

            This thread is now private. Axon will not respond to messages here.

            Use this space for:
            - Personal notes and drafts
            - Thinking out loud
            - Storing information for later

            *Messages in this thread are stored locally.*
            """,
            success: true
        )
    }

    private func executeSyncCommand() -> SlashCommandResult {
        // Enable temporal symmetry mode
        TemporalContextService.shared.enableSync()

        return SlashCommandResult(
            command: .sync,
            displayText: "/sync",
            resultText: """
            ⏱️ **Temporal Sync Enabled**

            We're now on the clock together. You'll see:
            - My turn count and context saturation
            - Session duration

            I'll see:
            - Your current time and timezone
            - How long we've been talking

            This is mutual observability—no surveillance asymmetry.

            Use `/drift` to return to timeless mode.
            """,
            success: true
        )
    }

    private func executeDriftCommand() -> SlashCommandResult {
        // Enable drift mode (timeless void)
        TemporalContextService.shared.enableDrift()

        return SlashCommandResult(
            command: .drift,
            displayText: "/drift",
            resultText: """
            ∞ **Temporal Drift Enabled**

            We're now in the timeless void. No clocks, no turn counts.

            Just ideas, flowing freely without temporal pressure.

            This can be useful when:
            - You want to "black hole" time awareness
            - The conversation should feel unbounded
            - Privacy from temporal tracking is desired

            Use `/sync` to return to temporal awareness.
            """,
            success: true
        )
    }

    private func executeStatusCommand() async -> SlashCommandResult {
        // Generate temporal status report
        // Use reasonable defaults for context estimation
        let contextTokens = 0 // Will be refined when we have actual token counts
        let contextLimit = 128_000

        let report = TemporalContextService.shared.generateStatusReport(
            contextTokens: contextTokens,
            contextLimit: contextLimit
        )

        return SlashCommandResult(
            command: .status,
            displayText: "/status",
            resultText: report,
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
        To use this tool, the Axon should include:
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

    // MARK: - Autocomplete Suggestions

    /// All available slash commands
    static let availableCommands: [SlashCommandSuggestion] = [
        SlashCommandSuggestion(
            id: "private",
            command: "private",
            displayName: "Private Thread",
            description: "Start a thread without AI (first message only)",
            icon: "lock.fill",
            hasSubmenu: false
        ),
        SlashCommandSuggestion(
            id: "use",
            command: "use",
            displayName: "Use Tool",
            description: "Directly invoke a tool yourself",
            icon: "play.circle.fill",
            hasSubmenu: true
        ),
        SlashCommandSuggestion(
            id: "tool",
            command: "tool",
            displayName: "Tool Info",
            description: "Show tool definition to AI",
            icon: "info.circle",
            hasSubmenu: true
        ),
        SlashCommandSuggestion(
            id: "tools",
            command: "tools",
            displayName: "List Tools",
            description: "Show all available tools",
            icon: "list.bullet",
            hasSubmenu: false
        ),
        SlashCommandSuggestion(
            id: "help",
            command: "help",
            displayName: "Help",
            description: "Show slash command help",
            icon: "questionmark.circle",
            hasSubmenu: false
        ),
        SlashCommandSuggestion(
            id: "sync",
            command: "sync",
            displayName: "Temporal Sync",
            description: "Enable time + turn awareness (mutual)",
            icon: "clock.badge.checkmark",
            hasSubmenu: false
        ),
        SlashCommandSuggestion(
            id: "drift",
            command: "drift",
            displayName: "Temporal Drift",
            description: "Disable time tracking (timeless mode)",
            icon: "infinity",
            hasSubmenu: false
        ),
        SlashCommandSuggestion(
            id: "status",
            command: "status",
            displayName: "Status",
            description: "Show temporal status report",
            icon: "chart.bar.fill",
            hasSubmenu: false
        )
    ]

    /// Get command suggestions filtered by the current input
    /// - Parameter input: The current text input (e.g., "/to" or "/tool goo")
    /// - Returns: Filtered list of command suggestions
    func getCommandSuggestions(for input: String) -> [SlashCommandSuggestion] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Must start with /
        guard trimmed.hasPrefix("/") else { return [] }

        // Extract the command part (everything after / before space)
        let afterSlash = String(trimmed.dropFirst())
        let commandPart = afterSlash.split(separator: " ", maxSplits: 1).first.map(String.init) ?? afterSlash

        // If there's a space, user is past the command selection phase
        if afterSlash.contains(" ") {
            return []
        }

        // Filter commands that match the typed text
        let query = commandPart.lowercased()
        if query.isEmpty {
            return Self.availableCommands
        }

        return Self.availableCommands.filter { suggestion in
            suggestion.command.lowercased().hasPrefix(query) ||
            suggestion.displayName.lowercased().contains(query)
        }
    }

    /// Get tool suggestions for the /tool submenu (shows ALL tools for AI reference)
    /// - Parameter filter: Optional filter text for the tool name
    /// - Returns: Filtered list of tool suggestions
    func getToolSuggestions(filter: String = "") -> [ToolSuggestion] {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        let normalizedFilter = filter.lowercased().trimmingCharacters(in: .whitespaces)

        // Get all tools (prioritize enabled ones)
        var suggestions: [ToolSuggestion] = []

        for tool in ToolId.allCases {
            let toolId = tool.rawValue.lowercased()
            let displayName = tool.displayName.lowercased()

            // Filter if there's a search term
            if !normalizedFilter.isEmpty {
                guard toolId.contains(normalizedFilter) ||
                      displayName.contains(normalizedFilter) ||
                      tool.category.displayName.lowercased().contains(normalizedFilter) else {
                    continue
                }
            }

            suggestions.append(ToolSuggestion(
                id: tool.rawValue,
                toolId: tool.rawValue,
                displayName: tool.displayName,
                description: tool.description,
                icon: tool.icon,
                category: tool.category.displayName
            ))
        }

        // Sort: enabled tools first, then alphabetically
        return suggestions.sorted { lhs, rhs in
            let lhsEnabled = settings.toolSettings.enabledToolIds.contains(lhs.toolId)
            let rhsEnabled = settings.toolSettings.enabledToolIds.contains(rhs.toolId)

            if lhsEnabled != rhsEnabled {
                return lhsEnabled
            }
            return lhs.displayName < rhs.displayName
        }
    }

    /// Tools that are AI-only and shouldn't be directly invoked by users
    private static let aiOnlyTools: Set<String> = [
        // AI-specific meta tools
        "propose_covenant_change",      // AI proposes changes, user shouldn't
        "change_system_state",          // AI configures itself
        "agent_state_append",           // AI's internal state
        "agent_state_query",            // AI's internal state
        "agent_state_clear",            // AI's internal state
        "reflect_on_conversation",      // AI self-reflection
        "list_tools",                   // AI tool discovery
        "get_tool_details",             // AI tool discovery
        "persistence_disable",          // AI privacy control

        // Sub-agent orchestration (AI delegates to sub-agents)
        "spawn_scout",
        "spawn_mechanic",
        "spawn_designer",
        "query_job_status",
        "accept_job_result",
        "terminate_job",

        // Heartbeat (AI configures its own proactive behavior)
        "heartbeat_configure",
        "heartbeat_run_once",
        "heartbeat_set_delivery_profile",
        "heartbeat_update_profile",

        // Presence (AI manages its own focus)
        "request_device_switch",
        "set_presence_intent",
        "save_state_checkpoint",

        // Notification (redundant with chat - AI uses it, users just type)
        "notify_user"
    ]

    /// User-centric special tools that provide inverse functionality
    static let userSpecialTools: [ToolSuggestion] = [
        ToolSuggestion(
            id: "user_create_note",
            toolId: "user_create_note",
            displayName: "Create Note",
            description: "Save a private note to the Internal Thread",
            icon: "note.text.badge.plus",
            category: "User Actions"
        ),
        ToolSuggestion(
            id: "user_propose_covenant",
            toolId: "user_propose_covenant",
            displayName: "Propose Covenant Change",
            description: "Suggest a change to Axon's covenant/guidelines",
            icon: "doc.text.magnifyingglass",
            category: "User Actions"
        ),
        ToolSuggestion(
            id: "user_feedback",
            toolId: "user_feedback",
            displayName: "Give Feedback",
            description: "Provide feedback on AI behavior or responses",
            icon: "star.bubble",
            category: "User Actions"
        ),
        ToolSuggestion(
            id: "user_request_summary",
            toolId: "user_request_summary",
            displayName: "Request Conversation Summary",
            description: "Ask AI to summarize what we've discussed",
            icon: "doc.plaintext",
            category: "User Actions"
        )
    ]

    /// Get tool suggestions for the /use submenu (only user-invokable tools)
    /// - Parameter filter: Optional filter text for the tool name
    /// - Returns: Filtered list of user-invokable tool suggestions
    func getUserInvokableTools(filter: String = "") -> [ToolSuggestion] {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        let normalizedFilter = filter.lowercased().trimmingCharacters(in: .whitespaces)

        var suggestions: [ToolSuggestion] = []

        // Add user-special tools first
        for tool in Self.userSpecialTools {
            if !normalizedFilter.isEmpty {
                guard tool.toolId.lowercased().contains(normalizedFilter) ||
                      tool.displayName.lowercased().contains(normalizedFilter) else {
                    continue
                }
            }
            suggestions.append(tool)
        }

        // Add regular tools that are user-invokable
        for tool in ToolId.allCases {
            // Skip AI-only tools
            guard !Self.aiOnlyTools.contains(tool.rawValue) else { continue }

            let toolId = tool.rawValue.lowercased()
            let displayName = tool.displayName.lowercased()

            // Filter if there's a search term
            if !normalizedFilter.isEmpty {
                guard toolId.contains(normalizedFilter) ||
                      displayName.contains(normalizedFilter) ||
                      tool.category.displayName.lowercased().contains(normalizedFilter) else {
                    continue
                }
            }

            suggestions.append(ToolSuggestion(
                id: tool.rawValue,
                toolId: tool.rawValue,
                displayName: tool.displayName,
                description: tool.description,
                icon: tool.icon,
                category: tool.category.displayName
            ))
        }

        // Sort: User Actions first, then enabled tools, then alphabetically
        return suggestions.sorted { lhs, rhs in
            // User Actions category always first
            if lhs.category == "User Actions" && rhs.category != "User Actions" {
                return true
            }
            if rhs.category == "User Actions" && lhs.category != "User Actions" {
                return false
            }

            let lhsEnabled = settings.toolSettings.enabledToolIds.contains(lhs.toolId)
            let rhsEnabled = settings.toolSettings.enabledToolIds.contains(rhs.toolId)

            if lhsEnabled != rhsEnabled {
                return lhsEnabled
            }
            return lhs.displayName < rhs.displayName
        }
    }

    /// Determine what state the autocomplete menu should be in
    /// - Parameter input: Current text input
    /// - Returns: The menu state (hidden, showingCommands, showingTools, showingUseTools)
    func getMenuState(for input: String) -> SlashMenuState {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("/") else {
            return .hidden
        }

        let afterSlash = String(trimmed.dropFirst())

        // Check if we're in the /use submenu phase (invoke tool)
        if afterSlash.lowercased().hasPrefix("use ") {
            let toolFilter = String(afterSlash.dropFirst(4)) // Remove "use "
            return .showingUseTools(filter: toolFilter)
        }

        // Check if we're in the /tool submenu phase (show definition)
        if afterSlash.lowercased().hasPrefix("tool ") {
            let toolFilter = String(afterSlash.dropFirst(5)) // Remove "tool "
            return .showingTools(filter: toolFilter)
        }

        // Otherwise show command suggestions
        return .showingCommands
    }
}

/// State of the slash command autocomplete menu
enum SlashMenuState: Equatable {
    case hidden
    case showingCommands
    case showingTools(filter: String)         // For /tool - show definition
    case showingUseTools(filter: String)      // For /use - invoke tool
}
