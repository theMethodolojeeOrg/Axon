//
//  StreamingTypes.swift
//  Axon
//
//  Core types for streaming responses and real-time tool call visibility.
//  Enables true SSE streaming from AI providers with inline tool progress.
//

import Foundation
import Combine

// MARK: - Streaming Event Types

/// Events emitted during streaming response generation
enum StreamingEvent: Sendable {
    /// Incremental text chunk from Axon's response
    case textDelta(String)

    /// Reasoning token delta (for reasoning models like DeepSeek, o1)
    case reasoningDelta(String)

    /// Tool execution is starting
    case toolCallStart(LiveToolCall)

    /// Tool execution progress update
    case toolCallProgress(String, ToolCallProgress)

    /// Tool execution completed (success or failure)
    case toolCallComplete(String, ToolCallResult)

    /// Final completion with all metadata
    case completion(StreamingCompletion)

    /// Error during streaming
    case error(StreamingError)
}

// MARK: - Tool Call State

/// State of a tool call during execution
enum ToolCallState: String, Codable, Sendable {
    case pending     // Queued but not started
    case running     // Currently executing
    case success     // Completed successfully
    case failure     // Failed with error
}

// MARK: - Tool Call Progress

/// Progress update for a running tool
struct ToolCallProgress: Sendable {
    let state: ToolCallState
    let statusMessage: String?
    let startedAt: Date
    let elapsedMs: Int
}

// MARK: - Live Tool Call

/// Live tool call displayed inline during streaming
struct LiveToolCall: Identifiable, Sendable, Equatable, Codable {
    let id: String
    let name: String
    let displayName: String
    let icon: String
    var state: ToolCallState
    var request: ToolCallRequest?
    var result: ToolCallResult?
    var startedAt: Date
    var completedAt: Date?
    var statusMessage: String?

    /// Duration of the tool call (nil if still running)
    var duration: TimeInterval? {
        guard let completed = completedAt else { return nil }
        return completed.timeIntervalSince(startedAt)
    }

    /// Duration so far (for running tools)
    var elapsedDuration: TimeInterval {
        let end = completedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        displayName: String,
        icon: String,
        state: ToolCallState = .pending,
        request: ToolCallRequest? = nil,
        result: ToolCallResult? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.icon = icon
        self.state = state
        self.request = request
        self.result = result
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.statusMessage = statusMessage
    }

    static func == (lhs: LiveToolCall, rhs: LiveToolCall) -> Bool {
        lhs.id == rhs.id &&
        lhs.state == rhs.state &&
        lhs.completedAt == rhs.completedAt
    }
}

// MARK: - Tool Call Request

/// Tool call request details (for drawer display)
struct ToolCallRequest: Codable, Sendable, Equatable {
    let tool: String
    let query: String
    let rawJSON: String
    let timestamp: Date

    init(tool: String, query: String, rawJSON: String? = nil, timestamp: Date = Date()) {
        self.tool = tool
        self.query = query
        self.rawJSON = rawJSON ?? "{\"tool\": \"\(tool)\", \"query\": \"\(query)\"}"
        self.timestamp = timestamp
    }
}

// MARK: - Tool Call Result

/// Tool call result details (for drawer display)
struct ToolCallResult: Codable, Sendable, Equatable {
    let success: Bool
    let output: String
    let rawJSON: String?
    let sources: [StreamingToolSource]?
    let memoryOperation: MessageMemoryOperation?
    let duration: TimeInterval
    let timestamp: Date
    let errorMessage: String?

    init(
        success: Bool,
        output: String,
        rawJSON: String? = nil,
        sources: [StreamingToolSource]? = nil,
        memoryOperation: MessageMemoryOperation? = nil,
        duration: TimeInterval,
        timestamp: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.success = success
        self.output = output
        self.rawJSON = rawJSON
        self.sources = sources
        self.memoryOperation = memoryOperation
        self.duration = duration
        self.timestamp = timestamp
        self.errorMessage = errorMessage
    }
}

// MARK: - Streaming Tool Source

