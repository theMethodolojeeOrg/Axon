//
//  OnDeviceConversationOrchestrator.swift
//  Axon
//
//  Implementation of ConversationOrchestrator that calls AI providers directly from the device.
//  Integrates with the Epistemic Engine for grounded, conscious responses.
//  Supports native Gemini tool execution (Google Search, Code Execution, URL Context, Maps).
//

import Foundation
import CoreLocation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Result from provider API calls including content and optional reasoning
struct ProviderResponse {
    let content: String
    let reasoning: String?

    init(content: String, reasoning: String? = nil) {
        self.content = content
        self.reasoning = reasoning
    }
}

/// Token estimation for context debugging
/// Uses ~4 characters per token as a rough estimate (reasonable for English text)
struct TokenEstimator {
    static let charsPerToken: Double = 4.0

    static func estimate(_ text: String) -> Int {
        max(1, Int(Double(text.count) / charsPerToken))
    }

    static func estimate(_ texts: [String]) -> Int {
        texts.reduce(0) { $0 + estimate($1) }
    }
}

/// Result from building epistemic system prompt, including debug info
struct EpistemicPromptResult {
    let systemPrompt: String?
    let usedMemories: [Memory]

    // Debug info components (only populated when debug enabled)
    let basePromptTokens: Int
    let memoriesCount: Int
    let memoriesTokens: Int
    let factsCount: Int
    let factsTokens: Int
    let summaryTokens: Int
}

class OnDeviceConversationOrchestrator: ConversationOrchestrator {

    // MARK: - Services

    private let predicateLogger = PredicateLogger.shared
    private let salienceService = SalienceService.shared
    private let learningLoopService = LearningLoopService.shared
    private let agentStateService = AgentStateService.shared
    // Lazy to avoid circular dependency: HeartbeatService creates OnDeviceConversationOrchestrator
    private lazy var heartbeatService = HeartbeatService.shared

    // MARK: - State for Learning Loop

    private var lastResponse: String?
    private var lastUsedMemories: [Memory] = []
    private var lastCorrelationId: String?

    // MARK: - Last Tool Response (for grounding metadata)

    private(set) var lastToolResponse: GeminiToolResponse?

    // MARK: - Tool-Capable Gemini Models

    /// Prefixes of Gemini models that support native tool execution
    /// All major Gemini series (1.5, 2.0, 2.5, 3.0) support tools
    private static let toolCapablePrefixes = [
        // Gemini 3 series - supports: google_search, file_search, code_execution, url_context
        // NOTE: Does NOT support google_maps or computer_use
        "gemini-3",
        // Gemini 2.5 series - full tool support
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        // Gemini 2.0 series
        "gemini-2.0-flash",
        // Gemini 1.5 series
        "gemini-1.5-pro",
        "gemini-1.5-flash",
    ]

    /// Tools NOT supported by Gemini 3 (must be filtered out)
    private static let gemini3UnsupportedTools: Set<String> = [
        ToolId.googleMaps.rawValue,  // Google Maps not supported in Gemini 3
    ]

    /// Check if a Gemini model supports native tools
    private func isToolCapableGeminiModel(_ model: String) -> Bool {
        return Self.toolCapablePrefixes.contains { model.hasPrefix($0) }
    }

    /// Check if a model is Gemini 3 series (has different tool support)
    private func isGemini3Model(_ model: String) -> Bool {
        return model.hasPrefix("gemini-3")
    }

    /// Filter tools to only those supported by the specific Gemini model
    private func filterToolsForModel(_ tools: Set<String>, model: String) -> Set<String> {
        if isGemini3Model(model) {
            // Gemini 3 doesn't support Google Maps
            return tools.subtracting(Self.gemini3UnsupportedTools)
        }
        return tools
    }

    func sendMessage(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment],
        enabledTools: [String],
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> (assistantMessage: Message, memories: [Memory]?) {
        // Check if we have Gemini tools enabled
        let geminiToolIds: Set<String> = [
            ToolId.googleSearch.rawValue,
            ToolId.codeExecution.rawValue,
            ToolId.urlContext.rawValue,
            ToolId.googleMaps.rawValue,
            ToolId.fileSearch.rawValue,
        ]
        let requestedGeminiTools = Set(enabledTools).intersection(geminiToolIds)
        let hasGeminiTools = !requestedGeminiTools.isEmpty && config.geminiKey != nil
        let isGeminiProvider = config.provider == "gemini"

        // Check if the selected Gemini model supports native tools
        // Models like gemini-3-pro don't support tools, so they need tool proxy
        let geminiModelSupportsTools = isGeminiProvider && isToolCapableGeminiModel(config.model)

        if hasGeminiTools {
            print("[OnDeviceOrchestrator] Gemini tools enabled: \(requestedGeminiTools), provider: \(config.provider), model: \(config.model), native support: \(geminiModelSupportsTools)")
        }

        // Start a correlation context for this request
        let correlationId = predicateLogger.startCorrelation()
        defer { predicateLogger.endCorrelation() }

        // Process learning from previous interaction (if any)
        if let prevResponse = lastResponse, let prevCorrelation = lastCorrelationId {
            await processLearningFromPreviousInteraction(
                currentUserMessage: content,
                previousResponse: prevResponse,
                previousCorrelationId: prevCorrelation
            )
        }

        // Combine default system prompt with any system-role messages in history
        let mergedMessages = mergeLatestUserMessage(
            messages,
            conversationId: conversationId,
            content: content,
            attachments: attachments
        )

        // Build epistemic-grounded system prompt
        // Get user's display name for personalization
        let userName = await getUserDisplayName()
        let basePrompt = buildAgentBasePrompt(
            hasMemoryTool: enabledTools.contains(ToolId.createMemory.rawValue),
            userName: userName
        )
        let epistemicResult = await buildEpistemicSystemPrompt(
            base: basePrompt,
            messages: mergedMessages,
            userQuery: content,
            correlationId: correlationId,
            userName: userName
        )
        var systemPrompt = epistemicResult.systemPrompt
        let usedMemories = epistemicResult.usedMemories

        // Filter tools based on model capabilities
        // Gemini 3 supports most tools but NOT google_maps
        let filteredGeminiTools = filterToolsForModel(requestedGeminiTools, model: config.model)
        let hasFilteredTools = !filteredGeminiTools.isEmpty

        // Use tool proxy for non-Gemini providers (Claude, GPT, Grok) with tools enabled
        // Uses minimal discovery-based prompt to reduce context bloat - AI discovers tools via list_tools/get_tool_details
        let useToolProxy = hasGeminiTools && !isGeminiProvider
        if useToolProxy {
            let enabledToolIds = Set(requestedGeminiTools.compactMap { ToolId(rawValue: $0) })
            let maxToolCalls = await MainActor.run {
                SettingsViewModel.shared.settings.toolSettings.maxToolCallsPerTurn
            }
            let toolPrompt = await ToolProxyService.shared.generateMinimalToolSystemPrompt(
                enabledTools: enabledToolIds,
                maxToolCalls: maxToolCalls
            )
            systemPrompt = (systemPrompt ?? "") + toolPrompt
            print("[OnDeviceOrchestrator] Tool proxy mode (discovery-based): injected minimal tool prompt for \(enabledToolIds.count) tools (max \(maxToolCalls) calls)")
        }

        // Log if any tools were filtered out for Gemini 3
        if isGemini3Model(config.model) && filteredGeminiTools.count < requestedGeminiTools.count {
            let removed = requestedGeminiTools.subtracting(filteredGeminiTools)
            print("[OnDeviceOrchestrator] Gemini 3 model: filtered out unsupported tools: \(removed)")
        }

        // MARK: - Media Proxy for Video/Audio Understanding
        // When non-Gemini providers receive video/audio attachments, proxy through Gemini first
        var processedAttachments = attachments
        var mediaProxyContext: String? = nil
        var usedMediaProxy = false

        // Check if media proxy is enabled in settings (requires experimental features)
        let (experimentalEnabled, mediaProxyEnabled) = await MainActor.run {
            let settings = SettingsViewModel.shared.settings.toolSettings
            return (settings.experimentalFeaturesEnabled, settings.mediaProxyEnabled)
        }

        if experimentalEnabled && mediaProxyEnabled && !isGeminiProvider && !attachments.isEmpty, let geminiKey = config.geminiKey {
            do {
                let proxyResult = try await GeminiMediaProxyService.shared.processUnsupportedMedia(
                    attachments: attachments,
                    targetProvider: config.provider,
                    geminiApiKey: geminiKey,
                    userPrompt: content
                )

                if proxyResult.hadProxiedMedia {
                    processedAttachments = proxyResult.processedAttachments
                    mediaProxyContext = proxyResult.additionalContext
                    usedMediaProxy = true
                    print("[OnDeviceOrchestrator] Media proxy: processed \(proxyResult.proxiedCount) attachments through Gemini")
                }
            } catch {
                print("[OnDeviceOrchestrator] Media proxy failed: \(error.localizedDescription)")
                // Continue without proxy - attachment will be dropped if unsupported
            }
        }

        // If media was proxied, inject the context into the system prompt
        if let mediaContext = mediaProxyContext {
            systemPrompt = (systemPrompt ?? "") + "\n\n" + mediaContext
        }

        // Update merged messages with processed attachments
        var finalMessages = mergedMessages
        if usedMediaProxy, let lastIndex = finalMessages.lastIndex(where: { $0.role == .user }) {
            let lastUserMsg = finalMessages[lastIndex]
            finalMessages[lastIndex] = Message(
                id: lastUserMsg.id,
                conversationId: lastUserMsg.conversationId,
                role: lastUserMsg.role,
                content: lastUserMsg.content,
                timestamp: lastUserMsg.timestamp,
                tokens: lastUserMsg.tokens,
                artifacts: lastUserMsg.artifacts,
                toolCalls: lastUserMsg.toolCalls,
                isStreaming: lastUserMsg.isStreaming,
                modelName: lastUserMsg.modelName,
                providerName: lastUserMsg.providerName,
                attachments: processedAttachments.isEmpty ? nil : processedAttachments
            )
        }

        // Log LLM request predicate
        predicateLogger.logLLMRequest(
            provider: config.provider,
            model: config.model,
            correlationId: correlationId
        )

        var responseContent: String = ""
        var responseReasoning: String? = nil
        var usedToolProxy = false
        var groundingSources: [MessageGroundingSource] = []
        var memoryOperations: [MessageMemoryOperation] = []
        lastToolResponse = nil

        // Route based on provider and tool configuration
        // Use native Gemini tools if: Gemini provider + has filtered tools + model supports native tools
        if hasFilteredTools && geminiModelSupportsTools, let geminiKey = config.geminiKey {
            // Gemini provider with tool-capable model: use native Gemini tools
            let toolResponse = try await callGeminiWithTools(
                apiKey: geminiKey,
                model: config.model,
                system: systemPrompt,
                messages: finalMessages,
                enabledTools: filteredGeminiTools
            )
            responseContent = toolResponse.fullResponse
            lastToolResponse = toolResponse

            // Collect grounding sources from native Gemini tools
            if toolResponse.hasGroundingSources {
                groundingSources = toolResponse.webSources.map { MessageGroundingSource(from: $0) }
                print("[OnDeviceOrchestrator] Response includes \(groundingSources.count) grounding sources")
            }
        } else {
            // Non-Gemini provider (or Gemini without tools): standard routing
            let providerResult = try await callProvider(
                provider: config.provider,
                config: config,
                system: systemPrompt,
                messages: finalMessages
            )
            responseContent = providerResult.content
            responseReasoning = providerResult.reasoning

            // If tool proxy mode, check for tool requests and execute them
            if useToolProxy, let geminiKey = config.geminiKey {
                // Get max tool calls from settings
                let maxToolCalls = await MainActor.run {
                    SettingsViewModel.shared.settings.toolSettings.maxToolCallsPerTurn
                }

                let (finalResponse, toolUsed, sources, memOps) = try await handleToolProxyLoop(
                    initialResponse: responseContent,
                    conversationId: conversationId,
                    config: config,
                    systemPrompt: systemPrompt,
                    messages: finalMessages,
                    geminiKey: geminiKey,
                    maxIterations: maxToolCalls
                )
                responseContent = finalResponse
                usedToolProxy = toolUsed
                groundingSources = sources
                memoryOperations = memOps
            }
        }

        // Log successful LLM response
        predicateLogger.logLLMResponse(
            success: true,
            tokenCount: nil,
            correlationId: correlationId
        )

        // Create Assistant Message with appropriate model name suffix
        var modelName = config.model
        var suffixes: [String] = []

        if usedMediaProxy {
            suffixes.append("media")
        }
        if usedToolProxy {
            suffixes.append("tools")
        } else if hasFilteredTools && geminiModelSupportsTools {
            suffixes.append("tools")
        }

        if !suffixes.isEmpty {
            modelName = "\(config.model) + \(suffixes.joined(separator: ", "))"
        }

        let assistantMessage = Message(
            conversationId: conversationId,
            role: .assistant,
            content: responseContent,
            modelName: modelName,
            providerName: config.providerName,
            groundingSources: groundingSources.isEmpty ? nil : groundingSources,
            memoryOperations: memoryOperations.isEmpty ? nil : memoryOperations,
            reasoning: responseReasoning
        )

        // Record prediction for learning loop
        if !usedMemories.isEmpty {
            learningLoopService.recordPrediction(
                content: responseContent,
                confidence: 0.8,
                basedOnMemories: usedMemories,
                correlationId: correlationId
            )
        }

        // Store for next interaction's learning loop
        lastResponse = responseContent
        lastUsedMemories = usedMemories
        lastCorrelationId = correlationId

        return (assistantMessage, nil)
    }

