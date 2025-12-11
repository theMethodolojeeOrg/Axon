//
//  OnDeviceConversationOrchestrator.swift
//  Axon
//
//  Implementation of ConversationOrchestrator that calls AI providers directly from the device.
//  Integrates with the Epistemic Engine for grounded, conscious responses.
//

import Foundation

class OnDeviceConversationOrchestrator: ConversationOrchestrator {

    // MARK: - Epistemic Services

    private let predicateLogger = PredicateLogger.shared
    private let salienceService = SalienceService.shared
    private let learningLoopService = LearningLoopService.shared

    // MARK: - State for Learning Loop

    private var lastResponse: String?
    private var lastUsedMemories: [Memory] = []
    private var lastCorrelationId: String?

    func sendMessage(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment],
        enabledTools: [String],
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> (assistantMessage: Message, memories: [Memory]?) {
        // Note: Tools requiring cloud mode (Gemini tools) are not available in on-device mode
        // Only local tools like create_memory can work here
        if !enabledTools.isEmpty {
            print("[OnDeviceOrchestrator] Tools requested: \(enabledTools) (Note: Gemini proxy tools require cloud mode)")
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
        let (systemPrompt, usedMemories) = await buildEpistemicSystemPrompt(
            base: "You are Axon, a helpful AI assistant.",
            messages: mergedMessages,
            userQuery: content,
            correlationId: correlationId
        )

        // Log LLM request predicate
        predicateLogger.logLLMRequest(
            provider: config.provider,
            model: config.model,
            correlationId: correlationId
        )

        var responseContent: String = ""

        switch config.provider {
        case "anthropic":
            guard let apiKey = config.anthropicKey else { throw APIError.unauthorized }
            responseContent = try await callAnthropic(
                apiKey: apiKey,
                model: config.model,
                system: systemPrompt,
                messages: mergedMessages
            )
            
        case "openai":
            guard let apiKey = config.openaiKey else { throw APIError.unauthorized }
            responseContent = try await callOpenAI(
                apiKey: apiKey,
                model: config.model,
                system: systemPrompt,
                messages: mergedMessages
            )
            
        case "gemini":
            guard let apiKey = config.geminiKey else { throw APIError.unauthorized }
            responseContent = try await callGemini(
                apiKey: apiKey,
                model: config.model,
                system: systemPrompt,
                messages: mergedMessages
            )
            
        case "openai-compatible":
             guard let apiKey = config.customApiKey, let baseUrl = config.customBaseUrl else { throw APIError.unauthorized }
             responseContent = try await callOpenAICompatible(
                apiKey: apiKey,
                baseUrl: baseUrl,
                model: config.model,
                system: systemPrompt,
                messages: mergedMessages
             )
            
        default:
            throw APIError.networkError("Provider \(config.provider) not supported in On-Device mode yet.")
        }

        // Log successful LLM response
        predicateLogger.logLLMResponse(
            success: true,
            tokenCount: nil, // Could estimate from response length
            correlationId: correlationId
        )

        // Create Assistant Message
        let assistantMessage = Message(
            conversationId: conversationId,
            role: .assistant,
            content: responseContent,
            modelName: config.model,
            providerName: config.providerName
        )

        // Record prediction for learning loop
        if !usedMemories.isEmpty {
            learningLoopService.recordPrediction(
                content: responseContent,
                confidence: 0.8, // Base confidence when using memories
                basedOnMemories: usedMemories,
                correlationId: correlationId
            )
        }

        // Store for next interaction's learning loop
        lastResponse = responseContent
        lastUsedMemories = usedMemories
        lastCorrelationId = correlationId

        // Memory Extraction (Optional/Future)
        // In on-device mode, we might skip automatic memory extraction for now
        // or implement a second call to do it.

        return (assistantMessage, nil)
    }

    // MARK: - Epistemic Integration

    /// Build a system prompt enhanced with epistemic grounding
    private func buildEpistemicSystemPrompt(
        base: String,
        messages: [Message],
        userQuery: String,
        correlationId: String
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
                correlationId: correlationId
            )

            if !injection.isEmpty {
                promptParts.append(injection.injectionBlock)
                usedMemories = injection.selectedMemories.map { $0.memory }
            }
        }