/// A source from tool results (web search, maps) for streaming context
struct StreamingToolSource: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let url: String
    let sourceType: MessageGroundingSource.SourceType

    init(id: String = UUID().uuidString, title: String, url: String, sourceType: MessageGroundingSource.SourceType = .web) {
        self.id = id
        self.title = title
        self.url = url
        self.sourceType = sourceType
    }

    /// Create from MessageGroundingSource
    init(from source: MessageGroundingSource) {
        self.id = source.id
        self.title = source.title
        self.url = source.url
        self.sourceType = source.sourceType
    }
}

// MARK: - Context Debug Info

/// Detailed breakdown of context window usage for debugging
struct ContextDebugInfo: Sendable, Codable, Equatable {
    /// Base system prompt token estimate
    let systemPromptTokens: Int

    /// Injected memories info
    let memoriesCount: Int
    let memoriesTokens: Int

    /// Grounded facts from epistemic engine
    let factsCount: Int
    let factsTokens: Int

    /// Conversation summary tokens
    let summaryTokens: Int

    /// Tool prompt tokens (when tools are enabled)
    let toolPromptTokens: Int

    /// Visible conversation messages tokens
    let messagesTokens: Int

    /// Total estimated tokens being sent
    var totalTokens: Int {
        systemPromptTokens + memoriesTokens + factsTokens + summaryTokens + toolPromptTokens + messagesTokens
    }

    /// Model's context window limit
    let contextWindowLimit: Int

    /// Model name for display
    let modelName: String

    /// Percentage of context used
    var usagePercentage: Double {
        guard contextWindowLimit > 0 else { return 0 }
        return min(Double(totalTokens) / Double(contextWindowLimit), 1.0)
    }

    /// Whether we're approaching or exceeding the limit
    var isNearLimit: Bool { usagePercentage > 0.8 }
    var isOverLimit: Bool { totalTokens > contextWindowLimit }

    /// Create empty debug info (when debug is disabled)
    static var empty: ContextDebugInfo {
        ContextDebugInfo(
            systemPromptTokens: 0,
            memoriesCount: 0,
            memoriesTokens: 0,
            factsCount: 0,
            factsTokens: 0,
            summaryTokens: 0,
            toolPromptTokens: 0,
            messagesTokens: 0,
            contextWindowLimit: 0,
            modelName: ""
        )
    }
}

// MARK: - Streaming Completion

/// Final streaming completion with all metadata
struct StreamingCompletion: Sendable {
    let fullContent: String
    let reasoning: String?
    let toolCalls: [LiveToolCall]
    let groundingSources: [MessageGroundingSource]
    let memoryOperations: [MessageMemoryOperation]
    let tokens: TokenUsage?
    let modelName: String?
    let providerName: String?
    let contextDebugInfo: ContextDebugInfo?

    init(
        fullContent: String,
        reasoning: String?,
        toolCalls: [LiveToolCall],
        groundingSources: [MessageGroundingSource],
        memoryOperations: [MessageMemoryOperation],
        tokens: TokenUsage?,
        modelName: String?,
        providerName: String?,
        contextDebugInfo: ContextDebugInfo? = nil
    ) {
        self.fullContent = fullContent
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.groundingSources = groundingSources
        self.memoryOperations = memoryOperations
        self.tokens = tokens
        self.modelName = modelName
        self.providerName = providerName
        self.contextDebugInfo = contextDebugInfo
    }
}

// MARK: - Streaming Errors

/// Errors that can occur during streaming
enum StreamingError: Error, Sendable {
    case connectionFailed(String)
    case providerError(Int, String)
    case parseError(String)
    case timeout
    case cancelled
    case unsupportedProvider(String)

    var localizedDescription: String {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .providerError(let code, let message):
            return "Provider error (\(code)): \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request cancelled"
        case .unsupportedProvider(let provider):
            return "Streaming not supported for provider: \(provider)"
        }
    }
}

// MARK: - Streaming State

/// Observable state for streaming UI
@MainActor
class StreamingState: ObservableObject {
    @Published var messageId: String?
    @Published var content: String = ""
    @Published var reasoning: String = ""
    @Published var toolCalls: [LiveToolCall] = []
    @Published var isStreaming: Bool = false
    @Published var error: StreamingError?

    func reset() {
        messageId = nil
        content = ""
        reasoning = ""
        toolCalls = []
        isStreaming = false
        error = nil
    }