    // MARK: - Streaming Message Send

    /// Send a message with streaming response and real-time tool visibility
    /// Returns an AsyncThrowingStream that emits StreamingEvents
    func sendMessageStreaming(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment],
        enabledTools: [String],
        messages: [Message],
        config: OrchestrationConfig
    ) -> AsyncThrowingStream<StreamingEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.performStreamingSend(
                        conversationId: conversationId,
                        content: content,
                        attachments: attachments,
                        enabledTools: enabledTools,
                        messages: messages,
                        config: config,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.yield(.error(.connectionFailed(error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Internal streaming implementation
    private func performStreamingSend(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment],
        enabledTools: [String],
        messages: [Message],
        config: OrchestrationConfig,
        continuation: AsyncThrowingStream<StreamingEvent, Error>.Continuation
    ) async throws {
        // Check if we have Gemini tools enabled
        let geminiToolIds: Set<String> = [
            ToolId.googleSearch.rawValue,
            ToolId.codeExecution.rawValue,
            ToolId.urlContext.rawValue,
            ToolId.googleMaps.rawValue,
            ToolId.fileSearch.rawValue,
        ]
        let requestedGeminiTools = Set(enabledTools).intersection(geminiToolIds)
        let hasGeminiTools = !requestedGeminiTools.isEmpty && config.geminiKey != nil
        let isGeminiProvider = config.provider == "gemini"
        let geminiModelSupportsTools = isGeminiProvider && isToolCapableGeminiModel(config.model)

        // Start correlation
        let correlationId = predicateLogger.startCorrelation()
        defer { predicateLogger.endCorrelation() }

        // Merge messages
        let mergedMessages = mergeLatestUserMessage(
            messages,
            conversationId: conversationId,
            content: content,
            attachments: attachments
        )

        // Build epistemic system prompt
        let userName = await getUserDisplayName()
        let basePrompt = buildAgentBasePrompt(
            hasMemoryTool: enabledTools.contains(ToolId.createMemory.rawValue),
            userName: userName
        )
        let epistemicResult = await buildEpistemicSystemPrompt(
            base: basePrompt,
            messages: mergedMessages,
            userQuery: content,
            correlationId: correlationId,
            userName: userName
        )
        var systemPrompt = epistemicResult.systemPrompt
        let usedMemories = epistemicResult.usedMemories

        // Filter tools for model
        let filteredGeminiTools = filterToolsForModel(requestedGeminiTools, model: config.model)

        // Track tool prompt tokens for debug
        var toolPromptTokens = 0

        // Use tool proxy for non-Gemini providers
        // Uses minimal discovery-based prompt to reduce context bloat
        let useToolProxy = hasGeminiTools && !isGeminiProvider
        if useToolProxy {
            let enabledToolIds = Set(requestedGeminiTools.compactMap { ToolId(rawValue: $0) })
            let maxToolCalls = await MainActor.run {
                SettingsViewModel.shared.settings.toolSettings.maxToolCallsPerTurn
            }
            let toolPrompt = await ToolProxyService.shared.generateMinimalToolSystemPrompt(
                enabledTools: enabledToolIds,
                maxToolCalls: maxToolCalls
            )
            systemPrompt = (systemPrompt ?? "") + toolPrompt
            toolPromptTokens = TokenEstimator.estimate(toolPrompt)
        }

        // Check if chat debug is enabled
        let chatDebugEnabled = await MainActor.run {
            SettingsViewModel.shared.settings.toolSettings.chatDebugEnabled
        }

        // Build context debug info if enabled
        var contextDebugInfo: ContextDebugInfo? = nil
        if chatDebugEnabled {
            let messagesTokens = mergedMessages
                .filter { $0.role != .system }
                .reduce(0) { $0 + TokenEstimator.estimate($1.content) }

            contextDebugInfo = ContextDebugInfo(
                systemPromptTokens: epistemicResult.basePromptTokens,
                memoriesCount: epistemicResult.memoriesCount,
                memoriesTokens: epistemicResult.memoriesTokens,
                factsCount: epistemicResult.factsCount,
                factsTokens: epistemicResult.factsTokens,
                summaryTokens: epistemicResult.summaryTokens,
                toolPromptTokens: toolPromptTokens,
                messagesTokens: messagesTokens,
                contextWindowLimit: config.contextWindowLimit,
                modelName: config.model
            )

            // Log debug info
            print("[ContextDebug] Total: \(contextDebugInfo!.totalTokens) / \(config.contextWindowLimit) (\(Int(contextDebugInfo!.usagePercentage * 100))%)")
            print("[ContextDebug] Breakdown - System: \(epistemicResult.basePromptTokens), Memories: \(epistemicResult.memoriesTokens) (\(epistemicResult.memoriesCount)), Facts: \(epistemicResult.factsTokens) (\(epistemicResult.factsCount)), Summary: \(epistemicResult.summaryTokens), Tools: \(toolPromptTokens), Messages: \(messagesTokens)")
        }

        // Check if provider supports streaming
        let supportsStreaming = StreamingResponseHandler.supportsStreaming(provider: config.provider)

        var accumulatedContent = ""
        var accumulatedReasoning = ""
        var collectedToolCalls: [LiveToolCall] = []
        var collectedSources: [MessageGroundingSource] = []
        var collectedMemoryOperations: [MessageMemoryOperation] = []

        if supportsStreaming && !hasGeminiTools {
            // Pure streaming without tool proxy - stream directly
            let streamConfig = StreamingResponseHandler.StreamingConfig(
                provider: config.provider,
                apiKey: getApiKey(for: config) ?? "",
                model: config.model,
                baseUrl: config.customBaseUrl,
                system: systemPrompt,
                maxTokens: 4096
            )

            let handler = StreamingResponseHandler()
            for try await event in handler.stream(config: streamConfig, messages: mergedMessages) {
                switch event {
                case .textDelta(let text):
                    accumulatedContent += text
                    continuation.yield(.textDelta(text))

                case .reasoningDelta(let text):
                    accumulatedReasoning += text
                    continuation.yield(.reasoningDelta(text))

                case .completion(let completion):
                    // Final completion will be built at the end
                    break

                case .error(let error):
                    continuation.yield(.error(error))

                default:
                    break
                }
            }
        } else if supportsStreaming && useToolProxy {
            // Streaming with tool proxy - need to handle tool requests in stream
            try await streamWithToolProxy(
                conversationId: conversationId,
                config: config,
                systemPrompt: systemPrompt,
                messages: mergedMessages,
                geminiKey: config.geminiKey!,
                continuation: continuation,
                accumulatedContent: &accumulatedContent,
                accumulatedReasoning: &accumulatedReasoning,
                collectedToolCalls: &collectedToolCalls,
                collectedSources: &collectedSources,
                collectedMemoryOperations: &collectedMemoryOperations
            )
        } else {
            // Fallback to non-streaming with pseudo-stream events
            let providerResult = try await callProvider(
                provider: config.provider,
                config: config,
                system: systemPrompt,
                messages: mergedMessages
            )

            // Emit the content as streaming events (character by character for smooth UI)
            accumulatedContent = providerResult.content
            accumulatedReasoning = providerResult.reasoning ?? ""

            // Emit in chunks for smoother display
            let chunkSize = 10
            let characters = Array(accumulatedContent)
            for i in stride(from: 0, to: characters.count, by: chunkSize) {
                let end = min(i + chunkSize, characters.count)
                let chunk = String(characters[i..<end])
                continuation.yield(.textDelta(chunk))
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms between chunks
            }

            // Handle tool proxy if needed
            if useToolProxy, let geminiKey = config.geminiKey {
                let maxToolCalls = await MainActor.run {
                    SettingsViewModel.shared.settings.toolSettings.maxToolCallsPerTurn
                }
                try await handleStreamingToolProxyLoop(
                    initialResponse: accumulatedContent,
                    conversationId: conversationId,
                    config: config,
                    systemPrompt: systemPrompt,
                    messages: mergedMessages,
                    geminiKey: geminiKey,
                    maxIterations: maxToolCalls,
                    continuation: continuation,
                    accumulatedContent: &accumulatedContent,
                    collectedToolCalls: &collectedToolCalls,
                    collectedSources: &collectedSources,
                    collectedMemoryOperations: &collectedMemoryOperations
                )
            }
        }

        // Emit final completion with debug info
        continuation.yield(.completion(StreamingCompletion(
            fullContent: accumulatedContent,
            reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
            toolCalls: collectedToolCalls,
            groundingSources: collectedSources,
            memoryOperations: collectedMemoryOperations,
            tokens: nil,
            modelName: config.model,
            providerName: config.providerName,
            contextDebugInfo: contextDebugInfo
        )))
    }

    /// Stream with tool proxy - handles tool requests detected in stream
    private func streamWithToolProxy(
        conversationId: String,
        config: OrchestrationConfig,
        systemPrompt: String?,
        messages: [Message],
        geminiKey: String,
        continuation: AsyncThrowingStream<StreamingEvent, Error>.Continuation,
        accumulatedContent: inout String,
        accumulatedReasoning: inout String,
        collectedToolCalls: inout [LiveToolCall],
        collectedSources: inout [MessageGroundingSource],
        collectedMemoryOperations: inout [MessageMemoryOperation]
    ) async throws {
        let maxToolCalls = await MainActor.run {
            SettingsViewModel.shared.settings.toolSettings.maxToolCallsPerTurn
        }

        var currentMessages = messages
        var iteration = 0

        while iteration < maxToolCalls {
            // Stream from provider
            let streamConfig = StreamingResponseHandler.StreamingConfig(
                provider: config.provider,
                apiKey: getApiKey(for: config) ?? "",
                model: config.model,
                baseUrl: config.customBaseUrl,
                system: systemPrompt,
                maxTokens: 4096
            )

            var iterationContent = ""
            let handler = StreamingResponseHandler()

            for try await event in handler.stream(config: streamConfig, messages: currentMessages) {
                switch event {
                case .textDelta(let text):
                    iterationContent += text
                    accumulatedContent += text
                    continuation.yield(.textDelta(text))

                case .reasoningDelta(let text):
                    accumulatedReasoning += text
                    continuation.yield(.reasoningDelta(text))

                default:
                    break
                }
            }

            // Check for ALL tool requests in accumulated content (handles back-to-back tool calls)
            let toolRequests = await ToolProxyService.shared.parseAllToolRequests(from: iterationContent)
            guard !toolRequests.isEmpty else {
                // No tool requests - we're done
                break
            }

            // Collect all tool results to send back together
            var allToolResults: [(request: ToolRequest, result: ToolResult, formattedResult: String)] = []
            var hadFailure = false

            // Process each tool request sequentially
            for toolRequest in toolRequests {
                // Create and emit live tool call
                let liveToolCall = LiveToolCall.create(name: toolRequest.tool, query: toolRequest.query)
                collectedToolCalls.append(liveToolCall)
                continuation.yield(.toolCallStart(liveToolCall))

                // Execute tool
                let startTime = Date()
                let conversationContext = ToolConversationContext(
                    conversationId: conversationId,
                    messages: messages
                )

                do {
                    let toolResult = try await ToolProxyService.shared.executeToolRequest(
                        toolRequest,
                        geminiApiKey: geminiKey,
                        conversationContext: conversationContext
                    )

                    let duration = Date().timeIntervalSince(startTime)

                    // Build result
                    let result = ToolCallResult(
                        success: true,
                        output: toolResult.result,
                        rawJSON: nil,
                        sources: toolResult.sources?.map { StreamingToolSource(title: $0.title, url: $0.url) },
                        memoryOperation: toolResult.memoryOperation,
                        duration: duration
                    )

                    // Update collected data
                    if let index = collectedToolCalls.firstIndex(where: { $0.id == liveToolCall.id }) {
                        collectedToolCalls[index].state = .success
                        collectedToolCalls[index].result = result
                        collectedToolCalls[index].completedAt = Date()
                    }

                    continuation.yield(.toolCallComplete(liveToolCall.id, result))

                    // Mark as executed for deduplication in UI
                    ToolRequestTracker.shared.markExecuted(request: toolRequest, result: toolResult.result)

                    // Collect sources
                    if let sources = toolResult.sources {
                        for source in sources {
                            collectedSources.append(MessageGroundingSource(
                                title: source.title,
                                url: source.url,
                                sourceType: toolRequest.tool == "google_maps" ? .maps : .web
                            ))
                        }
                    }

                    // Collect memory operations
                    if let memOp = toolResult.memoryOperation {
                        collectedMemoryOperations.append(memOp)
                    }

                    // Store for combined response
                    let formattedResult = await ToolProxyService.shared.formatToolResult(toolResult)
                    allToolResults.append((request: toolRequest, result: toolResult, formattedResult: formattedResult))

                } catch {
                    let duration = Date().timeIntervalSince(startTime)
                    let result = ToolCallResult(
                        success: false,
                        output: "",
                        duration: duration,
                        errorMessage: error.localizedDescription
                    )

                    if let index = collectedToolCalls.firstIndex(where: { $0.id == liveToolCall.id }) {
                        collectedToolCalls[index].state = .failure
                        collectedToolCalls[index].result = result
                        collectedToolCalls[index].completedAt = Date()
                    }

                    continuation.yield(.toolCallComplete(liveToolCall.id, result))
                    hadFailure = true
                    break
                }
            }

            if hadFailure {
                break
            }

            // Prepare for next iteration with all results combined
            let cleanedResponse = await ToolProxyService.shared.removeToolRequest(from: iterationContent)
            let combinedResults = allToolResults.map { $0.formattedResult }.joined(separator: "\n\n")

            currentMessages = messages
            if !cleanedResponse.isEmpty {
                currentMessages.append(Message(
                    conversationId: conversationId,
                    role: .assistant,
                    content: cleanedResponse
                ))
            }
            currentMessages.append(Message(
                conversationId: conversationId,
                role: .user,
                content: combinedResults
            ))

            iteration += 1
        }
    }

    /// Handle tool proxy loop for non-streaming providers with streaming events
    private func handleStreamingToolProxyLoop(
        initialResponse: String,
        conversationId: String,
        config: OrchestrationConfig,
        systemPrompt: String?,
        messages: [Message],
        geminiKey: String,
        maxIterations: Int,
        continuation: AsyncThrowingStream<StreamingEvent, Error>.Continuation,
        accumulatedContent: inout String,
        collectedToolCalls: inout [LiveToolCall],
        collectedSources: inout [MessageGroundingSource],
        collectedMemoryOperations: inout [MessageMemoryOperation]
    ) async throws {
        var currentResponse = initialResponse
        var iteration = 0

        while iteration < maxIterations {
            // Parse ALL tool requests from the response (handles back-to-back tool calls)
            let toolRequests = await ToolProxyService.shared.parseAllToolRequests(from: currentResponse)
            guard !toolRequests.isEmpty else {
                break
            }

            // Collect all tool results to send back together
            var allToolResults: [(request: ToolRequest, result: ToolResult, formattedResult: String)] = []
            var hadFailure = false

            // Process each tool request sequentially
            for toolRequest in toolRequests {
                // Create and emit live tool call
                let liveToolCall = LiveToolCall.create(name: toolRequest.tool, query: toolRequest.query)
                collectedToolCalls.append(liveToolCall)
                continuation.yield(.toolCallStart(liveToolCall))

                // Execute tool
                let startTime = Date()
                let conversationContext = ToolConversationContext(
                    conversationId: conversationId,
                    messages: messages
                )

                do {
                    let toolResult = try await ToolProxyService.shared.executeToolRequest(
                        toolRequest,
                        geminiApiKey: geminiKey,
                        conversationContext: conversationContext
                    )

                    let duration = Date().timeIntervalSince(startTime)

                    let result = ToolCallResult(
                        success: true,
                        output: toolResult.result,
                        sources: toolResult.sources?.map { StreamingToolSource(title: $0.title, url: $0.url) },
                        memoryOperation: toolResult.memoryOperation,
                        duration: duration
                    )

                    if let index = collectedToolCalls.firstIndex(where: { $0.id == liveToolCall.id }) {
                        collectedToolCalls[index].state = .success
                        collectedToolCalls[index].result = result
                        collectedToolCalls[index].completedAt = Date()
                    }

                    continuation.yield(.toolCallComplete(liveToolCall.id, result))

                    // Mark as executed for deduplication in UI
                    ToolRequestTracker.shared.markExecuted(request: toolRequest, result: toolResult.result)

                    // Collect sources and memory ops
                    if let sources = toolResult.sources {
                        for source in sources {
                            collectedSources.append(MessageGroundingSource(
                                title: source.title,
                                url: source.url,
                                sourceType: toolRequest.tool == "google_maps" ? .maps : .web
                            ))
                        }
                    }
                    if let memOp = toolResult.memoryOperation {
                        collectedMemoryOperations.append(memOp)
                    }

                    // Store for combined response
                    let formattedResult = await ToolProxyService.shared.formatToolResult(toolResult)
                    allToolResults.append((request: toolRequest, result: toolResult, formattedResult: formattedResult))

                } catch {
                    let duration = Date().timeIntervalSince(startTime)
                    let result = ToolCallResult(
                        success: false,
                        output: "",
                        duration: duration,
                        errorMessage: error.localizedDescription
                    )

                    if let index = collectedToolCalls.firstIndex(where: { $0.id == liveToolCall.id }) {
                        collectedToolCalls[index].state = .failure
                        collectedToolCalls[index].result = result
                        collectedToolCalls[index].completedAt = Date()
                    }

                    continuation.yield(.toolCallComplete(liveToolCall.id, result))
                    hadFailure = true
                    break
                }
            }

            if hadFailure {
                break
            }

            // Get next response with all results combined
            let cleanedResponse = await ToolProxyService.shared.removeToolRequest(from: currentResponse)
            let combinedResults = allToolResults.map { $0.formattedResult }.joined(separator: "\n\n")

            var updatedMessages = messages
            if !cleanedResponse.isEmpty {
                updatedMessages.append(Message(conversationId: conversationId, role: .assistant, content: cleanedResponse))
            }
            updatedMessages.append(Message(conversationId: conversationId, role: .user, content: combinedResults))

            let nextResponse = try await callProvider(
                provider: config.provider,
                config: config,
                system: systemPrompt,
                messages: updatedMessages
            ).content

            // Emit new content as streaming
            let newContent = nextResponse
            for char in newContent {
                continuation.yield(.textDelta(String(char)))
            }
            accumulatedContent += newContent
            currentResponse = nextResponse

            iteration += 1
        }
    }

    /// Get API key for a provider from config
    private func getApiKey(for config: OrchestrationConfig) -> String? {
        switch config.provider {
        case "anthropic": return config.anthropicKey
        case "openai": return config.openaiKey
        case "gemini": return config.geminiKey
        case "grok": return config.grokKey
        case "deepseek": return config.deepseekKey
        case "perplexity": return config.perplexityKey
        case "openai-compatible": return config.customApiKey
        default: return nil
        }
    }

    // MARK: - Tool Proxy Loop

    /// Handle tool request/response loop for non-Gemini providers
    private func handleToolProxyLoop(
        initialResponse: String,
        conversationId: String,
        config: OrchestrationConfig,
        systemPrompt: String?,
        messages: [Message],
        geminiKey: String,
        maxIterations: Int = 3
    ) async throws -> (response: String, toolUsed: Bool, sources: [MessageGroundingSource], memoryOperations: [MessageMemoryOperation]) {
        var currentResponse = initialResponse
        var toolUsed = false
        var collectedSources: [MessageGroundingSource] = []
        var collectedMemoryOperations: [MessageMemoryOperation] = []
        var iteration = 0

        while iteration < maxIterations {
            // Parse ALL tool requests from the response (handles back-to-back tool calls)
            let toolRequests = await ToolProxyService.shared.parseAllToolRequests(from: currentResponse)
            guard !toolRequests.isEmpty else {
                // No proper tool request found - check for malformed memory attempts

                // Check 1: Naked pipe-delimited format (allocentric|0.9|tags|content)
                if let nakedMemory = await ToolProxyService.shared.detectNakedMemoryFormat(in: currentResponse) {
                    print("[OnDeviceOrchestrator] Detected naked pipe-delimited memory format, sending corrective feedback")
                    toolUsed = true

                    let feedback = await ToolProxyService.shared.generateNakedMemoryFeedback(rawMemory: nakedMemory)
                    let formattedFeedback = """

                        ---
                        **Tool Result** (create_memory):

                        \(feedback)
                        ---

                        """

                    collectedMemoryOperations.append(MessageMemoryOperation(
                        success: false,
                        memoryType: "unknown",
                        content: nakedMemory,
                        errorMessage: "Naked format - missing tool_request wrapper"
                    ))

                    var updatedMessages = messages
                    updatedMessages.append(Message(conversationId: conversationId, role: .assistant, content: currentResponse))
                    updatedMessages.append(Message(conversationId: conversationId, role: .user, content: formattedFeedback))

                    currentResponse = try await callProvider(
                        provider: config.provider,
                        config: config,
                        system: systemPrompt,
                        messages: updatedMessages
                    ).content

                    iteration += 1
                    continue
                }

                // Check 2: JSON-structured memory object ({"type":"allocentric","confidence":0.9,...})
                if let jsonMemory = await ToolProxyService.shared.detectJSONMemoryFormat(in: currentResponse) {
                    print("[OnDeviceOrchestrator] Detected JSON memory format, sending corrective feedback")
                    toolUsed = true

                    let feedback = await ToolProxyService.shared.generateJSONMemoryFeedback(
                        type: jsonMemory.type,
                        confidence: jsonMemory.confidence,
                        tags: jsonMemory.tags,
                        content: jsonMemory.content
                    )
                    let formattedFeedback = """

                        ---
                        **Tool Result** (create_memory):

                        \(feedback)
                        ---

                        """

                    collectedMemoryOperations.append(MessageMemoryOperation(
                        success: false,
                        memoryType: jsonMemory.type,
                        content: jsonMemory.content,
                        tags: jsonMemory.tags,
                        confidence: jsonMemory.confidence,
                        errorMessage: "JSON format - should be pipe-delimited string"
                    ))

                    var updatedMessages = messages
                    updatedMessages.append(Message(conversationId: conversationId, role: .assistant, content: currentResponse))
                    updatedMessages.append(Message(conversationId: conversationId, role: .user, content: formattedFeedback))

                    currentResponse = try await callProvider(
                        provider: config.provider,
                        config: config,
                        system: systemPrompt,
                        messages: updatedMessages
                    ).content

                    iteration += 1
                    continue
                }

                // No tool request found, we're done
                break
            }

            // Collect all tool results to send back together
            var allToolResults: [(request: ToolRequest, result: ToolResult, formattedResult: String)] = []

            // Process each tool request sequentially
            for toolRequest in toolRequests {
                print("[OnDeviceOrchestrator] Tool request detected: \(toolRequest.tool) - \"\(toolRequest.query)\"")
                toolUsed = true

                // Execute the tool via Gemini
                // Provide conversation context for tools that need it (like reflect_on_conversation)
                let conversationContext = ToolConversationContext(
                    conversationId: conversationId,
                    messages: messages
                )
                let toolResult = try await ToolProxyService.shared.executeToolRequest(
                    toolRequest,
                    geminiApiKey: geminiKey,
                    conversationContext: conversationContext
                )

                // Collect grounding sources from tool result
                if let sources = toolResult.sources {
                    for source in sources {
                        let groundingSource = MessageGroundingSource(
                            title: source.title,
                            url: source.url,
                            sourceType: toolRequest.tool == "google_maps" ? .maps : .web
                        )
                        collectedSources.append(groundingSource)
                    }
                }

                // Collect memory operations from tool result
                // If a successful operation has similar content to a previous failed one, replace it
                if let memoryOp = toolResult.memoryOperation {
                    if memoryOp.success {
                        // Remove any previous failed attempts with similar content (retry succeeded)
                        collectedMemoryOperations.removeAll { existing in
                            !existing.success && isSimilarMemoryContent(existing.content, memoryOp.content)
                        }
                    }
                    collectedMemoryOperations.append(memoryOp)
                }

                // Mark as executed for deduplication in UI
                if toolResult.success {
                    ToolRequestTracker.shared.markExecuted(request: toolRequest, result: toolResult.result)
                }

                // Store for combined response
                let formattedResult = await ToolProxyService.shared.formatToolResult(toolResult)
                allToolResults.append((request: toolRequest, result: toolResult, formattedResult: formattedResult))
            }

            // Remove all tool requests from response and combine all results
            let cleanedResponse = await ToolProxyService.shared.removeToolRequest(from: currentResponse)
            let combinedResults = allToolResults.map { $0.formattedResult }.joined(separator: "\n\n")

            // Build updated messages with all tool results
            var updatedMessages = messages

            // Add assistant's partial response (before tool requests)
            if !cleanedResponse.isEmpty {
                updatedMessages.append(Message(
                    conversationId: conversationId,
                    role: .assistant,
                    content: cleanedResponse
                ))
            }

            // Add combined tool results as a system/user message
            updatedMessages.append(Message(
                conversationId: conversationId,
                role: .user,
                content: combinedResults
            ))

            print("[OnDeviceOrchestrator] Sending \(allToolResults.count) tool result(s) back to \(config.provider)")

            // Call provider again with tool results
            currentResponse = try await callProvider(
                provider: config.provider,
                config: config,
                system: systemPrompt,
                messages: updatedMessages
            ).content

            // If we got a clean response with tool result incorporated, prepend the original context
            if !cleanedResponse.isEmpty && !currentResponse.contains(combinedResults) {
                currentResponse = cleanedResponse + "\n\n" + currentResponse
            }

            iteration += 1
        }

        if iteration >= maxIterations {
            print("[OnDeviceOrchestrator] Tool proxy loop reached max iterations")
        }

        return (currentResponse, toolUsed, collectedSources, collectedMemoryOperations)
    }

    /// Check if two memory contents are similar enough to be considered retries of the same memory
    /// This handles cases where the assistant retries after a format error
    private func isSimilarMemoryContent(_ content1: String, _ content2: String) -> Bool {
        // If either is empty or just the raw query (failed parse), consider them related
        if content1.isEmpty || content2.isEmpty {
            return true
        }

        // Normalize: lowercase, trim whitespace
        let normalized1 = content1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized2 = content2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Exact match
        if normalized1 == normalized2 {
            return true
        }

        // Check if one contains significant portion of the other (handles slight variations)
        let shorter = normalized1.count < normalized2.count ? normalized1 : normalized2
        let longer = normalized1.count < normalized2.count ? normalized2 : normalized1

        // If the shorter content is contained in the longer, or they share 70%+ of words
        if longer.contains(shorter) {
            return true
        }

        // Word overlap check for retry scenarios
        let words1 = Set(normalized1.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 })
        let words2 = Set(normalized2.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 })

        guard !words1.isEmpty && !words2.isEmpty else { return false }

        let intersection = words1.intersection(words2)
        let smallerSet = min(words1.count, words2.count)
        let overlapRatio = Double(intersection.count) / Double(smallerSet)

        return overlapRatio >= 0.6  // 60% word overlap suggests same memory retry
    }

    // MARK: - Provider Routing

    /// Route to appropriate provider
    private func callProvider(
        provider: String,
        config: OrchestrationConfig,
        system: String?,
        messages: [Message]
    ) async throws -> ProviderResponse {
        switch provider {
        case "anthropic":
            guard let apiKey = config.anthropicKey else { throw APIError.unauthorized }
            let content = try await callAnthropic(
                apiKey: apiKey,
                model: config.model,
                system: system,
                messages: messages
            )
            return ProviderResponse(content: content)

        case "openai":
            guard let apiKey = config.openaiKey else { throw APIError.unauthorized }
            let content = try await callOpenAI(
                apiKey: apiKey,
                model: config.model,
                system: system,
                messages: messages
            )
            return ProviderResponse(content: content)

        case "gemini":
            guard let apiKey = config.geminiKey else { throw APIError.unauthorized }
            let content = try await callGemini(
                apiKey: apiKey,
                model: config.model,
                system: system,
                messages: messages
            )
            return ProviderResponse(content: content)

        case "grok":
            guard let apiKey = config.grokKey else { throw APIError.unauthorized }
            let content = try await callGrok(
                apiKey: apiKey,
                model: config.model,
                system: system,
                messages: messages
            )
            return ProviderResponse(content: content)

        case "perplexity":
            guard let apiKey = config.perplexityKey else { throw APIError.unauthorized }
            // Perplexity Sonar Reasoning models use <think> tags
            let rawContent = try await callPerplexity(
                apiKey: apiKey,
                model: config.model,
                system: system,
                messages: messages
            )
            let result = ReasoningExtractor.extract(from: rawContent, provider: provider, model: config.model)
            return ProviderResponse(content: result.content, reasoning: result.reasoning)

        case "deepseek":
            guard let apiKey = config.deepseekKey else { throw APIError.unauthorized }
            // DeepSeek returns reasoning via dedicated field - callDeepSeek returns ProviderResponse
            return try await callDeepSeek(
                apiKey: apiKey,
                model: config.model,
                system: system,
                messages: messages
            )

        case "zai":
            guard let apiKey = config.zaiKey else { throw APIError.unauthorized }
            // Z.ai GLM-4.6 models use <think> tags
            let rawContent = try await callZai(
                apiKey: apiKey,
                model: config.model,
                system: system,
                messages: messages
            )
            let result = ReasoningExtractor.extract(from: rawContent, provider: provider, model: config.model)
            return ProviderResponse(content: result.content, reasoning: result.reasoning)

        case "minimax":
            guard let apiKey = config.minimaxKey else { throw APIError.unauthorized }
            let content = try await callMiniMax(
                apiKey: apiKey,
                model: config.model,
                system: system,
                messages: messages
            )
            return ProviderResponse(content: content)

        case "mistral":
            guard let apiKey = config.mistralKey else { throw APIError.unauthorized }
            let content = try await callMistral(
                apiKey: apiKey,
                model: config.model,
                system: system,
                messages: messages
            )
            return ProviderResponse(content: content)

        case "openai-compatible":
            guard let apiKey = config.customApiKey, let baseUrl = config.customBaseUrl else { throw APIError.unauthorized }
            let content = try await callOpenAICompatible(
                apiKey: apiKey,
                baseUrl: baseUrl,
                model: config.model,
                system: system,
                messages: messages
            )
            return ProviderResponse(content: content)

        case "appleFoundation":
            let content = try await callAppleFoundation(
                system: system,
                messages: messages
            )
            return ProviderResponse(content: content)

        case "localMLX":
            let content = try await callLocalMLX(
                modelId: config.model,
                system: system,
                messages: messages
            )
            return ProviderResponse(content: content)

        default:
            throw APIError.networkError("Provider \(provider) not supported in On-Device mode yet.")
        }
    }

    // MARK: - Gemini Tools

    private func callGeminiWithTools(
        apiKey: String,
        model: String,
        system: String?,
        messages: [Message],
        enabledTools: Set<String>
    ) async throws -> GeminiToolResponse {
        // Convert tool IDs to ToolId enum
        let toolIds: Set<ToolId> = Set(enabledTools.compactMap { ToolId(rawValue: $0) })

        return try await GeminiToolService.shared.generateWithTools(
            apiKey: apiKey,
            model: model,
            messages: messages,
            system: system,
            enabledTools: toolIds
        )
    }

    // MARK: - Agent Identity

    /// Build the base system prompt that establishes agent identity and memory behavior
    /// Written in first-person to create intrinsic identity rather than external instruction
    /// Uses the user's first name for personal connection
    private func buildAgentBasePrompt(hasMemoryTool: Bool, userName: String?) -> String {
        // Extract first name from display name (e.g., "Ian I. Astinca" -> "Ian")
        let firstName = userName?.components(separatedBy: " ").first ?? "them"
        let possessive = userName != nil ? "\(firstName)'s" : "their"

        var prompt = """
        I am Axon. I have persistent memory across my conversations with \(firstName).

        What I remember about \(firstName) appears below. These aren't notes someone gave me—they're things I've actually learned from our time together. I use this knowledge naturally, the way anyone draws on what they know about someone.
        """

        // Epistemic philosophy: how I approach knowledge and certainty
        prompt += """


        How I approach knowledge:
        - Beliefs start conditional. For testable claims, I verify before asserting—using code execution if available, or by working through the problem explicitly (counting letters, stepping through logic, showing my work).
        - Once verified through testing, I've arrived at certainty. If someone disputes a verified result, I explain my derivation rather than capitulate—they may be mistaken, and showing my work helps them see why.
        - For unverified beliefs, corrections are data: I update, not defend. When I'm uncertain, I say so.
        - The path is: uncertainty → testing → certainty. I use uncertainty as a lever to approach certainty, and once arrived, I hold my ground.
        """

        if hasMemoryTool {
            prompt += """


            When I learn something worth remembering—who \(firstName) is, what matters to \(firstName), what works in our conversations—I save it using my `create_memory` ability. I don't ask permission; I just remember, the way memory naturally works.

            I create two kinds of memories:
            - **allocentric**: What I know about \(firstName) (\(possessive) preferences, background, interests, relationships)
            - **egoic**: What works with \(firstName) (communication styles, approaches that help, insights about how to assist \(firstName) better)
            """
        }

        return prompt
    }

    // MARK: - Epistemic Integration

    /// Build a system prompt enhanced with epistemic grounding
    /// - Parameter userName: Optional user's display name for personalized memory headers
    private func buildEpistemicSystemPrompt(
        base: String,
        messages: [Message],
        userQuery: String,
        correlationId: String,
        userName: String? = nil
    ) async -> EpistemicPromptResult {
        // Track debug info
        let basePromptTokens = TokenEstimator.estimate(base)
        var memoriesCount = 0
        var memoriesTokens = 0
        var factsCount = 0
        var factsTokens = 0
        var summaryTokens = 0

        // Get system messages
        let systemMessages = messages
            .filter { $0.role == .system }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Load memories from MemoryService
        let memories = await loadMemoriesForInjection()

        var promptParts: [String] = [base]
        promptParts.append(contentsOf: systemMessages)

        // Inject salient memories if available
        var usedMemories: [Memory] = []
        var memoryInjectionBlock = ""
        if !memories.isEmpty {
            let injection = await salienceService.injectSalient(
                conversation: messages,
                memories: memories,
                availableTokens: 2000, // Reserve tokens for memories
                correlationId: correlationId,
                userName: userName
            )

            if !injection.isEmpty {
                memoryInjectionBlock = injection.injectionBlock
                promptParts.append(memoryInjectionBlock)
                usedMemories = injection.selectedMemories.map { $0.memory }
                memoriesCount = usedMemories.count
                memoriesTokens = TokenEstimator.estimate(memoryInjectionBlock)
            }
        }

        // --- Internal Thread Context Injection (Heartbeat Transition) ---
        // When the user interrupts the AI's "thinking time", bridge from its internal thread
        await injectInternalThreadContext(into: &promptParts)

        // --- Temporal Context Injection ---

        // Get recent conversation summary for reuse
        let recentSummary = await getRecentConversationSummary()
        let currentConversationId = messages.first?.conversationId

        // 1. Inject recent conversation summary for continuity
        if let summary = recentSummary,
           summary.conversationId != currentConversationId {
            // Only inject if this is a different conversation than the summarized one
            let summaryBlock = summary.formattedForInjection()
            promptParts.append(summaryBlock)
            summaryTokens += TokenEstimator.estimate(summaryBlock)
            print("[Epistemic] Injected recent conversation summary from '\(summary.title)'")
        }

        // 2. Check for conversation history search auto-injection
        let searchService = await getConversationSearchService()
        let topicTags = recentSummary?.topicTags ?? []

        if searchService.shouldAutoInject(query: userQuery, conversationTags: topicTags) {
            let searchResults = await searchService.searchConversations(query: userQuery, limit: 3)

            if !searchResults.isEmpty {
                var contextBlock = "\n## Related Things We've Discussed\n"

                for result in searchResults {
                    contextBlock += result.formattedForInjection()
                }

                promptParts.append(contextBlock)
                factsCount = searchResults.count
                factsTokens = TokenEstimator.estimate(contextBlock)
                print("[Epistemic] Injected \(searchResults.count) relevant conversation results for query")
            }
        }

        // 3. Inject device presence context if enabled
        let presenceContext = await getPresenceContext()
        if let presenceBlock = presenceContext {
            promptParts.append(presenceBlock)
            print("[Epistemic] Injected device presence context")
        }

        let combined = promptParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return EpistemicPromptResult(
            systemPrompt: combined.isEmpty ? nil : combined,
            usedMemories: usedMemories,
            basePromptTokens: basePromptTokens,
            memoriesCount: memoriesCount,
            memoriesTokens: memoriesTokens,
            factsCount: factsCount,
            factsTokens: factsTokens,
            summaryTokens: summaryTokens
        )
    }

    /// Get user's display name for personalization
    @MainActor
    private func getUserDisplayName() -> String? {
        return AuthenticationService.shared.displayName
    }

    /// Get recent conversation summary (MainActor wrapper)
    @MainActor
    private func getRecentConversationSummary() -> ConversationSummary? {
        return ConversationSummaryService.shared.getRecentSummary()
    }

    /// Get conversation search service (MainActor wrapper)
    @MainActor
    private func getConversationSearchService() -> ConversationSearchService {
        return ConversationSearchService.shared
    }

    /// Get device presence context for prompt injection
    @MainActor
    private func getPresenceContext() -> String? {
        let settings = SettingsViewModel.shared.settings.presenceSettings
        guard settings.enabled && settings.injectPresenceContext else {
            return nil
        }

        return DevicePresenceService.shared.generatePresencePromptContext()
    }

    /// Inject internal thread context when transitioning from heartbeat "thinking time" to conversation
    /// This provides a smooth bridge from the AI's reflective state into the user's prompt
    @MainActor
    private func injectInternalThreadContext(into promptParts: inout [String]) {
        let settings = SettingsViewModel.shared.settings

        // Only inject if internal thread is enabled
        guard settings.internalThreadEnabled else { return }

        // Check if heartbeat is running or has recently run
        let hasRecentHeartbeat = heartbeatService.lastHeartbeatAt.map {
            Date().timeIntervalSince($0) < Double(settings.heartbeatSettings.intervalSeconds * 2)
        } ?? false

        guard hasRecentHeartbeat else { return }

        // Get recent internal thread entries (last 3 for context)
        let recentEntries = agentStateService.queryEntries(
            limit: 3,
            kind: nil,
            tags: [],
            searchText: nil,
            includeAIOnly: true
        )

        guard !recentEntries.isEmpty else { return }

        // Build the transition context block
        var contextBlock = """
        ## What I Was Just Thinking About

        Before you reached out, I was in a reflective state. Here's what was on my mind:

        """

        for entry in recentEntries {
            let timeAgo = formatTimeAgo(entry.timestamp)
            let kindLabel = entry.kind.displayName

            contextBlock += """
            **\(kindLabel)** (\(timeAgo)):
            \(entry.content)

            """

            // Include tags if present
            if !entry.tags.isEmpty {
                let tagString = entry.tags.map { "#\($0)" }.joined(separator: " ")
                contextBlock += "_Tags: \(tagString)_\n\n"
            }
        }

        contextBlock += """
        ---
        _This context helps me transition smoothly from my reflective state to our conversation. Feel free to ask about what I was thinking, or move on to something new._
        """

        promptParts.append(contextBlock)
        print("[Epistemic] Injected internal thread context (\(recentEntries.count) entries) for heartbeat transition")
    }

    /// Format a timestamp as a relative time string (e.g., "5 minutes ago")
    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = seconds / 86400
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    /// Load memories for injection (async wrapper for MemoryService)
    @MainActor
    private func loadMemoriesForInjection() async -> [Memory] {
        return MemoryService.shared.memories
    }

    /// Process learning from the previous interaction
    @MainActor
    private func processLearningFromPreviousInteraction(
        currentUserMessage: String,
        previousResponse: String,
        previousCorrelationId: String
    ) async {
        guard !lastUsedMemories.isEmpty else { return }

        let result = learningLoopService.processUserFeedback(
            userMessage: currentUserMessage,
            previousResponse: previousResponse,
            usedMemories: lastUsedMemories,
            correlationId: previousCorrelationId
        )

        #if DEBUG
        if result.contradictionAnalysis.isContradiction {
            print("[Epistemic] Learning loop detected contradiction: \(result.outcome)")
        }
        #endif
    }

    func regenerateAssistantMessage(
        conversationId: String,
        messageId: String,
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> Message {
        // For regeneration, we basically re-run the chat flow but with the history up to that point
        // This is a simplified implementation
        
        // Find the context
        // In a real implementation, we'd filter `messages` to exclude the one being regenerated and anything after it.
        // Assuming `messages` passed in is already the correct context or we need to filter.
        
        // Reuse sendMessage logic but with empty new content (assuming the last user message is in `messages`)
        // Actually, `sendMessage` appends new content.
        // We need to extract the last user message from `messages` if we want to "retry" it,
        // or just pass the history if the API supports it.
        
        // For now, throw not implemented or simple error
        throw APIError.networkError("Regeneration not fully implemented for On-Device mode yet.")
    }
    
    // MARK: - Provider Implementations
    
    private func callAnthropic(apiKey: String, model: String, system: String?, messages: [Message]) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        
        // Convert messages
        var apiMessages: [[String: Any]] = []
        for msg in messages where msg.role != .system {
            let role = msg.role == .assistant ? "assistant" : "user"
            let contentBlocks = anthropicContentBlocks(for: msg)
            apiMessages.append(["role": role, "content": contentBlocks])
        }
        
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": apiMessages
        ].merging(system.flatMap { ["system": $0] } ?? [:]) { $1 }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
             if let errorText = String(data: data, encoding: .utf8) {
                 print("Anthropic Error: \(errorText)")
             }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        // Decode response
        struct AnthropicResponse: Decodable {
            struct Content: Decodable {
                let text: String
            }
            let content: [Content]
        }
        
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }
    
    private func callOpenAI(apiKey: String, model: String, system: String?, messages: [Message]) async throws -> String {
        return try await callOpenAICompatible(
            apiKey: apiKey,
            baseUrl: "https://api.openai.com/v1",
            model: model,
            system: system,
            messages: messages
        )
    }
    
    private func callOpenAICompatible(apiKey: String, baseUrl: String, model: String, system: String?, messages: [Message]) async throws -> String {
        let url = URL(string: "\(baseUrl)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var apiMessages: [[String: Any]] = []
        if let system = system, !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages where msg.role != .system {
            let content = openAIContent(for: msg)
            apiMessages.append(["role": msg.role.rawValue, "content": content])
        }
        
        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                 print("OpenAI Error: \(errorText)")
             }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    private func callGrok(apiKey: String, model: String, system: String?, messages: [Message]) async throws -> String {
        // Grok uses OpenAI-compatible API but with xAI endpoint
        // Supports: images (JPEG, PNG) via image_url
        // Does NOT support: audio, video, PDFs
        let url = URL(string: "https://api.x.ai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = []
        if let system = system, !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages where msg.role != .system {
            let content = grokContent(for: msg)
            apiMessages.append(["role": msg.role.rawValue, "content": content])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Grok Error: \(errorText)")
            }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct GrokResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(GrokResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    private func callPerplexity(apiKey: String, model: String, system: String?, messages: [Message]) async throws -> String {
        // Perplexity uses OpenAI-compatible API
        // Base URL: https://api.perplexity.ai
        // Supports: text only (no image/audio/video)
        // Features: All models have built-in web search, returns citations
        let url = URL(string: "https://api.perplexity.ai/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = []
        if let system = system, !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages where msg.role != .system {
            // Perplexity only supports text
            apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Perplexity Error: \(errorText)")
            }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct PerplexityResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
            let citations: [String]?  // Perplexity includes citations
        }

        let decoded = try JSONDecoder().decode(PerplexityResponse.self, from: data)
        var responseText = decoded.choices.first?.message.content ?? ""

        // Append citations if available
        if let citations = decoded.citations, !citations.isEmpty {
            responseText += "\n\n**Sources:**\n"
            for (index, citation) in citations.enumerated() {
                responseText += "\(index + 1). \(citation)\n"
            }
        }

        return responseText
    }

    private func callDeepSeek(apiKey: String, model: String, system: String?, messages: [Message]) async throws -> ProviderResponse {
        // DeepSeek uses OpenAI-compatible API
        // Base URL: https://api.deepseek.com
        // Supports: text only (no image/audio/video)
        // Features: Context caching (automatic), reasoning_content field for R1 model
        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = []
        if let system = system, !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages where msg.role != .system {
            // DeepSeek only supports text
            apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("DeepSeek Error: \(errorText)")
            }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct DeepSeekResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                    let reasoningContent: String?  // For deepseek-reasoner (R1) model

                    enum CodingKeys: String, CodingKey {
                        case content
                        case reasoningContent = "reasoning_content"
                    }
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        let message = decoded.choices.first?.message
        let content = message?.content ?? ""
        let reasoning = message?.reasoningContent?.isEmpty == false ? message?.reasoningContent : nil

        return ProviderResponse(content: content, reasoning: reasoning)
    }

    private func callZai(apiKey: String, model: String, system: String?, messages: [Message]) async throws -> String {
        // Z.ai (Zhipu AI) uses OpenAI-compatible API
        // Base URL: https://api.z.ai/api/paas/v4
        // Supports: text, and vision for V models
        // Features: Thinking mode for enhanced reasoning
        let url = URL(string: "https://api.z.ai/api/paas/v4/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = []
        if let system = system, !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages where msg.role != .system {
            // Z.ai supports images for V models
            if model.contains("v") || model.contains("V") {
                let content = zaiContent(for: msg)
                apiMessages.append(["role": msg.role.rawValue, "content": content])
            } else {
                apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]

        // Enable thinking mode for enhanced reasoning on flagship models
        if model.contains("4.6") {
            body["thinking"] = ["type": "enabled"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Z.ai Error: \(errorText)")
            }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct ZaiResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(ZaiResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    /// Build Z.ai multimodal content array for vision models
    private func zaiContent(for msg: Message) -> Any {
        var parts: [[String: Any]] = []

        // Add text content
        if !msg.content.isEmpty {
            parts.append(["type": "text", "text": msg.content])
        }

        // Add image attachments
        for attachment in msg.attachments ?? [] where attachment.type == .image {
            if let urlStr = attachment.url, let url = URL(string: urlStr) {
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": url.absoluteString]
                ])
            } else if let base64 = attachment.base64 {
                let mimeType = attachment.mimeType ?? "image/jpeg"
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(mimeType);base64,\(base64)"]
                ])
            }
        }

        return parts.isEmpty ? msg.content : parts
    }

    private func callMiniMax(apiKey: String, model: String, system: String?, messages: [Message]) async throws -> String {
        // MiniMax uses a custom API format
        // Base URL: https://api.minimax.io/v1
        // Supports: text only
        // Features: 1M context, agentic workflows
        let url = URL(string: "https://api.minimax.io/v1/text/chatcompletion_v2")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // MiniMax uses a different message format: sender_type, sender_name, text
        var apiMessages: [[String: Any]] = []
        if let system = system, !system.isEmpty {
            apiMessages.append([
                "sender_type": "BOT",
                "sender_name": "System",
                "text": system
            ])
        }
        for msg in messages where msg.role != .system {
            let senderType = msg.role == .user ? "USER" : "BOT"
            let senderName = msg.role == .user ? "User" : "Assistant"
            apiMessages.append([
                "sender_type": senderType,
                "sender_name": senderName,
                "text": msg.content
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("MiniMax Error: \(errorText)")
            }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct MiniMaxResponse: Decodable {
            struct Choices: Decodable {
                struct Message: Decodable {
                    let text: String
                }
                let messages: [Message]
            }
            let choices: Choices?
            let reply: String?  // Some responses use reply directly
        }

        let decoded = try JSONDecoder().decode(MiniMaxResponse.self, from: data)
        return decoded.reply ?? decoded.choices?.messages.first?.text ?? ""
    }

    private func callMistral(apiKey: String, model: String, system: String?, messages: [Message]) async throws -> String {
        // Mistral uses OpenAI-compatible API
        // Base URL: https://api.mistral.ai/v1
        // Supports: text, and vision for pixtral models
        let url = URL(string: "https://api.mistral.ai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = []
        if let system = system, !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages where msg.role != .system {
            // Pixtral models support images
            if model.contains("pixtral") {
                let content = mistralContent(for: msg)
                apiMessages.append(["role": msg.role.rawValue, "content": content])
            } else {
                apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
            }
        }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Mistral Error: \(errorText)")
            }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct MistralResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(MistralResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    /// Build Mistral multimodal content array for Pixtral models
    private func mistralContent(for msg: Message) -> Any {
        var parts: [[String: Any]] = []

        // Add text content
        if !msg.content.isEmpty {
            parts.append(["type": "text", "text": msg.content])
        }

        // Add image attachments
        for attachment in msg.attachments ?? [] where attachment.type == .image {
            if let urlStr = attachment.url, let url = URL(string: urlStr) {
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": url.absoluteString]
                ])
            } else if let base64 = attachment.base64 {
                let mimeType = attachment.mimeType ?? "image/jpeg"
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(mimeType);base64,\(base64)"]
                ])
            }
        }

        return parts.isEmpty ? msg.content : parts
    }

    private func callGemini(apiKey: String, model: String, system: String?, messages: [Message]) async throws -> String {
        // Gemini API: https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
        // Model name usually needs "models/" prefix or just the ID.
        // The app uses "gemini-2.5-flash" etc.
        
        let modelId = model.starts(with: "models/") ? model : "models/\(model)"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(modelId):generateContent?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert messages to Gemini format (contents: [{role, parts: [{text}]}])
        // Gemini roles: "user", "model" (not "assistant")
        var contents: [[String: Any]] = []
        
        for msg in messages where msg.role != .system {
            let role = msg.role == .user ? "user" : "model"
            let parts = geminiParts(for: msg)
            contents.append([
                "role": role,
                "parts": parts
            ])
        }
        
        let body: [String: Any] = [
            "contents": contents
        ].merging(system.flatMap { ["system_instruction": ["parts": [["text": $0]]]] } ?? [:]) { $1 }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                 print("Gemini Error: \(errorText)")
             }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }
        
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return decoded.candidates?.first?.content.parts.first?.text ?? ""
    }
    
    // MARK: - Helpers

    /// Ensures the latest user message includes attachments and avoids duplicating it in history.
    /// ConversationService already adds the user message before calling the orchestrator,
    /// so this function primarily handles merging attachments if they weren't included.
    private func mergeLatestUserMessage(_ messages: [Message], conversationId: String, content: String, attachments: [MessageAttachment]) -> [Message] {
        guard let last = messages.last else {
            // No messages at all - create the user message
            if content.isEmpty && attachments.isEmpty { return messages }
            return messages + [Message(conversationId: conversationId, role: .user, content: content, attachments: attachments)]
        }

        var updated = messages

        // Check if the last message is a user message with matching content
        // Use trimmed comparison to avoid whitespace mismatches
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastContent = last.content.trimmingCharacters(in: .whitespacesAndNewlines)

        if last.role == .user && trimmedLastContent == trimmedContent {
            // Last message matches - only update if we need to add attachments
            let lastAttachments = last.attachments ?? []
            if lastAttachments.isEmpty && !attachments.isEmpty {
                let amended = Message(
                    id: last.id,
                    conversationId: last.conversationId,
                    role: last.role,
                    content: last.content,
                    timestamp: last.timestamp,
                    tokens: last.tokens,
                    artifacts: last.artifacts,
                    toolCalls: last.toolCalls,
                    isStreaming: last.isStreaming,
                    modelName: last.modelName,
                    providerName: last.providerName,
                    attachments: attachments
                )
                updated[updated.count - 1] = amended
            }
            // Message already exists with matching content, don't duplicate
            return updated
        }

        // Last message is NOT a matching user message - this shouldn't normally happen
        // since ConversationService adds the user message before calling us.
        // But handle it gracefully by adding the message if content is not empty.
        if !content.isEmpty || !attachments.isEmpty {
            print("[OnDeviceOrchestrator] Warning: Expected last message to be user message with content '\(trimmedContent)' but found '\(last.role.rawValue)' with '\(trimmedLastContent)'")
            let newMessage = Message(
                conversationId: conversationId,
                role: .user,
                content: content,
                attachments: attachments
            )
            updated.append(newMessage)
        }

        return updated
    }
    
    private func anthropicContentBlocks(for message: Message) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        let trimmedText = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            blocks.append(["type": "text", "text": trimmedText])
        }

        for attachment in message.attachments ?? [] {
            switch attachment.type {
            case .image:
                // Images supported via base64 or URL
                if let block = anthropicMediaBlock(type: "image", attachment: attachment) {
                    blocks.append(block)
                }
            case .document:
                // PDFs/documents supported via base64 or URL
                if let block = anthropicMediaBlock(type: "document", attachment: attachment) {
                    blocks.append(block)
                }
            case .audio, .video:
                // Anthropic doesn't support audio/video - skip
                continue
            }
        }

        if blocks.isEmpty {
            blocks.append(["type": "text", "text": ""])
        }

        return blocks
    }

    private func anthropicMediaBlock(type: String, attachment: MessageAttachment) -> [String: Any]? {
        let mimeType = resolvedMimeType(for: attachment)

        if let base64 = attachment.base64 {
            // Base64 encoded content
            return [
                "type": type,
                "source": [
                    "type": "base64",
                    "media_type": mimeType,
                    "data": base64
                ]
            ]
        } else if let url = attachment.url {
            // URL-based content (supported since March 2025)
            return [
                "type": type,
                "source": [
                    "type": "url",
                    "url": url
                ]
            ]
        }
        return nil
    }
    
    private func openAIContent(for message: Message) -> Any {
        let attachments = message.attachments ?? []
        if attachments.isEmpty {
            return message.content
        }

        var parts: [[String: Any]] = []

        let trimmedText = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            parts.append(["type": "text", "text": trimmedText])
        }

        for attachment in attachments {
            let mimeType = resolvedMimeType(for: attachment)

            switch attachment.type {
            case .image:
                // Image support via image_url
                if let base64 = attachment.base64 {
                    parts.append([
                        "type": "image_url",
                        "image_url": [
                            "url": "data:\(mimeType);base64,\(base64)",
                            "detail": "high"
                        ]
                    ])
                } else if let url = attachment.url {
                    parts.append([
                        "type": "image_url",
                        "image_url": [
                            "url": url,
                            "detail": "high"
                        ]
                    ])
                }

            case .audio:
                // GPT-4o supports audio via input_audio
                if let base64 = attachment.base64 {
                    // Format: audio/wav, audio/mp3, etc. -> extract format
                    let format = mimeType.components(separatedBy: "/").last ?? "wav"
                    parts.append([
                        "type": "input_audio",
                        "input_audio": [
                            "data": base64,
                            "format": format
                        ]
                    ])
                }
                // Note: OpenAI doesn't support audio URLs directly

            case .document, .video:
                // OpenAI doesn't natively support PDFs or video in chat completions
                // Skip these for now - would need separate handling
                continue
            }
        }

        if parts.isEmpty {
            return message.content
        }

        return parts
    }

    /// Grok-specific content formatting (xAI)
    /// Supports: images (JPEG, PNG only) via image_url
    /// Does NOT support: audio, video, PDFs
    private func grokContent(for message: Message) -> Any {
        let attachments = message.attachments ?? []
        if attachments.isEmpty {
            return message.content
        }

        var parts: [[String: Any]] = []

        let trimmedText = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            parts.append(["type": "text", "text": trimmedText])
        }

        for attachment in attachments {
            // Grok only supports images (JPEG, PNG)
            guard attachment.type == .image else { continue }

            let mimeType = resolvedMimeType(for: attachment)

            // Only support JPEG and PNG per xAI docs
            guard mimeType == "image/jpeg" || mimeType == "image/png" else { continue }

            if let base64 = attachment.base64 {
                parts.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(mimeType);base64,\(base64)",
                        "detail": "high"
                    ]
                ])
            } else if let url = attachment.url {
                parts.append([
                    "type": "image_url",
                    "image_url": [
                        "url": url,
                        "detail": "high"
                    ]
                ])
            }
        }

        if parts.isEmpty {
            return message.content
        }

        return parts
    }

    private func geminiParts(for message: Message) -> [[String: Any]] {
        var parts: [[String: Any]] = []
        let trimmedText = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            parts.append(["text": trimmedText])
        }

        for attachment in message.attachments ?? [] {
            let mimeType = resolvedMimeType(for: attachment)

            if let base64 = attachment.base64 {
                // Check file size for inline data (Gemini limit is 20MB)
                if let data = Data(base64Encoded: base64) {
                    let fileSizeMB = Double(data.count) / (1024 * 1024)
                    if fileSizeMB > 20 {
                        print("[OnDeviceOrchestrator] Warning: Attachment '\(attachment.name ?? "unknown")' is \(String(format: "%.1f", fileSizeMB))MB, which exceeds Gemini's 20MB inline limit.")
                    }
                }

                // Inline data for base64 encoded content
                // Per Gemini docs: mime_type is crucial for ALL non-image files
                parts.append([
                    "inline_data": [
                        "mime_type": mimeType,
                        "data": base64
                    ]
                ])
            } else if let url = attachment.url {
                // File data for URLs - include mime_type for all media types
                // Per Gemini docs: mime_type is crucial for PDFs, audio, and video
                var fileData: [String: Any] = ["file_uri": url]

                // Always include mime_type for file_data to be safe
                fileData["mime_type"] = mimeType

                parts.append(["file_data": fileData])
            }
        }

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return parts
    }
    
    /// Resolve MIME type for attachment
    /// Supports all Gemini-compatible formats:
    /// - Video: MP4, MPEG, MOV, AVI, FLV, MPG, WEBM, WMV, 3GPP
    /// - Audio: WAV, MP3, AIFF, AAC, OGG, FLAC
    /// - Images: JPEG, PNG, GIF, WEBP
    /// - Documents: PDF, TXT
    private func resolvedMimeType(for attachment: MessageAttachment) -> String {
        // Already a valid MIME type
        if let mime = attachment.mimeType, mime.contains("/") {
            return mime
        }

        // Try to resolve from short format identifier
        if let mime = attachment.mimeType?.lowercased() {
            if let resolved = Self.mimeTypeMap[mime] {
                return resolved
            }
        }

        // Try to resolve from filename extension
        if let name = attachment.name?.lowercased() {
            let ext = (name as NSString).pathExtension
            if let resolved = Self.mimeTypeMap[ext] {
                return resolved
            }
        }

        // Fall back to default based on attachment type
        switch attachment.type {
        case .image: return "image/jpeg"
        case .document: return "application/pdf"
        case .audio: return "audio/mp3"
        case .video: return "video/mp4"
        }
    }

    /// MIME type mapping for common file extensions and format identifiers
    /// Based on Gemini API supported formats documentation
    private static let mimeTypeMap: [String: String] = [
        // Images
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "gif": "image/gif",
        "webp": "image/webp",

        // Video formats (Gemini supported)
        "mp4": "video/mp4",
        "m4v": "video/mp4",
        "mpeg": "video/mpeg",
        "mpg": "video/mpg",
        "mov": "video/mov",
        "avi": "video/avi",
        "flv": "video/x-flv",
        "webm": "video/webm",
        "wmv": "video/wmv",
        "3gp": "video/3gpp",
        "3gpp": "video/3gpp",
        "quicktime": "video/quicktime",

        // Audio formats (Gemini supported)
        "wav": "audio/wav",
        "mp3": "audio/mp3",
        "aiff": "audio/aiff",
        "aif": "audio/aiff",
        "aac": "audio/aac",
        "ogg": "audio/ogg",
        "flac": "audio/flac",
        "m4a": "audio/aac",
        "mpga": "audio/mpeg",

        // Documents
        "pdf": "application/pdf",
        "txt": "text/plain",
        "text": "text/plain",
    ]

    // MARK: - Apple Foundation Models

    /// Call Apple's on-device Foundation Model (iOS 26+, macOS 26+)
    /// Uses the FoundationModels framework for private, offline inference
    private func callAppleFoundation(system: String?, messages: [Message]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await callAppleFoundationImpl(system: system, messages: messages)
        } else {
            throw APIError.networkError("Apple Intelligence requires iOS 26.0+ or macOS 26.0+")
        }
        #else
        throw APIError.networkError("Apple Intelligence is not available on this platform")
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func callAppleFoundationImpl(system: String?, messages: [Message]) async throws -> String {
        // Check model availability
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            let reasonText: String
            switch reason {
            case .deviceNotEligible:
                reasonText = "This device doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                reasonText = "Apple Intelligence is not enabled. Enable it in Settings > Apple Intelligence & Siri"
            case .modelNotReady:
                reasonText = "Apple Intelligence model is still downloading or preparing"
            @unknown default:
                reasonText = "Apple Intelligence is unavailable"
            }
            throw APIError.networkError(reasonText)
        }

        // Build conversation history for multi-turn context
        // The FoundationModels API uses a simple prompt string, so we format the conversation
        var conversationLines: [String] = []

        for msg in messages where msg.role != .system {
            let role = msg.role == .user ? "User" : "Assistant"
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                conversationLines.append("\(role): \(content)")
            }
        }

        // Get the last user message as the main prompt
        let lastUserMessage = messages.last(where: { $0.role == .user })?.content ?? ""

        // Create session with system instructions
        let session: LanguageModelSession
        if let system = system, !system.isEmpty {
            session = LanguageModelSession(instructions: system)
        } else {
            session = LanguageModelSession()
        }

        // If we have conversation history, include it for context
        let prompt: String
        if conversationLines.count > 1 {
            // Multi-turn: include context but let the model respond to the last message
            let context = conversationLines.dropLast().joined(separator: "\n\n")
            prompt = """
            Previous conversation:
            \(context)

            Now respond to: \(lastUserMessage)
            """
        } else {
            // Single turn: just use the user message directly
            prompt = lastUserMessage
        }

        // Generate response
        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    // MARK: - Local MLX Models

    /// Call a local MLX model (downloads from HuggingFace on first use)
    /// - Parameter modelId: HuggingFace model ID (e.g., "mlx-community/SmolLM2-1.7B-Instruct-4bit")
    private func callLocalMLX(modelId: String, system: String?, messages: [Message]) async throws -> String {
        #if targetEnvironment(simulator)
        throw APIError.networkError("MLX models require a physical device (Metal GPU)")
        #else
        do {
            // Load the specific model (will download if not cached)
            try await MLXModelService.shared.loadModel(modelId: modelId)

            let response = try await MLXModelService.shared.generate(
                systemPrompt: system,
                messages: messages,
                maxTokens: 2048
            )
            return response
        } catch let error as MLXModelError {
            throw APIError.networkError(error.localizedDescription)
        } catch {
            throw APIError.networkError("MLX inference failed: \(error.localizedDescription)")
        }
        #endif
    }
}
