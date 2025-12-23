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
            return try await executeV2Tool(toolId: toolId, query: query, context: context)
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
    func parseToolRequests(from response: String) -> [ParsedToolRequest] {
        // Use existing parsing logic - format is the same for both systems
        let pattern = #"```tool_request\s*\n(\{[^`]+\})\s*\n```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let nsRange = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, options: [], range: nsRange)

        return matches.compactMap { match -> ParsedToolRequest? in
            guard let jsonRange = Range(match.range(at: 1), in: response) else { return nil }
            let jsonString = String(response[jsonRange])

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tool = json["tool"] as? String else {
                return nil
            }

            let query = json["query"] as? String ?? ""
            return ParsedToolRequest(toolId: tool, query: query)
        }
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
