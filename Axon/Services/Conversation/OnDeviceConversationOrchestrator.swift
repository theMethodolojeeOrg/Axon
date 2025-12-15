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

/// Result from provider API calls including content and optional reasoning
struct ProviderResponse {
    let content: String
    let reasoning: String?

    init(content: String, reasoning: String? = nil) {
        self.content = content
        self.reasoning = reasoning
    }
}

class OnDeviceConversationOrchestrator: ConversationOrchestrator {

    // MARK: - Services

    private let predicateLogger = PredicateLogger.shared
    private let salienceService = SalienceService.shared
    private let learningLoopService = LearningLoopService.shared

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
        var (systemPrompt, usedMemories) = await buildEpistemicSystemPrompt(
            base: basePrompt,
            messages: mergedMessages,
            userQuery: content,
            correlationId: correlationId,
            userName: userName
        )

        // Filter tools based on model capabilities
        // Gemini 3 supports most tools but NOT google_maps
        let filteredGeminiTools = filterToolsForModel(requestedGeminiTools, model: config.model)
        let hasFilteredTools = !filteredGeminiTools.isEmpty

        // Use tool proxy for non-Gemini providers (Claude, GPT, Grok) with tools enabled
        let useToolProxy = hasGeminiTools && !isGeminiProvider
        if useToolProxy {
            let enabledToolIds = Set(requestedGeminiTools.compactMap { ToolId(rawValue: $0) })
            let toolPrompt = await ToolProxyService.shared.generateToolSystemPrompt(enabledTools: enabledToolIds)
            systemPrompt = (systemPrompt ?? "") + toolPrompt
            print("[OnDeviceOrchestrator] Tool proxy mode (non-Gemini provider): injected tool prompt for \(enabledToolIds.count) tools")
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
                let (finalResponse, toolUsed, sources, memOps) = try await handleToolProxyLoop(
                    initialResponse: responseContent,
                    conversationId: conversationId,
                    config: config,
                    systemPrompt: systemPrompt,
                    messages: finalMessages,
                    geminiKey: geminiKey
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
            // Check for tool request in response
            guard let toolRequest = await ToolProxyService.shared.parseToolRequest(from: currentResponse) else {
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

            // Format tool result
            let formattedResult = await ToolProxyService.shared.formatToolResult(toolResult)

            // Remove tool request from response and append result
            let cleanedResponse = await ToolProxyService.shared.removeToolRequest(from: currentResponse)

            // Build updated messages with tool result
            var updatedMessages = messages

            // Add assistant's partial response (before tool request)
            if !cleanedResponse.isEmpty {
                updatedMessages.append(Message(
                    conversationId: conversationId,
                    role: .assistant,
                    content: cleanedResponse
                ))
            }

            // Add tool result as a system/user message
            updatedMessages.append(Message(
                conversationId: conversationId,
                role: .user,
                content: formattedResult
            ))

            print("[OnDeviceOrchestrator] Sending tool result back to \(config.provider)")

            // Call provider again with tool results
            currentResponse = try await callProvider(
                provider: config.provider,
                config: config,
                system: systemPrompt,
                messages: updatedMessages
            ).content

            // If we got a clean response with tool result incorporated, prepend the original context
            if !cleanedResponse.isEmpty && !currentResponse.contains(formattedResult) {
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
    ) async -> (String?, [Memory]) {
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
        if !memories.isEmpty {
            let injection = await salienceService.injectSalient(
                conversation: messages,
                memories: memories,
                availableTokens: 2000, // Reserve tokens for memories
                correlationId: correlationId,
                userName: userName
            )

            if !injection.isEmpty {
                promptParts.append(injection.injectionBlock)
                usedMemories = injection.selectedMemories.map { $0.memory }
            }
        }

        // --- Temporal Context Injection ---

        // Get recent conversation summary for reuse
        let recentSummary = await getRecentConversationSummary()
        let currentConversationId = messages.first?.conversationId

        // 1. Inject recent conversation summary for continuity
        if let summary = recentSummary,
           summary.conversationId != currentConversationId {
            // Only inject if this is a different conversation than the summarized one
            promptParts.append(summary.formattedForInjection())
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
                print("[Epistemic] Injected \(searchResults.count) relevant conversation results for query")
            }
        }

        let combined = promptParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return (combined.isEmpty ? nil : combined, usedMemories)
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
                // Inline data for base64 encoded content
                parts.append([
                    "inline_data": [
                        "mime_type": mimeType,
                        "data": base64
                    ]
                ])
            } else if let url = attachment.url {
                // File data for URLs - include mime_type for PDFs and other documents
                var fileData: [String: Any] = ["file_uri": url]

                // Per Gemini docs: mime_type is crucial for PDFs and non-image files
                if attachment.type == .document || attachment.type == .audio || attachment.type == .video {
                    fileData["mime_type"] = mimeType
                }

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
}
