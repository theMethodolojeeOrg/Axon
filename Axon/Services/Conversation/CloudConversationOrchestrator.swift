//
//  CloudConversationOrchestrator.swift
//  Axon
//
//  Implementation of ConversationOrchestrator that uses the Firebase Cloud Functions backend.
//

import Foundation

class CloudConversationOrchestrator: ConversationOrchestrator {
    private let apiClient = APIClient.shared
    private let defaultProjectId = "default"

    // MARK: - Temporal Context Helpers

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

    /// Build temporal context to prepend to user message for continuity
    private func buildTemporalContext(userQuery: String, currentConversationId: String) async -> String? {
        var contextParts: [String] = []

        // 1. Inject recent conversation summary for continuity
        let recentSummary = await getRecentConversationSummary()
        if let summary = recentSummary,
           summary.conversationId != currentConversationId {
            contextParts.append(summary.formattedForInjection())
            print("[CloudOrchestrator] Injected recent conversation summary from '\(summary.title)'")
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

                contextParts.append(contextBlock)
                print("[CloudOrchestrator] Injected \(searchResults.count) relevant conversation results for query")
            }
        }

        guard !contextParts.isEmpty else { return nil }

        return contextParts.joined(separator: "\n\n")
    }

    func sendMessage(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment],
        enabledTools: [String],
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> (assistantMessage: Message, memories: [Memory]?) {

        // Build temporal context (recent conversation summary, relevant past conversations)
        let temporalContext = await buildTemporalContext(userQuery: content, currentConversationId: conversationId)

        // Prepend temporal context to content if available
        // First-person framing for intrinsic memory
        let enrichedContent: String
        if let context = temporalContext {
            enrichedContent = """
            [What I recall from our recent conversations]
            \(context)

            [Their message]
            \(content)
            """
        } else {
            enrichedContent = content
        }

        // Construct content payload (String or Array)
        let contentPayload: AnyCodable
        if attachments.isEmpty {
            contentPayload = .string(enrichedContent)
        } else {
            var parts: [AnyCodable] = []

            // Add text part if not empty
            if !enrichedContent.isEmpty {
                parts.append(.object([
                    "type": .string("text"),
                    "text": .string(enrichedContent)
                ]))
            }
            
            // Add attachment parts - flattened structure matching backend expectations
            for attachment in attachments {
                let resolvedMimeType = AttachmentMimePolicyService.resolveMimeType(for: attachment)
                switch attachment.type {
                case .image:
                    if let base64 = attachment.base64 {
                        parts.append(.object([
                            "type": .string("image_base64"),
                            "media_type": .string(resolvedMimeType),
                            "data": .string(base64)
                        ]))
                    } else if let url = attachment.url {
                        parts.append(.object([
                            "type": .string("image_url"),
                            "image_url": .object([
                                "url": .string(url)
                            ])
                        ]))
                    }
                case .document:
                    if let base64 = attachment.base64 {
                        parts.append(.object([
                            "type": .string("file_base64"),
                            "media_type": .string(resolvedMimeType),
                            "data": .string(base64)
                        ]))
                    } else if let url = attachment.url {
                        var fileUrlDict: [String: AnyCodable] = ["url": .string(url)]
                        fileUrlDict["mime_type"] = .string(resolvedMimeType)

                        parts.append(.object([
                            "type": .string("file_url"),
                            "file_url": .object(fileUrlDict)
                        ]))
                    }
                case .audio:
                    if let base64 = attachment.base64 {
                        parts.append(.object([
                            "type": .string("audio_base64"),
                            "media_type": .string(resolvedMimeType),
                            "data": .string(base64)
                        ]))
                    } else if let url = attachment.url {
                        parts.append(.object([
                            "type": .string("audio_url"),
                            "audio_url": .object([
                                "url": .string(url)
                            ])
                        ]))
                    }
                case .video:
                    if let base64 = attachment.base64 {
                        parts.append(.object([
                            "type": .string("video_base64"),
                            "media_type": .string(resolvedMimeType),
                            "data": .string(base64)
                        ]))
                    } else if let url = attachment.url {
                        parts.append(.object([
                            "type": .string("video_url"),
                            "video_url": .object([
                                "url": .string(url)
                            ])
                        ]))
                    }
                }
            }
            contentPayload = .array(parts)
        }

        // Handle custom provider config
        var openaiCompatibleConfig: OpenAICompatible? = nil
        if config.provider == "openai-compatible", let apiKey = config.customApiKey, let baseUrl = config.customBaseUrl {
            openaiCompatibleConfig = OpenAICompatible(apiKey: apiKey, baseUrl: baseUrl)
        }

        // Determine if gemini tools should be enabled (any Gemini-provider tools in the list)
        let geminiToolIds = ["perform_google_search", "execute_python_code", "query_google_maps"]
        let hasGeminiTools = enabledTools.contains { geminiToolIds.contains($0) }

        let request = OrchestrateRequest(
            conversationId: conversationId,
            content: contentPayload,
            provider: config.provider,
            options: OrchestrateOptions(
                createArtifacts: true,
                saveMemories: true,
                executeTools: false,
                model: config.model,
                geminiTools: hasGeminiTools,  // Backward compatible: true if any Gemini tools enabled
                enabledTools: enabledTools.isEmpty ? nil : enabledTools  // Pass specific tools list
            ),
            anthropic: config.anthropicKey,
            openai: config.openaiKey,
            gemini: config.geminiKey,
            grok: config.grokKey,
            openaiCompatible: openaiCompatibleConfig
        )

        // Log tool configuration for debugging
        if !enabledTools.isEmpty {
            print("[CloudOrchestrator] Sending with enabled tools: \(enabledTools)")
        }

        // Prepare provider API key headers
        var providerHeaders: [String: String] = [:]
        if let key = config.anthropicKey, !key.isEmpty { providerHeaders["X-Anthropic-Api-Key"] = key }
        if let key = config.openaiKey, !key.isEmpty { providerHeaders["X-OpenAI-Api-Key"] = key }
        if let key = config.geminiKey, !key.isEmpty { providerHeaders["X-Gemini-Api-Key"] = key }
        if let key = config.grokKey, !key.isEmpty { providerHeaders["X-Grok-Api-Key"] = key }

        let response: OrchestrateResponse = try await apiClient.request(
            endpoint: "/apiOrchestrate",
            method: .post,
            body: request,
            headers: providerHeaders
        )

        // Add model info if missing (backend might not return it)
        var assistantMessage = response.assistantMessage
        if assistantMessage.modelName == nil || assistantMessage.providerName == nil {
            assistantMessage = Message(
                id: assistantMessage.id,
                conversationId: assistantMessage.conversationId,
                role: assistantMessage.role,
                content: assistantMessage.content,
                timestamp: assistantMessage.timestamp,
                tokens: assistantMessage.tokens,
                artifacts: assistantMessage.artifacts,
                toolCalls: assistantMessage.toolCalls,
                isStreaming: assistantMessage.isStreaming,
                modelName: config.model,
                providerName: config.providerName
            )
        }

        // Notify temporal service of message (session tracking, context saturation)
        // Turn counts are derived from Core Data automatically
        await notifyTemporalService(conversationId: conversationId, contextLimit: config.contextWindowLimit)

        return (assistantMessage, response.memories)
    }

    /// Notify temporal service of message exchange (for session tracking)
    @MainActor
    private func notifyTemporalService(conversationId: String, contextLimit: Int) {
        // Cloud backend doesn't provide precise token counts, use estimate
        let estimatedContextTokens = 0
        TemporalContextService.shared.notifyMessageAdded(
            conversationId: conversationId,
            contextTokens: estimatedContextTokens,
            contextLimit: contextLimit
        )
    }

    func regenerateAssistantMessage(
        conversationId: String,
        messageId: String,
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> Message {
        
        let request = RegenerateRequest(
            provider: config.provider,
            options: .init(
                model: nil, // Use default or previous
                temperature: nil,
                maxTokens: nil,
                includeMemories: true,
                replaceLastMessage: true,
                projectId: defaultProjectId
            ),
            anthropic: config.anthropicKey,
            openai: config.openaiKey,
            gemini: config.geminiKey,
            grok: config.grokKey
        )

        let response: RegenerateResponse = try await apiClient.request(
            endpoint: "/apiRegenerateMessage/\(conversationId)/regenerate",
            method: .post,
            body: request
        )

        return response.assistantMessage
    }
}
