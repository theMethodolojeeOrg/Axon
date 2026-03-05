//
//  ToolSettings.swift
//  Axon
//
//  Tool settings and execution mode
//

import Foundation

// MARK: - Tool Execution Mode

/// Controls when tool requests are executed during a conversation
enum ToolExecutionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Tools execute automatically as soon as they're streamed from the assistant
    case immediate

    /// Tools show "Apply" button; results are sent with the user's next message
    case deferred

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .immediate: return "Immediate"
        case .deferred: return "Deferred"
        }
    }

    var description: String {
        switch self {
        case .immediate: return "Execute tools automatically as they stream"
        case .deferred: return "Review and apply tools manually"
        }
    }

    var icon: String {
        switch self {
        case .immediate: return "bolt.fill"
        case .deferred: return "hand.tap.fill"
        }
    }
}

// MARK: - Tool Settings

/// Settings for AI tool use (web search, code execution, etc.)
struct ToolSettings: Codable, Equatable, Sendable {
    /// Master toggle for tool use
    var toolsEnabled: Bool = false

    /// Set of enabled tool IDs
    var enabledToolIds: Set<String> = []

    /// Maximum tool calls per conversation turn
    var maxToolCallsPerTurn: Int = 5

    /// Tool execution timeout in seconds
    var toolTimeout: Int = 30

    /// Enable experimental features
    var experimentalFeaturesEnabled: Bool = false

    /// Enable Gemini media proxy for video/audio understanding (experimental)
    /// When enabled, video/audio attachments sent to non-Gemini providers
    /// will be analyzed by Gemini first, with the analysis passed to the primary model
    var mediaProxyEnabled: Bool = false

    /// Enable chat debug mode (developer feature)
    /// Shows detailed context breakdown, token counts, and injection details in chat
    var chatDebugEnabled: Bool = false

    /// Tool execution mode: immediate (auto-execute) or deferred (manual apply)
    var executionMode: ToolExecutionMode = .immediate

    /// Enable system-prompt guidance for multi-file artifact output (`language:path/to/file.ext` fences)
    var multiFileArtifactsEnabled: Bool = true

    private enum CodingKeys: String, CodingKey {
        case toolsEnabled
        case enabledToolIds
        case maxToolCallsPerTurn
        case toolTimeout
        case experimentalFeaturesEnabled
        case mediaProxyEnabled
        case chatDebugEnabled
        case executionMode
        case multiFileArtifactsEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .toolsEnabled) ?? false
        enabledToolIds = try container.decodeIfPresent(Set<String>.self, forKey: .enabledToolIds) ?? []
        maxToolCallsPerTurn = try container.decodeIfPresent(Int.self, forKey: .maxToolCallsPerTurn) ?? 5
        toolTimeout = try container.decodeIfPresent(Int.self, forKey: .toolTimeout) ?? 30
        experimentalFeaturesEnabled = try container.decodeIfPresent(Bool.self, forKey: .experimentalFeaturesEnabled) ?? false
        mediaProxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaProxyEnabled) ?? false
        chatDebugEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatDebugEnabled) ?? false
        executionMode = try container.decodeIfPresent(ToolExecutionMode.self, forKey: .executionMode) ?? .immediate
        multiFileArtifactsEnabled = try container.decodeIfPresent(Bool.self, forKey: .multiFileArtifactsEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolsEnabled, forKey: .toolsEnabled)
        try container.encode(enabledToolIds, forKey: .enabledToolIds)
        try container.encode(maxToolCallsPerTurn, forKey: .maxToolCallsPerTurn)
        try container.encode(toolTimeout, forKey: .toolTimeout)
        try container.encode(experimentalFeaturesEnabled, forKey: .experimentalFeaturesEnabled)
        try container.encode(mediaProxyEnabled, forKey: .mediaProxyEnabled)
        try container.encode(chatDebugEnabled, forKey: .chatDebugEnabled)
        try container.encode(executionMode, forKey: .executionMode)
        try container.encode(multiFileArtifactsEnabled, forKey: .multiFileArtifactsEnabled)
    }

    /// Helper to check if a specific tool is enabled
    func isToolEnabled(_ tool: ToolId) -> Bool {
        toolsEnabled && enabledToolIds.contains(tool.rawValue)
    }

    /// Helper to get enabled tools as ToolId array
    var enabledTools: [ToolId] {
        enabledToolIds.compactMap { ToolId(rawValue: $0) }
    }

    /// Enable a tool
    mutating func enableTool(_ tool: ToolId) {
        enabledToolIds.insert(tool.rawValue)
    }

    /// Disable a tool
    mutating func disableTool(_ tool: ToolId) {
        enabledToolIds.remove(tool.rawValue)
    }

    /// Toggle a tool
    mutating func toggleTool(_ tool: ToolId) {
        if enabledToolIds.contains(tool.rawValue) {
            enabledToolIds.remove(tool.rawValue)
        } else {
            enabledToolIds.insert(tool.rawValue)
        }
    }

    /// Enable all tools in a category
    mutating func enableCategory(_ category: ToolCategory) {
        let tools = ToolId.tools(for: category)
        for tool in tools {
            enableTool(tool)
        }
    }

    /// Disable all tools in a category
    mutating func disableCategory(_ category: ToolCategory) {
        let tools = ToolId.tools(for: category)
        for tool in tools {
            disableTool(tool)
        }
    }

    /// Check if all tools in a category are enabled
    func isCategoryFullyEnabled(_ category: ToolCategory) -> Bool {
        let tools = ToolId.tools(for: category)
        return tools.allSatisfy { isToolEnabled($0) }
    }

    /// Check if any tools in a category are enabled
    func isCategoryPartiallyEnabled(_ category: ToolCategory) -> Bool {
        let tools = ToolId.tools(for: category)
        return tools.contains { isToolEnabled($0) }
    }

    /// Count of enabled tools in a category
    func enabledCountForCategory(_ category: ToolCategory) -> Int {
        let tools = ToolId.tools(for: category)
        return tools.filter { isToolEnabled($0) }.count
    }
}
