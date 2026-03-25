//
//  ToolRoutingService.swift
//  Axon
//
//  Unified tool routing service that checks V1/V2 toggle and routes to appropriate system.
//  Acts as the single entry point for all tool operations in the app.
//

import Foundation
import Combine
import os.log

// MARK: - Tool Routing Service

/// Unified tool routing service that bridges V1 and V2 tool systems
@MainActor
final class ToolRoutingService: ObservableObject {

    // MARK: - Singleton

    static let shared = ToolRoutingService()

    // MARK: - Dependencies

    private let toolsToggle = ToolsV2Toggle.shared
    private let pluginLoader = ToolPluginLoader.shared
    private let indexService = ToolIndexServiceV2.shared
    private let executionRouter = ToolExecutionRouterV2.shared

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ToolRoutingService"
    )

    // MARK: - Initialization

    private init() {
        logger.debug("ToolRoutingService initialized")
    }

    // MARK: - Tool Availability

    /// Check if any tools are available for use (V1 or V2)
    /// - Parameter enabledV1Tools: Set of enabled V1 tool IDs
    /// - Returns: True if tools are available and should trigger tool proxy mode
    func hasAnyToolsAvailable(enabledV1Tools: Set<String>) -> Bool {
        if toolsToggle.isV2Active {
            // V2 mode: check if any V2 tools are enabled
            return !pluginLoader.enabledTools.isEmpty
        } else {
            // V1 mode: check if any V1 tools are enabled
            return !enabledV1Tools.isEmpty
        }
    }

    // MARK: - System Prompt Generation

    /// Generate tool system prompt based on active tool system
    /// - Parameters:
    ///   - enabledToolIds: Set of enabled tool IDs (for V1 compatibility)
    ///   - maxToolCalls: Maximum tool calls per turn
    /// - Returns: System prompt string with tool descriptions
    func generateToolSystemPrompt(
        enabledToolIds: Set<String>,
        maxToolCalls: Int = 5
    ) async -> String {
        if toolsToggle.isV2Active {
            return generateV2SystemPrompt()
        } else {
            return await generateV1SystemPrompt(enabledToolIds: enabledToolIds, maxToolCalls: maxToolCalls)
        }
    }

    /// Generate V2 system prompt from loaded tools
    private func generateV2SystemPrompt() -> String {
        // Ensure tools are loaded
        if pluginLoader.loadedTools.isEmpty {
            Task {
                await pluginLoader.loadAllTools()
            }
        }
        
        // Get settings for max tool calls
        let maxToolCalls = SettingsStorage.shared.loadSettingsOrDefault().toolSettings.maxToolCallsPerTurn
        
        // Categorize tools
        let enabledTools = pluginLoader.loadedTools.filter { $0.isEnabled }
        let totalCount = enabledTools.count
        
        // Group by category
        var categoryCount: [String: Int] = [:]
        for tool in enabledTools {
            let category = tool.manifest.tool.category.displayName
            categoryCount[category, default: 0] += 1
        }
        
        // Build discovery prompt similar to V1's generateMinimalToolSystemPrompt
        var prompt = """
        
        ## Tool Discovery System
        
        You have access to \(totalCount) tool\(totalCount == 1 ? "" : "s") across the following categories:
        """
        
        // Sort categories for consistent output
        for (category, count) in categoryCount.sorted(by: { $0.key < $1.key }) {
            prompt += "\n- **\(category)**: \(count) tool\(count == 1 ? "" : "s")"
        }
        
        prompt += """
        
        
        **Tool Call Limit:** You may use up to \(maxToolCalls) tool call\(maxToolCalls == 1 ? "" : "s") per response.
        
        To discover and use these tools, use the following discovery tools:
        
        ### list_tools
        Get a compact catalog of available tools. Returns tool IDs, names, categories, and brief descriptions.
        
        **Query options:**
        - `enabled` (default) - Show only enabled tools
        - `all` - Show all tools (enabled and disabled)
        - Category name (e.g., `memory`, `search`) - Filter by category
        
        Example:
        ```tool_request
        {"tool": "list_tools", "query": "enabled"}
        ```
        
        ### get_tool_details
        Fetch full details (usage instructions, parameters, examples) for a specific tool by its ID.
        
        Example:
        ```tool_request
        {"tool": "get_tool_details", "query": "google_search"}
        ```
        
        **Workflow:** Use `list_tools` first to discover what's available, then use `get_tool_details` to get full usage instructions for any tool you want to use.

        **Important:** Only request ONE tool at a time. Wait for results before continuing.
        **Output Rule:** When invoking a tool, place the `tool_request` block at the END of your message. You may include brief reasoning before it. Do not write text after the block — execution pauses until the result arrives in a `tool_result` block.

        """
        
        // Add dynamic tools section if available
        prompt += DynamicToolConfigurationService.shared.generateSystemPromptSection()
        
        // Add VS Code bridge tools if connected
        if let workspace = BridgeToolExecutor.shared.workspaceInfo {
            prompt += BridgeToolId.generateSystemPrompt(
                workspaceName: workspace.name,
                workspaceRoot: workspace.root
            )
        }
        
        // Add port tools section
        prompt += generatePortToolsSection()
        
        return prompt
    }
    
    /// Generate port tools section for V2 system prompt
    private func generatePortToolsSection() -> String {
        let availablePorts = PortRegistry.shared.enabledPorts
        guard !availablePorts.isEmpty else { return "" }
        
        var section = """
        
        ### External App Integration (Ports)
        
        You can discover and invoke external apps via ports:
        
        **discover_ports** - List available external app integrations
        ```tool_request
        {"tool": "discover_ports", "query": "all"}
        ```
        
        **invoke_port** - Invoke a registered port action
        ```tool_request
        {"tool": "invoke_port", "query": "port_id|param1|param2"}
        ```
        
        """
        
        return section
    }

    /// Generate V1 system prompt via ToolProxyService
    private func generateV1SystemPrompt(enabledToolIds: Set<String>, maxToolCalls: Int) async -> String {
        let toolIds = Set(enabledToolIds.compactMap { ToolId(rawValue: $0) })
        return await ToolProxyService.shared.generateMinimalToolSystemPrompt(
            enabledTools: toolIds,
            maxToolCalls: maxToolCalls
        )
    }

    // MARK: - V1 to V2 Compatibility Aliases

    /// Maps V1 tool IDs to their V2 equivalents for backward compatibility
    private let v1ToV2Aliases: [String: String] = [
        // VS Code bridge tools → Mac equivalents (when running on Mac without bridge)
        "vscode_read_file": "mac_file_read",
        "vscode_list_files": "mac_file_find",
        // Legacy aliases
        "google_search": "gemini_google_search",
        "code_execution": "gemini_code_execution",
        "url_context": "gemini_url_context",
        "google_maps": "gemini_google_maps",
        "file_search": "gemini_file_search",
        "openai_image_gen": "openai_image_generation",
        "openai_video_gen": "openai_video_generation",
        "xai_web_search": "grok_web_search",
        "zai_web_search": "glm_web_search",
        "gemini_veo": "gemini_video_generation"
    ]

    /// Resolve a tool ID, checking for V1 aliases
    private func resolveToolId(_ toolId: String) -> String {
        // First check if this is a V1 alias that should map to V2
        if let v2Id = v1ToV2Aliases[toolId] {
            // Only use alias if the V2 tool exists
            if pluginLoader.hasToolId(v2Id) {
                logger.debug("Resolved V1 tool '\(toolId)' to V2 tool '\(v2Id)'")
                return v2Id
            }
        }
        return toolId
    }

    // MARK: - Tool Execution

    /// Execute a tool by ID, routing to V1 or V2 based on toggle
    /// - Parameters:
    ///   - toolId: Tool identifier
    ///   - query: Input query or parameters
    ///   - context: Additional context (V2 only)
    /// - Returns: Tool result as string
    func executeTool(
        toolId: String,
        query: String,
        context: ToolContextV2 = .empty
    ) async throws -> ToolExecutionResult {
        if toolsToggle.isV2Active {
            // Resolve V1 aliases to V2 tool IDs
            let resolvedId = resolveToolId(toolId)
            return try await executeV2Tool(toolId: resolvedId, query: query, context: context)
        } else {
            return try await executeV1Tool(toolId: toolId, query: query)
        }
    }

    /// Execute a V2 tool
    private func executeV2Tool(
        toolId: String,
        query: String,
        context: ToolContextV2
    ) async throws -> ToolExecutionResult {
        let result = try await executionRouter.executeToolV2(
            toolId: toolId,
            rawInput: query,
            context: context
        )

        // Convert metadata to dictionary if present
        var metadataDict: [String: Any]?
        if let metadata = result.metadata {
            var dict: [String: Any] = [
                "executionTimeMs": metadata.executionTimeMs,
                "handlerUsed": metadata.handlerUsed
            ]
            if let approvalId = metadata.approvalRecordId {
                dict["approvalRecordId"] = approvalId
            }
            if let extra = metadata.extra {
                dict["extra"] = extra
            }
            metadataDict = dict
        }

        return ToolExecutionResult(
            success: result.success,
            output: result.output,
            metadata: metadataDict,
            groundingSources: nil, // V2 sources would need conversion
            memoryOperation: nil // V2 memory ops would need conversion
        )
    }

    /// Execute a V1 tool via ToolProxyService
    private func executeV1Tool(
        toolId: String,
        query: String
    ) async throws -> ToolExecutionResult {
        // V1 execution goes through ToolProxyService
        // Get API keys from settings
        let settings = await MainActor.run { SettingsStorage.shared.loadSettingsOrDefault() }
        let geminiKey = (try? APIKeysStorage.shared.getAPIKey(for: .gemini)) ?? ""
        
        let toolRequest = ToolRequest(tool: toolId, query: query)
        let toolResult = try await ToolProxyService.shared.executeToolRequest(
            toolRequest,
            geminiApiKey: geminiKey,
            conversationContext: nil
        )
        
        // Convert V1 ToolResult to ToolExecutionResult
        var groundingSources: [MessageGroundingSource]?
        if let sources = toolResult.sources {
            groundingSources = sources.map { source in
                MessageGroundingSource(
                    title: source.title,
                    url: source.url,
                    sourceType: toolId == "google_maps" ? .maps : .web
                )
            }
        }
        
        return ToolExecutionResult(
            success: toolResult.success,
            output: toolResult.result,
            metadata: nil,
            groundingSources: groundingSources,
            memoryOperation: toolResult.memoryOperation
        )
    }

    // MARK: - Tool Discovery

    /// Check if a tool exists and is available
    func isToolAvailable(_ toolId: String) -> Bool {
        if toolsToggle.isV2Active {
            return pluginLoader.hasToolId(toolId) &&
                   (pluginLoader.tool(byId: toolId)?.isEnabled ?? false)
        } else {
            return ToolId(rawValue: toolId) != nil
        }
    }

    /// Get list of enabled tool IDs
    func getEnabledToolIds() -> Set<String> {
        if toolsToggle.isV2Active {
            return pluginLoader.enabledToolIds
        } else {
            // V1 enabled tools come from Settings
            let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
            return settings.toolSettings.enabledToolIds
        }
    }

    /// Get tool name for display
    func getToolDisplayName(_ toolId: String) -> String {
        if toolsToggle.isV2Active {
            return pluginLoader.tool(byId: toolId)?.name ?? toolId
        } else {
            return ToolId(rawValue: toolId)?.displayName ?? toolId
        }
    }

    // MARK: - Parse Tool Requests

    /// Parse tool request from AI response
    /// Works for both V1 and V2 (same format)
    /// Now matches V1's flexible parsing: supports multiple field names, nested parameters, and backticks in content
    func parseToolRequests(from response: String) -> [ParsedToolRequest] {
        // Match V1's regex pattern - captures any content between fences (not just {[^`]+})
        // This allows backticks inside JSON string values
        let pattern = "```tool_request\\s*\\n?([\\s\\S]*?)\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsRange = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, options: [], range: nsRange)

        return matches.compactMap { match -> ParsedToolRequest? in
            guard let jsonRange = Range(match.range(at: 1), in: response) else { return nil }
            let jsonString = String(response[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tool = json["tool"] as? String else {
                return nil
            }

            // Extract query with V1-compatible field name fallbacks and nested parameters support
            let query = extractQuery(from: json, toolId: tool)
            let content = extractContent(from: json)

            return ParsedToolRequest(toolId: tool, query: query, content: content)
        }
    }

    /// Extract query value with V1-compatible fallbacks
    /// Supports: query, memory, content, input, data, path keys
    /// Also handles nested {"tool": "x", "parameters": {"query": "..."}} format
    private func extractQuery(from json: [String: Any], toolId: String) -> String {
        // Check for nested parameters object first (common AI format)
        if let params = json["parameters"] as? [String: Any] {
            if let q = params["query"] as? String { return q }
            if let q = params["path"] as? String { return q }
            if let q = params["input"] as? String { return q }
        }

        // Flat format: try multiple possible key names (matching V1's ToolRequest decoder)
        if let q = json["query"] as? String { return q }
        if let q = json["memory"] as? String { return q }
        if let q = json["path"] as? String { return q }
        if let q = json["input"] as? String { return q }
        if let q = json["data"] as? String { return q }

        // Special case: reflect_on_conversation sends options as top-level fields
        // Reconstruct them as JSON query (matching V1 behavior)
        if toolId == "reflect_on_conversation" {
            var optionsDict: [String: Any] = [:]
            for (key, value) in json where key != "tool" {
                optionsDict[key] = value
            }
            if !optionsDict.isEmpty,
               let jsonData = try? JSONSerialization.data(withJSONObject: optionsDict, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        }

        // For content-only requests, use content as query if no query field
        if let c = json["content"] as? String { return c }

        // Default to empty string for tools that don't require parameters
        return ""
    }

    /// Extract separate content field if present (for write operations)
    private func extractContent(from json: [String: Any]) -> String? {
        // Check nested parameters first
        if let params = json["parameters"] as? [String: Any],
           let content = params["content"] as? String {
            return content
        }

        // Check flat format - only return content if query also exists (to distinguish from content-as-query)
        if json["query"] != nil || json["path"] != nil || json["input"] != nil {
            return json["content"] as? String
        }

        return nil
    }
}

// MARK: - Supporting Types

/// Result from tool execution
struct ToolExecutionResult {
    let success: Bool
    let output: String
    let metadata: [String: Any]?
    let groundingSources: [MessageGroundingSource]?
    let memoryOperation: MessageMemoryOperation?  // For create_memory tool results
}

/// Parsed tool request from AI response
struct ParsedToolRequest {
    let toolId: String
    let query: String
    let content: String?  // Separate content field for write operations (e.g., file writes)

    init(toolId: String, query: String, content: String? = nil) {
        self.toolId = toolId
        self.query = query
        self.content = content
    }
}

/// Errors from tool routing
enum ToolRoutingError: LocalizedError {
    case toolNotFound(String)
    case toolNotEnabled(String)
    case v1PathNotRouted(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let id):
            return "Tool not found: \(id)"
        case .toolNotEnabled(let id):
            return "Tool not enabled: \(id)"
        case .v1PathNotRouted(let reason):
            return "V1 tool path: \(reason)"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}

// MARK: - Convenience Extensions

extension ToolRoutingService {

    /// Quick check if V2 system is active
    var isV2Active: Bool {
        toolsToggle.isV2Active
    }

    /// Active system version for display
    var activeSystemName: String {
        toolsToggle.activeVersion.displayName
    }

    /// Reload tools for active system
    func reloadTools() async {
        if toolsToggle.isV2Active {
            await pluginLoader.loadAllTools()
        }
        // V1 doesn't need explicit reload - tools are loaded from Settings
    }
}
