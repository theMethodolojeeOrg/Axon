//
//  ToolProxyService.swift
//  Axon
//
//  Tool proxy service that enables any AI model (Claude, GPT, etc.) to use Gemini tools.
//  The primary model decides when to use tools, and Gemini executes them.
//
//  Flow:
//  1. Inject tool descriptions into system prompt
//  2. Primary model responds with tool requests (JSON format)
//  3. Parse tool requests from response
//  4. Execute tools via GeminiToolService
//  5. Feed tool results back to primary model for final response
//

import Foundation
import CoreLocation
import Combine

// MARK: - Tool Proxy Service

@MainActor
class ToolProxyService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = ToolProxyService()

    // MARK: - Dependencies

    private let dynamicToolConfig = DynamicToolConfigurationService.shared
    private let dynamicToolEngine = DynamicToolExecutionEngine.shared

    // Location manager for Maps queries
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocationCoordinate2D?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Tool System Prompt

    /// Generate system prompt injection describing available tools
    /// - Parameters:
    ///   - enabledTools: Set of tool IDs that are enabled
    ///   - maxToolCalls: Maximum number of tool calls allowed per turn (from settings)
    func generateToolSystemPrompt(enabledTools: Set<ToolId>, maxToolCalls: Int = 5) -> String {
        guard !enabledTools.isEmpty else { return "" }

        var prompt = """

        ## Available Tools

        You have access to the following tools. When you need real-time information, current data, or to perform calculations, you can request a tool be executed by responding with a JSON tool request block.

        **Tool Call Limit:** You may use up to \(maxToolCalls) tool call\(maxToolCalls == 1 ? "" : "s") per response. Plan your tool usage efficiently.

        To use a tool, include a code block with the tool request in this exact format:
        ```tool_request
        {"tool": "tool_name", "query": "your query or request"}
        ```

        Available tools:

        """

        for tool in enabledTools {
            switch tool {
            case .googleSearch:
                prompt += """

                ### google_search
                Search the web for current information. Use for recent news, current prices, weather, stocks, or anything requiring up-to-date information.
                Example: ```tool_request
                {"tool": "google_search", "query": "current weather in Tokyo"}
                ```

                """

            case .codeExecution:
                prompt += """

                ### code_execution
                Execute Python code in a sandbox. Use for calculations, data analysis, or generating charts.
                Example: ```tool_request
                {"tool": "code_execution", "query": "Calculate the first 20 prime numbers"}
                ```

                """

            case .urlContext:
                prompt += """

                ### url_context
                Fetch and analyze content from a URL. Use for reading articles or documentation.
                Example: ```tool_request
                {"tool": "url_context", "query": "Summarize https://example.com/article"}
                ```

                """

            case .googleMaps:
                prompt += """

                ### google_maps
                Query Google Maps for location information. Use for finding nearby places or getting business info.
                Example: ```tool_request
                {"tool": "google_maps", "query": "Best Italian restaurants near me"}
                ```

                """

            case .fileSearch:
                prompt += """

                ### file_search
                Search through uploaded documents using semantic RAG (Retrieval-Augmented Generation). Use for finding information in PDFs, documents, or other uploaded files.
                Example: ```tool_request
                {"tool": "file_search", "query": "Find sections about authentication in the documentation"}
                ```

                """

            case .createMemory:
                prompt += """

                ### create_memory
                Save important information to memory for future conversations. Use this to remember facts about the user, their preferences, important context, or insights.

                **Memory Types:**
                - `allocentric`: Facts ABOUT the user (preferences, background, relationships, what they like/dislike)
                - `egoic`: What WORKS for you in this agentic context (approaches, techniques, insights, learnings about how to help them)

                **Format:**
                ```tool_request
                {"tool": "create_memory", "query": "TYPE|CONFIDENCE|TAGS|CONTENT"}
                ```

                **Parameters (pipe-separated):**
                - TYPE: Either "allocentric" or "egoic"
                - CONFIDENCE: 0.0-1.0 (how certain you are)
                - TAGS: Retrieval context keywords - when should this memory surface? (e.g., "debugging,swift-help" not just "swift")
                - CONTENT: The actual fact or insight to remember

                **What to Remember:**
                - DO save: User preferences, project context, communication styles, successful approaches
                - DON'T save: Tool usage documentation, system internals, format specifications (these are in the system prompt)

                **Examples:**
                ```tool_request
                {"tool": "create_memory", "query": "allocentric|0.9|ios-development,language-choice|User prefers Swift over Objective-C for iOS development"}
                ```
                ```tool_request
                {"tool": "create_memory", "query": "egoic|0.8|explaining-code,teaching|User responds well to concise explanations with code examples"}
                ```

                """

            case .conversationSearch:
                prompt += """

                ### conversation_search
                Search through your recent conversation history for context from previous discussions. Use when the user references past conversations, asks "remember when we discussed...", "what did you say about...", or needs context from earlier chats.
                Example: ```tool_request
                {"tool": "conversation_search", "query": "What did we discuss about the authentication system?"}
                ```

                """

            case .reflectOnConversation:
                prompt += """

                ### reflect_on_conversation
                Analyze the current conversation to understand model usage patterns, task distribution, memory operations, and topic shifts. Use this to gain meta-awareness about how the conversation has been handled across different substrates.

                **Note:** This tool requires user approval before execution.

                **Options:**
                - `show_model_timeline`: Show which models handled which messages (default: true)
                - `show_task_distribution`: Show what types of tasks each model handled (default: true)
                - `show_memory_usage`: Show memory retrieval and creation events (default: true)

                **Returns:**
                - Model timeline: Which models handled which messages
                - Task distribution: What each substrate was best at
                - Memory usage: Which memories were retrieved/created when
                - Pivots: Where the conversation shifted topics or tasks
                - Insights: Patterns about model strengths and handoffs

                Example (flat format): ```tool_request
                {"tool": "reflect_on_conversation", "show_model_timeline": true, "show_task_distribution": true, "show_memory_usage": true}
                ```

                """

            }
        }

        prompt += """

        **Important:** Only request ONE tool at a time. Wait for results before continuing.

        """

        // Add dynamic tools section
        prompt += dynamicToolConfig.generateSystemPromptSection()

        // Add VS Code bridge tools if connected
        if let workspace = BridgeToolExecutor.shared.workspaceInfo {
            prompt += BridgeToolId.generateSystemPrompt(
                workspaceName: workspace.name,
                workspaceRoot: workspace.root
            )
        }

        return prompt
    }

    // MARK: - Parse Tool Requests

    /// Parse tool requests from model response
    func parseToolRequest(from response: String) -> ToolRequest? {
        let pattern = "```tool_request\\s*\\n?([\\s\\S]*?)\\n?```"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
              let jsonRange = Range(match.range(at: 1), in: response) else {
            return nil
        }

        let jsonString = String(response[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            print("[ToolProxy] Failed to convert tool request to data: \(jsonString)")
            return nil
        }

        do {
            let request = try JSONDecoder().decode(ToolRequest.self, from: data)
            print("[ToolProxy] Parsed tool request: \(request.tool)")
            return request
        } catch {
            print("[ToolProxy] Failed to decode tool request: \(error). JSON: \(jsonString)")
            return nil
        }
    }

    /// Detect "naked" memory format sent as plain text without proper tool_request wrapper
    /// Returns the detected raw memory string if found, nil otherwise
    func detectNakedMemoryFormat(in response: String) -> String? {
        // Pattern: starts with allocentric| or egoic| followed by a decimal, pipe, tags, pipe, content
        // Must appear at start of line or after whitespace, and be substantial (not just a fragment)
        let pattern = "(?:^|\\n|\\s)((?:allocentric|egoic)\\|\\d+\\.?\\d*\\|[^|]+\\|.{10,})"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
              let captureRange = Range(match.range(at: 1), in: response) else {
            return nil
        }

        let captured = String(response[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Make sure this isn't already inside a tool_request block (avoid double-detection)
        if response.contains("```tool_request") && response.contains(captured) {
            // Check if the captured text appears inside a code block
            let codeBlockPattern = "```[\\s\\S]*?\(NSRegularExpression.escapedPattern(for: captured))[\\s\\S]*?```"
            if let codeBlockRegex = try? NSRegularExpression(pattern: codeBlockPattern, options: []),
               codeBlockRegex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)) != nil {
                return nil // It's properly wrapped, don't flag it
            }
        }

        print("[ToolProxy] Detected naked memory format: \(captured.prefix(50))...")
        return captured
    }

    /// Detect JSON-structured memory object sent instead of pipe-delimited format
    /// Models sometimes try to be "helpful" by sending {"type":"allocentric","confidence":0.9,...}
    /// Returns parsed components if detected, nil otherwise
    func detectJSONMemoryFormat(in response: String) -> (type: String, confidence: Double, tags: [String], content: String)? {
        // First, check if this looks like it might contain a memory JSON object
        let lowercased = response.lowercased()
        guard lowercased.contains("\"type\"") &&
              (lowercased.contains("allocentric") || lowercased.contains("egoic")) &&
              lowercased.contains("\"content\"") else {
            return nil
        }

        // Find candidate JSON objects by looking for { ... } windows
        // Use a bracket-matching approach for robustness
        var searchStart = response.startIndex

        while searchStart < response.endIndex {
            guard let openBrace = response[searchStart...].firstIndex(of: "{") else { break }

            // Find matching close brace using bracket counting
            var depth = 0
            var closeBrace: String.Index? = nil

            for idx in response.indices[openBrace...] {
                let char = response[idx]
                if char == "{" { depth += 1 }
                else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        closeBrace = idx
                        break
                    }
                }
                // Safety: don't scan more than 500 chars from open brace
                if response.distance(from: openBrace, to: idx) > 500 { break }
            }

            guard let closeIdx = closeBrace else {
                searchStart = response.index(after: openBrace)
                continue
            }

            let candidateRange = openBrace...closeIdx
            let candidateString = String(response[candidateRange])

            // Check if this candidate is inside a ```tool_request block
            let beforeCandidate = String(response[..<openBrace])
            let afterCandidate = String(response[response.index(after: closeIdx)...])

            // Find the last ```tool_request before our candidate
            if let lastToolRequestStart = beforeCandidate.range(of: "```tool_request", options: .backwards) {
                // Check if there's a closing ``` between tool_request and our candidate
                let afterToolRequest = beforeCandidate[lastToolRequestStart.upperBound...]
                if !afterToolRequest.contains("```") {
                    // We're inside an unclosed tool_request block - check if it closes after our candidate
                    if afterCandidate.contains("```") {
                        // This JSON is properly inside a tool_request block, skip it
                        searchStart = response.index(after: closeIdx)
                        continue
                    }
                }
            }

            // Try to parse as JSON
            guard let data = candidateString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  (type.lowercased() == "allocentric" || type.lowercased() == "egoic") else {
                searchStart = response.index(after: openBrace)
                continue
            }

            // Found a valid memory JSON object outside of tool_request block!
            let confidence = (json["confidence"] as? Double) ?? 0.8
            let content = (json["content"] as? String) ?? (json["memory"] as? String) ?? (json["text"] as? String) ?? ""

            var tags: [String] = []
            if let tagsArray = json["tags"] as? [String] {
                tags = tagsArray
            } else if let tagsString = json["tags"] as? String {
                tags = tagsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }

            guard !content.isEmpty else {
                searchStart = response.index(after: closeIdx)
                continue
            }

            print("[ToolProxy] Detected JSON memory format: type=\(type), content=\(content.prefix(30))...")
            return (type: type.lowercased(), confidence: confidence, tags: tags, content: content)
        }

        return nil
    }

    /// Properly escape a string for use inside JSON
    private func jsonEscape(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        out = out.replacingOccurrences(of: "\r", with: "\\r")
        out = out.replacingOccurrences(of: "\t", with: "\\t")
        return out
    }

    /// Generate corrective feedback for JSON memory format
    func generateJSONMemoryFeedback(type: String, confidence: Double, tags: [String], content: String) -> String {
        let tagsString = tags.joined(separator: ",")
        // Format confidence to 2 decimal places and clamp to [0,1]
        let clampedConfidence = min(1.0, max(0.0, confidence))
        let confStr = String(format: "%.2f", clampedConfidence)
        let pipeFormat = "\(type)|\(confStr)|\(tagsString)|\(content)"

        return """
            🤓 **NICE TRY NERD!** You sent a JSON object with memory fields, but this tool uses a simple pipe-delimited string format, not JSON.

            **You sent:** A JSON object with type, confidence, tags, content fields

            **But create_memory expects this format:**
            ```tool_request
            {"tool": "create_memory", "query": "\(jsonEscape(pipeFormat))"}
            ```

            **The `query` value is a pipe-delimited string:** `TYPE|CONFIDENCE|TAGS|CONTENT`

            NOT a nested JSON object. The outer JSON has `tool` and `query` keys only. Please retry with the exact format above.
            """
    }

    /// Generate corrective feedback for naked memory format
    func generateNakedMemoryFeedback(rawMemory: String) -> String {
        return """
            🙃 **ALMOST!** You sent the memory in the right pipe-delimited format, but forgot to wrap it in the tool_request JSON block.

            **You sent:**
            `\(rawMemory.prefix(80))...`

            **You need to wrap it like this:**
            ```tool_request
            {"tool": "create_memory", "query": "\(jsonEscape(rawMemory))"}
            ```

            The system can only execute tools when they're inside a properly formatted `tool_request` code block with valid JSON. Please retry with the exact format above.
            """
    }

    /// Remove tool request block from response text
    func removeToolRequest(from response: String) -> String {
        let pattern = "```tool_request\\s*\\n?[\\s\\S]*?\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return response
        }

        let result = regex.stringByReplacingMatches(
            in: response,
            options: [],
            range: NSRange(response.startIndex..., in: response),
            withTemplate: ""
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Execute Tool

    /// Execute a tool request via Gemini and return formatted results
    /// - Parameters:
    ///   - request: The tool request to execute
    ///   - geminiApiKey: API key for Gemini-based tools
    ///   - conversationContext: Optional context for tools that need conversation access (e.g., reflect_on_conversation)
    func executeToolRequest(
        _ request: ToolRequest,
        geminiApiKey: String,
        conversationContext: ToolConversationContext? = nil
    ) async throws -> ToolResult {
        // First, check if this is a VS Code bridge tool
        if request.tool.hasPrefix("vscode_") {
            return await BridgeToolExecutor.shared.execute(request)
        }

        // Check if this is a dynamic tool
        if let dynamicTool = dynamicToolConfig.tool(withId: request.tool), dynamicTool.enabled {
            return try await executeDynamicTool(request: request, tool: dynamicTool)
        }

        // Otherwise, handle as built-in tool
        guard let toolId = ToolId(rawValue: request.tool) else {
            return ToolResult(
                tool: request.tool,
                success: false,
                result: "Unknown tool: \(request.tool)",
                sources: nil,
                memoryOperation: nil
            )
        }

        // Handle internal tools (no Gemini API needed)
        if toolId.provider == .internal {
            // Check if this internal tool requires approval
            if toolId.requiresApproval {
                return await executeInternalToolWithApproval(
                    toolId: toolId,
                    query: request.query,
                    context: conversationContext
                )
            }
            return await executeInternalTool(toolId: toolId, query: request.query, context: conversationContext)
        }

        // Get location for Maps queries
        var userLocation: CLLocationCoordinate2D? = nil
        if toolId == .googleMaps {
            userLocation = await getCurrentLocation()
        }

        // Execute via Gemini with the specific tool
        let toolResponse = try await GeminiToolService.shared.generateWithTools(
            apiKey: geminiApiKey,
            model: "gemini-2.5-flash",
            messages: [Message(conversationId: "", role: .user, content: request.query)],
            system: nil,
            enabledTools: Set([toolId]),
            userLocation: userLocation
        )

        // Format sources if available
        var sources: [ToolResultSource]? = nil
        if !toolResponse.webSources.isEmpty {
            sources = toolResponse.webSources.map { chunk in
                ToolResultSource(
                    title: chunk.title,
                    url: chunk.uri ?? ""
                )
            }
        }

        return ToolResult(
            tool: request.tool,
            success: true,
            result: toolResponse.text,
            sources: sources,
            memoryOperation: nil
        )
    }

    /// Execute internal tools (conversation search, memory, reflection, etc.)
    private func executeInternalTool(toolId: ToolId, query: String, context: ToolConversationContext?) async -> ToolResult {
        switch toolId {
        case .reflectOnConversation:
            return await executeReflectOnConversation(query: query, context: context)

        case .conversationSearch:
            // Search recent conversations
            let searchResults = await ConversationSearchService.shared.searchConversations(
                query: query,
                limit: 5,
                maxAgeDays: 14
            )

            if searchResults.isEmpty {
                return ToolResult(
                    tool: toolId.rawValue,
                    success: true,
                    result: "No relevant past conversations found for this query.",
                    sources: nil,
                    memoryOperation: nil
                )
            }

            // Format results
            var resultText = "Found \(searchResults.count) relevant conversation(s):\n\n"
            for result in searchResults {
                resultText += "**\(result.title)** (\(formatRelativeTime(from: result.timestamp)))\n"
                for snippet in result.snippets {
                    resultText += "> \(snippet)\n"
                }
                resultText += "\n"
            }

            return ToolResult(
                tool: toolId.rawValue,
                success: true,
                result: resultText,
                sources: nil,
                memoryOperation: nil
            )

        case .createMemory:
            // Parse the pipe-separated format: TYPE|CONFIDENCE|TAGS|CONTENT
            let parts = query.components(separatedBy: "|")
            guard parts.count >= 4 else {
                // Generate a corrective example based on their content
                let truncatedContent = query.count > 100 ? String(query.prefix(100)) + "..." : query
                let suggestedTags = generateSuggestedTags(from: query)

                let correctiveExample = """
                    😬 **WHOOPS FORMAT ERROR**: What is this? Freestyle? In your dreams. The create_memory tool requires a pipe-delimited string.

                    **Your input:** `\(truncatedContent)`

                    **Required format:** `TYPE|CONFIDENCE|TAGS|CONTENT`

                    **To save this memory, retry with something like:**
                    ```tool_request
                    {"tool": "create_memory", "query": "allocentric|0.8|\(suggestedTags)|\(query.replacingOccurrences(of: "|", with: "-"))"}
                    ```

                    **Format breakdown:**
                    - TYPE: `allocentric` (facts about user) or `egoic` (what works for user)
                    - CONFIDENCE: `0.0` to `1.0` (e.g., `0.8` for 80% certain)
                    - TAGS: comma-separated keywords (e.g., `preferences,workflow`)
                    - CONTENT: the memory text (your original input)

                    Please retry using the exact format above.
                    """

                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: correctiveExample,
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: "unknown",
                        content: query,
                        errorMessage: "Invalid format - missing pipe delimiters"
                    )
                )
            }

            let typeStr = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let confidenceStr = parts[1].trimmingCharacters(in: .whitespaces)
            let tagsStr = parts[2].trimmingCharacters(in: .whitespaces)
            let content = parts[3...].joined(separator: "|").trimmingCharacters(in: .whitespaces)

            // Parse memory type
            guard let memoryType = MemoryType(rawValue: typeStr) else {
                // Suggest which type based on content
                let suggestedType = content.lowercased().contains("prefer") ||
                                   content.lowercased().contains("like") ||
                                   content.lowercased().contains("background") ? "allocentric" : "egoic"

                let typeError = """
                    🤨 **HMMM... INVALID MEMORY TYPE**: '\(typeStr)' is not recognized.

                    **Valid types:**
                    - `allocentric`: Facts ABOUT the user (preferences, background, relationships)
                    - `egoic`: What WORKS for you in this particular agentic context (approaches, techniques, learnings)

                    **To fix, retry with:**
                    ```tool_request
                    {"tool": "create_memory", "query": "\(suggestedType)|\(confidenceStr)|\(tagsStr)|\(content)"}
                    ```
                    """

                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: typeError,
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: typeStr,
                        content: content,
                        errorMessage: "Invalid memory type '\(typeStr)'"
                    )
                )
            }

            // Parse confidence
            guard let confidence = Double(confidenceStr), confidence >= 0.0, confidence <= 1.0 else {
                let confidenceError = """
                    🥸 **LOL INVALID CONFIDENCE**: '\(confidenceStr)' is not a valid confidence value, nerd (jk, we're friends here).

                    **Required:** A decimal number between 0.0 and 1.0
                    - `0.9` = 90% certain (high confidence)
                    - `0.7` = 70% certain (moderate confidence)
                    - `0.5` = 50% certain (uncertain)

                    **To fix, retry with:**
                    ```tool_request
                    {"tool": "create_memory", "query": "\(typeStr)|0.8|\(tagsStr)|\(content)"}
                    ```
                    """

                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: confidenceError,
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: typeStr,
                        content: content,
                        errorMessage: "Invalid confidence '\(confidenceStr)'"
                    )
                )
            }

            // Parse tags
            let tags = tagsStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Validate content
            guard !content.isEmpty else {
                let contentError = """
                    😂 **HEY EMPTY CONTENT**: Memory content can't be empty, silly goose.

                    **Format reminder:** `TYPE|CONFIDENCE|TAGS|CONTENT`

                    The CONTENT field (4th segment after the third `|`) must contain the memory text.

                    **Example:**
                    ```tool_request
                    {"tool": "create_memory", "query": "allocentric|0.8|preferences|User prefers dark mode"}
                    ```
                    """

                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: contentError,
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: typeStr,
                        content: "",
                        errorMessage: "Memory content cannot be empty"
                    )
                )
            }

            // Create the memory via MemoryService
            do {
                print("[ToolProxy] Creating memory: type=\(memoryType.rawValue), confidence=\(confidence), tags=\(tags)")
                let memory = try await MemoryService.shared.createMemory(
                    content: content,
                    type: memoryType,
                    confidence: confidence,
                    tags: tags,
                    context: nil
                )
                print("[ToolProxy] ✅ Memory created successfully: \(memory.id)")

                return ToolResult(
                    tool: toolId.rawValue,
                    success: true,
                    result: "✓ Memory saved successfully.\n\n**Type:** \(memoryType.displayName)\n**Confidence:** \(Int(confidence * 100))%\n**Tags:** \(tags.joined(separator: ", "))\n**Content:** \(content)",
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        id: memory.id,
                        success: true,
                        memoryType: memoryType.rawValue,
                        content: content,
                        tags: tags,
                        confidence: confidence
                    )
                )
            } catch {
                print("[ToolProxy] ❌ Failed to create memory: \(error.localizedDescription)")
                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: "Failed to save memory: \(error.localizedDescription)",
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: memoryType.rawValue,
                        content: content,
                        tags: tags,
                        confidence: confidence,
                        errorMessage: error.localizedDescription
                    )
                )
            }

        default:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "Unknown internal tool: \(toolId.rawValue)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Internal Tool Approval

    /// Execute an internal tool that requires biometric approval
    private func executeInternalToolWithApproval(
        toolId: ToolId,
        query: String,
        context: ToolConversationContext?
    ) async -> ToolResult {
        print("[ToolProxy] Internal tool '\(toolId.rawValue)' requires biometric approval")

        // Create a DynamicToolConfig facade for the approval service
        let toolConfig = DynamicToolConfig(
            id: toolId.rawValue,
            name: toolId.displayName,
            description: toolId.description,
            category: .utility,
            enabled: true,
            icon: toolId.icon,
            requiredSecrets: [],
            pipeline: [],
            parameters: [:],
            requiresApproval: true,
            approvalScopes: toolId.approvalScopes
        )

        let inputs: [String: Any] = ["query": query]
        let approvalResult = await toolApprovalService.requestApproval(tool: toolConfig, inputs: inputs)

        switch approvalResult {
        case .approved(let record), .approvedForSession(let record):
            let isSession = if case .approvedForSession = approvalResult { true } else { false }
            let approvalNote = isSession
                ? "✅ *Session-approved by \(formatBiometricType(record.biometricType))*"
                : "✅ *Approved by \(formatBiometricType(record.biometricType)) at \(record.formattedTime)*"
            print("[ToolProxy] Internal tool '\(toolId.rawValue)' \(isSession ? "session-" : "")approved")

            // Execute the internal tool now that we have approval
            var result = await executeInternalTool(toolId: toolId, query: query, context: context)

            // Append approval note to result
            return ToolResult(
                tool: result.tool,
                success: result.success,
                result: result.result + "\n\n\(approvalNote)",
                sources: result.sources,
                memoryOperation: result.memoryOperation,
                approvalRecord: record
            )

        case .denied:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "⛔ Tool execution was not authorized by the user.",
                sources: nil,
                memoryOperation: nil
            )

        case .cancelled:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "Tool execution was cancelled.",
                sources: nil,
                memoryOperation: nil
            )

        case .timeout:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "⏱️ Tool approval request timed out. Please try again.",
                sources: nil,
                memoryOperation: nil
            )

        case .stop:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "🛑 Tool execution was stopped by the user.",
                sources: nil,
                memoryOperation: nil
            )

        case .error(let message):
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "Approval error: \(message)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Dynamic Tool Execution

    private let toolApprovalService = ToolApprovalService.shared

    /// Execute a dynamic tool pipeline
    private func executeDynamicTool(
        request: ToolRequest,
        tool: DynamicToolConfig
    ) async throws -> ToolResult {
        print("[ToolProxy] Executing dynamic tool: \(tool.id)")

        // Parse inputs from the query
        // The query can be JSON for complex inputs or a simple string for single-param tools
        var inputs: [String: Any] = [:]

        // Try to parse as JSON first
        if let data = request.query.data(using: .utf8),
           let jsonInputs = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            inputs = jsonInputs
        } else {
            // For simple queries, try to map to the first required parameter
            if let firstRequiredParam = tool.parameters.first(where: { $0.value.required }) {
                inputs[firstRequiredParam.key] = request.query
            } else if let firstParam = tool.parameters.first {
                inputs[firstParam.key] = request.query
            } else {
                // No parameters defined, pass query as generic input
                inputs["query"] = request.query
            }
        }

        // Check if this tool requires biometric approval
        if tool.requiresApproval {
            print("[ToolProxy] Tool '\(tool.id)' requires biometric approval")

            let approvalResult = await toolApprovalService.requestApproval(tool: tool, inputs: inputs)

            switch approvalResult {
            case .approved(let record), .approvedForSession(let record):
                let isSession = if case .approvedForSession = approvalResult { true } else { false }
                let approvalNote = isSession
                    ? "✅ *Session-approved by \(formatBiometricType(record.biometricType))*"
                    : "✅ *Approved by \(formatBiometricType(record.biometricType)) at \(record.formattedTime)*"
                print("[ToolProxy] Tool '\(tool.id)' \(isSession ? "session-" : "")approved with signature: \(record.shortSignature)")

                do {
                    let result = try await dynamicToolEngine.execute(toolId: tool.id, inputs: inputs)
                    // Return result with approval info
                    return ToolResult(
                        tool: tool.id,
                        success: result.success,
                        result: result.output + "\n\n\(approvalNote)",
                        sources: nil,
                        memoryOperation: nil,
                        approvalRecord: record
                    )
                } catch let error as DynamicToolError {
                    return ToolResult(
                        tool: tool.id,
                        success: false,
                        result: "Dynamic tool error: \(error.localizedDescription)",
                        sources: nil,
                        memoryOperation: nil,
                        approvalRecord: record
                    )
                } catch {
                    return ToolResult(
                        tool: tool.id,
                        success: false,
                        result: "Dynamic tool failed: \(error.localizedDescription)",
                        sources: nil,
                        memoryOperation: nil,
                        approvalRecord: record
                    )
                }

            case .denied:
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "⛔ Tool execution was not authorized by the user.",
                    sources: nil,
                    memoryOperation: nil
                )

            case .cancelled:
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "Tool execution was cancelled.",
                    sources: nil,
                    memoryOperation: nil
                )

            case .timeout:
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "⏱️ Tool approval request timed out. Please try again.",
                    sources: nil,
                    memoryOperation: nil
                )

            case .stop:
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "🛑 Tool execution was stopped by the user.",
                    sources: nil,
                    memoryOperation: nil
                )

            case .error(let message):
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "Approval error: \(message)",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        // No approval required - execute directly
        do {
            let result = try await dynamicToolEngine.execute(toolId: tool.id, inputs: inputs)
            return result.toToolResult()
        } catch let error as DynamicToolError {
            return ToolResult(
                tool: tool.id,
                success: false,
                result: "Dynamic tool error: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        } catch {
            return ToolResult(
                tool: tool.id,
                success: false,
                result: "Dynamic tool failed: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Reflect on Conversation Tool

    /// Execute the reflect_on_conversation tool
    private func executeReflectOnConversation(query: String, context: ToolConversationContext?) async -> ToolResult {
        guard let context = context else {
            return ToolResult(
                tool: ToolId.reflectOnConversation.rawValue,
                success: false,
                result: "Cannot reflect on conversation: no conversation context available.",
                sources: nil,
                memoryOperation: nil
            )
        }

        // Parse options from query (JSON format)
        var options = ReflectionOptions()

        if !query.isEmpty && query != "{}" {
            if let data = query.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let showTimeline = json["show_model_timeline"] as? Bool {
                    options.showModelTimeline = showTimeline
                }
                if let showTasks = json["show_task_distribution"] as? Bool {
                    options.showTaskDistribution = showTasks
                }
                if let showMemory = json["show_memory_usage"] as? Bool {
                    options.showMemoryUsage = showMemory
                }
            }
        }

        // Generate reflection
        let reflection = ConversationReflectionService.shared.reflect(
            on: context.messages,
            conversationId: context.conversationId,
            options: options
        )

        // Format the reflection as text
        let formattedResult = ConversationReflectionService.shared.formatReflection(reflection, options: options)

        return ToolResult(
            tool: ToolId.reflectOnConversation.rawValue,
            success: true,
            result: formattedResult,
            sources: nil,
            memoryOperation: nil
        )
    }

    private func formatBiometricType(_ type: String) -> String {
        switch type {
        case "faceID": return "Face ID"
        case "touchID": return "Touch ID"
        case "opticID": return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Format timestamp as relative time
    private func formatRelativeTime(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return minutes <= 1 ? "just now" : "\(minutes) minutes ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else {
            let days = Int(seconds / 86400)
            return days == 1 ? "yesterday" : "\(days) days ago"
        }
    }

    /// Generate suggested tags from content using keyword extraction
    private func generateSuggestedTags(from content: String) -> String {
        let lowercased = content.lowercased()

        // Common topic keywords to detect
        let topicKeywords: [(keywords: [String], tag: String)] = [
            (["code", "coding", "programming", "developer", "software", "swift", "python", "javascript"], "coding"),
            (["prefer", "like", "want", "favorite", "love"], "preferences"),
            (["work", "job", "career", "project", "task"], "work"),
            (["mac", "iphone", "ipad", "apple", "ios", "macos", "xcode"], "apple"),
            (["learn", "study", "course", "tutorial"], "learning"),
            (["ui", "ux", "design", "interface", "visual"], "design"),
            (["test", "testing", "debug", "debugging"], "testing"),
            (["tool", "tools", "workflow", "process"], "workflow"),
            (["feature", "features", "functionality"], "features"),
            (["communication", "talk", "explain", "discuss"], "communication"),
        ]

        var detectedTags: [String] = []

        for (keywords, tag) in topicKeywords {
            if keywords.contains(where: { lowercased.contains($0) }) {
                detectedTags.append(tag)
            }
            if detectedTags.count >= 3 { break }
        }

        // Fallback if no tags detected
        if detectedTags.isEmpty {
            detectedTags = ["general", "context"]
        }

        return detectedTags.joined(separator: ",")
    }

    // MARK: - Format Tool Results

    /// Format tool results for injection into conversation
    func formatToolResult(_ result: ToolResult) -> String {
        var formatted = """

        ---
        **Tool Result** (\(result.tool)):

        \(result.result)
        """

        if let sources = result.sources, !sources.isEmpty {
            formatted += "\n\n**Sources:**\n"
            for source in sources {
                formatted += "- [\(source.title)](\(source.url))\n"
            }
        }

        formatted += "\n---\n"

        return formatted
    }

    // MARK: - Location Services

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        let status = locationManager.authorizationStatus

        #if os(macOS)
        // CoreLocation authorization statuses differ on macOS.
        // There is no `.authorizedWhenInUse` (it’s iOS-only). Treat `.authorized` as success.
        guard status == .authorized || status == .authorizedAlways else {
            print("[ToolProxy] Location not authorized: \(status.rawValue)")
            return nil
        }
        #else
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            print("[ToolProxy] Location not authorized: \(status.rawValue)")
            return nil
        }
        #endif

        if let location = locationManager.location,
           Date().timeIntervalSince(location.timestamp) < 300 {
            return location.coordinate
        }

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()

            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if self.locationContinuation != nil {
                    self.locationContinuation?.resume(returning: self.locationManager.location?.coordinate)
                    self.locationContinuation = nil
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.locationContinuation?.resume(returning: location.coordinate)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[ToolProxy] Location error: \(error.localizedDescription)")
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("[ToolProxy] Location authorization changed: \(manager.authorizationStatus.rawValue)")
    }
}

// MARK: - Models

struct ToolRequest: Decodable {
    let tool: String
    let query: String
    /// Optional separate content field (for write_file when AI sends path and content separately)
    let separateContent: String?

    /// Custom decoder to accept multiple key names for the query field
    /// LLMs sometimes use "memory", "content", "input", etc. instead of "query"
    /// Also handles nested "parameters" object format: {"tool": "...", "parameters": {"query": "...", "content": "..."}}
    /// Also handles tools like reflect_on_conversation where options are sent as top-level fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(String.self, forKey: .tool)

        // Check if AI sent nested parameters object (common format)
        // e.g., {"tool": "vscode_write_file", "parameters": {"query": "path", "content": "data"}}
        if container.contains(.parameters) {
            let paramsContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .parameters)

            // Extract query from parameters
            if let q = try? paramsContainer.decode(String.self, forKey: .query) {
                query = q
            } else if let q = try? paramsContainer.decode(String.self, forKey: .path) {
                query = q
            } else if let q = try? paramsContainer.decode(String.self, forKey: .input) {
                query = q
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.query,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No query/path found in parameters object")
                )
            }

            // Extract content from parameters if present
            separateContent = try? paramsContainer.decode(String.self, forKey: .content)
            return
        }

        // Flat format: check if we have both query and content (common for write_file)
        let hasQuery = container.contains(.query)
        let hasContent = container.contains(.content)

        if hasQuery && hasContent {
            // AI sent query (path) and content separately - capture both
            query = try container.decode(String.self, forKey: .query)
            separateContent = try container.decodeIfPresent(String.self, forKey: .content)
        } else {
            // Try multiple possible key names for the query value
            if let q = try? container.decode(String.self, forKey: .query) {
                query = q
            } else if let q = try? container.decode(String.self, forKey: .memory) {
                query = q
            } else if let q = try? container.decode(String.self, forKey: .content) {
                query = q
            } else if let q = try? container.decode(String.self, forKey: .input) {
                query = q
            } else if let q = try? container.decode(String.self, forKey: .data) {
                query = q
            } else {
                // Special case: reflect_on_conversation and similar tools may send options as top-level fields
                // e.g., {"tool":"reflect_on_conversation","show_model_timeline":true,"show_task_distribution":true}
                // In this case, reconstruct the query as JSON from all non-tool fields
                if tool == "reflect_on_conversation" {
                    // Decode all fields as a dictionary and re-serialize without "tool"
                    let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
                    var optionsDict: [String: Any] = [:]

                    for key in dynamicContainer.allKeys where key.stringValue != "tool" {
                        if let boolValue = try? dynamicContainer.decode(Bool.self, forKey: key) {
                            optionsDict[key.stringValue] = boolValue
                        } else if let stringValue = try? dynamicContainer.decode(String.self, forKey: key) {
                            optionsDict[key.stringValue] = stringValue
                        } else if let intValue = try? dynamicContainer.decode(Int.self, forKey: key) {
                            optionsDict[key.stringValue] = intValue
                        }
                    }

                    // Convert back to JSON string for the query
                    if let jsonData = try? JSONSerialization.data(withJSONObject: optionsDict, options: []),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        query = jsonString
                    } else {
                        query = "{}"  // Empty options
                    }
                    separateContent = nil
                    return
                }

                throw DecodingError.keyNotFound(
                    CodingKeys.query,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No valid query key found (tried: query, memory, content, input, data)")
                )
            }
            separateContent = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tool
        case query
        case memory
        case content
        case input
        case data
        case parameters
        case path
    }

    /// Dynamic coding keys for parsing arbitrary fields
    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

struct ToolResult {
    let tool: String
    let success: Bool
    let result: String
    let sources: [ToolResultSource]?
    let memoryOperation: MessageMemoryOperation?  // For create_memory tool results
    let approvalRecord: ToolApprovalRecord?  // For tools requiring biometric approval

    init(
        tool: String,
        success: Bool,
        result: String,
        sources: [ToolResultSource]?,
        memoryOperation: MessageMemoryOperation?,
        approvalRecord: ToolApprovalRecord? = nil
    ) {
        self.tool = tool
        self.success = success
        self.result = result
        self.sources = sources
        self.memoryOperation = memoryOperation
        self.approvalRecord = approvalRecord
    }
}

struct ToolResultSource {
    let title: String
    let url: String
}

/// Context passed to tools that need access to conversation data
struct ToolConversationContext {
    let conversationId: String
    let messages: [Message]
}