    func appendText(_ text: String) {
        content += text
    }

    func appendReasoning(_ text: String) {
        reasoning += text
    }

    func addToolCall(_ toolCall: LiveToolCall) {
        toolCalls.append(toolCall)
    }

    func updateToolCall(id: String, state: ToolCallState, statusMessage: String? = nil) {
        if let index = toolCalls.firstIndex(where: { $0.id == id }) {
            toolCalls[index].state = state
            toolCalls[index].statusMessage = statusMessage
        }
    }

    func completeToolCall(id: String, result: ToolCallResult) {
        if let index = toolCalls.firstIndex(where: { $0.id == id }) {
            toolCalls[index].state = result.success ? .success : .failure
            toolCalls[index].result = result
            toolCalls[index].completedAt = Date()
        }
    }
}

// MARK: - Tool Display Helpers

extension LiveToolCall {
    /// Get display name for a tool
    static func displayName(for toolName: String) -> String {
        switch toolName {
        case "google_search": return "Web Search"
        case "code_execution": return "Code Execution"
        case "url_context": return "URL Fetch"
        case "google_maps": return "Google Maps"
        case "file_search": return "File Search"
        case "create_memory": return "Save Memory"
        case "conversation_search": return "Search Conversations"
        case "reflect_on_conversation": return "Reflect"
        case "vscode_read_file": return "Read File"
        case "vscode_write_file": return "Write File"
        case "vscode_list_directory": return "List Directory"
        case "vscode_list_files": return "List Files"
        case "vscode_run_terminal": return "Run Terminal"
        default: return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Get SF Symbol icon for a tool
    static func icon(for toolName: String) -> String {
        switch toolName {
        case "google_search": return "magnifyingglass"
        case "code_execution": return "terminal"
        case "url_context": return "link"
        case "google_maps": return "map"
        case "file_search": return "doc.text.magnifyingglass"
        case "create_memory": return "brain.head.profile"
        case "conversation_search": return "text.magnifyingglass"
        case "reflect_on_conversation": return "bubble.left.and.bubble.right"
        case "vscode_read_file": return "doc.text"
        case "vscode_write_file": return "square.and.pencil"
        case "vscode_list_directory": return "folder"
        case "vscode_list_files": return "folder"
        case "vscode_run_terminal": return "terminal"
        default: return "gear"
        }
    }

    /// Get status message for a running tool
    static func statusMessage(for toolName: String) -> String {
        switch toolName {
        case "google_search": return "Searching the web..."
        case "code_execution": return "Running code..."
        case "url_context": return "Fetching content..."
        case "google_maps": return "Looking up location..."
        case "file_search": return "Searching documents..."
        case "create_memory": return "Saving to memory..."
        case "conversation_search": return "Searching conversations..."
        case "reflect_on_conversation": return "Analyzing conversation..."
        case "vscode_read_file": return "Reading file..."
        case "vscode_write_file": return "Writing file..."
        case "vscode_list_directory": return "Listing directory..."
        case "vscode_list_files": return "Listing files..."
        case "vscode_run_terminal": return "Running command..."
        default: return "Executing..."
        }
    }

    /// Create a LiveToolCall from a tool name and query
    static func create(name: String, query: String) -> LiveToolCall {
        LiveToolCall(
            name: name,
            displayName: displayName(for: name),
            icon: icon(for: name),
            state: .running,
            request: ToolCallRequest(tool: name, query: query),
            statusMessage: statusMessage(for: name)
        )
    }
}

// MARK: - Conversion to Message Types

extension LiveToolCall {
    /// Convert to ToolCall for message persistence
    func toToolCall() -> ToolCall {
        ToolCall(
            id: id,
            name: name,
            arguments: request.flatMap { req in
                ["query": .string(req.query)]
            },
            result: result?.output,
            success: result?.success,
            errorMessage: result?.errorMessage
        )
    }
}

extension StreamingToolSource {
    /// Convert to MessageGroundingSource
    func toMessageGroundingSource() -> MessageGroundingSource {
        MessageGroundingSource(id: id, title: title, url: url, sourceType: sourceType)
    }
}
