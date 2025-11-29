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

    func sendMessage(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment],
        geminiTools: Bool,
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> (assistantMessage: Message, memories: [Memory]?) {
        
        // Construct content payload (String or Array)
        let contentPayload: AnyCodable
        if attachments.isEmpty {
            contentPayload = .string(content)
        } else {
            var parts: [AnyCodable] = []
            
            // Add text part if not empty
            if !content.isEmpty {
                parts.append(.object([
                    "type": .string("text"),
                    "text": .string(content)
                ]))
            }
            
            // Add attachment parts - flattened structure matching backend expectations
            for attachment in attachments {
                switch attachment.type {
                case .image:
                    if let base64 = attachment.base64 {
                        parts.append(.object([
                            "type": .string("image_base64"),
                            "media_type": .string(attachment.mimeType ?? "image/jpeg"),
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
                            "media_type": .string(attachment.mimeType ?? "application/pdf"),
                            "data": .string(base64)
                        ]))
                    } else if let url = attachment.url {
                        var fileUrlDict: [String: AnyCodable] = ["url": .string(url)]
                        if let mimeType = attachment.mimeType {
                            fileUrlDict["mime_type"] = .string(mimeType)
                        }

                        parts.append(.object([
                            "type": .string("file_url"),
                            "file_url": .object(fileUrlDict)
                        ]))
                    }
                case .audio:
                    if let base64 = attachment.base64 {
                        parts.append(.object([
                            "type": .string("audio_base64"),
                            "media_type": .string(attachment.mimeType ?? "audio/mp3"),
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
                            "media_type": .string(attachment.mimeType ?? "video/mp4"),
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

        let request = OrchestrateRequest(
            conversationId: conversationId,
            content: contentPayload,
            provider: config.provider,
            options: OrchestrateOptions(
                createArtifacts: true,
                saveMemories: true,
                executeTools: false,
                model: config.model,
                geminiTools: geminiTools
            ),
            anthropic: config.anthropicKey,
            openai: config.openaiKey,
            gemini: config.geminiKey,
            grok: config.grokKey,
            openaiCompatible: openaiCompatibleConfig
        )

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

        return (assistantMessage, response.memories)
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