        let combined = promptParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return (combined.isEmpty ? nil : combined, usedMemories)
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
    private func mergeLatestUserMessage(_ messages: [Message], conversationId: String, content: String, attachments: [MessageAttachment]) -> [Message] {
        guard let last = messages.last else {
            if content.isEmpty && attachments.isEmpty { return messages }
            return messages + [Message(conversationId: conversationId, role: .user, content: content, attachments: attachments)]
        }
        
        var updated = messages
        
        if last.role == .user && last.content == content {
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
            return updated
        }
        
        if !content.isEmpty || !attachments.isEmpty {
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
                if let block = anthropicMediaBlock(type: "image", attachment: attachment) {
                    blocks.append(block)
                }
            case .document:
                if let block = anthropicMediaBlock(type: "document", attachment: attachment) {
                    blocks.append(block)
                }
            default:
                continue
            }
        }
        
        if blocks.isEmpty {
            blocks.append(["type": "text", "text": ""])
        }
        
        return blocks
    }
    
    private func anthropicMediaBlock(type: String, attachment: MessageAttachment) -> [String: Any]? {
        if let base64 = attachment.base64 {
            return [
                "type": type,
                "source": [
                    "type": "base64",
                    "media_type": resolvedMimeType(for: attachment),
                    "data": base64
                ]
            ]
        } else if let url = attachment.url {
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
            guard attachment.type == .image else { continue }
            
            if let base64 = attachment.base64 {
                let mimeType = resolvedMimeType(for: attachment)
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
            if let base64 = attachment.base64 {
                parts.append([
                    "inline_data": [
                        "mime_type": resolvedMimeType(for: attachment),
                        "data": base64
                    ]
                ])
            } else if let url = attachment.url {
                parts.append([
                    "file_data": [
                        "file_uri": url
                    ]
                ])
            }
        }
        
        if parts.isEmpty {
            parts.append(["text": ""])
        }
        
        return parts
    }
    
    private func resolvedMimeType(for attachment: MessageAttachment) -> String {
        if let mime = attachment.mimeType, mime.contains("/") {
            return mime
        }
        
        if let mime = attachment.mimeType?.lowercased() {
            switch mime {
            case "jpg", "jpeg": return "image/jpeg"
            case "png": return "image/png"
            case "gif": return "image/gif"
            case "webp": return "image/webp"
            case "pdf": return "application/pdf"
            case "txt", "text": return "text/plain"
            case "mp3", "mpeg", "mpga": return "audio/mpeg"
            case "wav": return "audio/wav"
            case "aac": return "audio/aac"
            case "flac": return "audio/flac"
            case "ogg": return "audio/ogg"
            case "mp4": return "video/mp4"
            case "mov": return "video/quicktime"
            default: break
            }
        }
        
        if let name = attachment.name?.lowercased() {
            let ext = (name as NSString).pathExtension
            switch ext {
            case "jpg", "jpeg": return "image/jpeg"
            case "png": return "image/png"
            case "gif": return "image/gif"
            case "webp": return "image/webp"
            case "pdf": return "application/pdf"
            case "txt": return "text/plain"
            case "mp3", "mpeg", "mpga": return "audio/mpeg"
            case "wav": return "audio/wav"
            case "aac": return "audio/aac"
            case "flac": return "audio/flac"
            case "ogg": return "audio/ogg"
            case "mp4", "m4v": return "video/mp4"
            case "mov": return "video/quicktime"
            default: break
            }
        }
        
        switch attachment.type {
        case .image: return "image/jpeg"
        case .document: return "application/octet-stream"
        case .audio: return "audio/mpeg"
        case .video: return "video/mp4"
        }
    }
}
