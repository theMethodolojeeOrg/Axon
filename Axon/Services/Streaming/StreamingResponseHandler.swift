//
//  StreamingResponseHandler.swift
//  Axon
//
//  Handles SSE streaming from AI providers, emitting events for UI consumption.
//  Supports Anthropic, OpenAI, Gemini, and OpenAI-compatible providers.
//

import Foundation

// MARK: - Streaming Response Handler

/// Handles streaming responses from AI providers
class StreamingResponseHandler {

    // MARK: - Streaming Configuration

    struct StreamingConfig {
        let provider: String
        let apiKey: String
        let model: String
        let baseUrl: String?
        let system: String?
        let maxTokens: Int
        let modelParams: ModelGenerationSettings?

        init(
            provider: String,
            apiKey: String,
            model: String,
            baseUrl: String? = nil,
            system: String? = nil,
            maxTokens: Int = 4096,
            modelParams: ModelGenerationSettings? = nil
        ) {
            self.provider = provider
            self.apiKey = apiKey
            self.model = model
            self.baseUrl = baseUrl
            self.system = system
            self.maxTokens = maxTokens
            self.modelParams = modelParams
        }
    }

    private func openAIStyleSamplingParameters(
        from modelParams: ModelGenerationSettings?,
        provider: String
    ) -> [String: Any] {
        guard let modelParams else {
            return [:]
        }
        return modelParams.parameters(for: provider)
    }

    private func geminiGenerationConfig(from modelParams: ModelGenerationSettings?) -> [String: Any] {
        guard let modelParams else {
            return [:]
        }
        let raw = modelParams.parameters(for: "gemini")
        var config: [String: Any] = [:]
        if let temperature = raw["temperature"] {
            config["temperature"] = temperature
        }
        if let topP = raw["top_p"] {
            config["topP"] = topP
        }
        if let topK = raw["top_k"] {
            config["topK"] = topK
        }
        return config
    }

    // MARK: - Supported Providers

    /// Check if a provider supports SSE streaming
    static func supportsStreaming(provider: String) -> Bool {
        let streamingProviders = [
            "anthropic",
            "openai",
            "openai-compatible",
            "gemini",
            "deepseek",
            "grok"
        ]
        return streamingProviders.contains(provider.lowercased())
    }

    // MARK: - Stream Response

    /// Stream a response from the provider
    func stream(
        config: StreamingConfig,
        messages: [Message]
    ) -> AsyncThrowingStream<StreamingEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    switch config.provider.lowercased() {
                    case "anthropic":
                        try await streamAnthropic(config: config, messages: messages, continuation: continuation)
                    case "openai":
                        try await streamOpenAI(config: config, messages: messages, continuation: continuation)
                    case "openai-compatible":
                        try await streamOpenAICompatible(config: config, messages: messages, continuation: continuation)
                    case "gemini":
                        try await streamGemini(config: config, messages: messages, continuation: continuation)
                    case "deepseek":
                        try await streamDeepSeek(config: config, messages: messages, continuation: continuation)
                    case "grok":
                        try await streamGrok(config: config, messages: messages, continuation: continuation)
                    default:
                        continuation.yield(.error(.unsupportedProvider(config.provider)))
                    }
                    continuation.finish()
                } catch {
                    if let streamingError = error as? StreamingError {
                        continuation.yield(.error(streamingError))
                    } else {
                        continuation.yield(.error(.connectionFailed(error.localizedDescription)))
                    }
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Anthropic Streaming

    private func streamAnthropic(
        config: StreamingConfig,
        messages: [Message],
        continuation: AsyncThrowingStream<StreamingEvent, Error>.Continuation
    ) async throws {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")

        // Convert messages to Anthropic format
        var apiMessages: [[String: Any]] = []
        for msg in messages where msg.role != .system {
            let role = msg.role == .assistant ? "assistant" : "user"
            let contentBlocks = anthropicContentBlocks(for: msg)
            apiMessages.append(["role": role, "content": contentBlocks])
        }

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "stream": true,
            "messages": apiMessages
        ]

        if let system = config.system, !system.isEmpty {
            body["system"] = system
        }
        body.merge(openAIStyleSamplingParameters(from: config.modelParams, provider: "anthropic")) { _, new in new }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.connectionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            do {
                for try await line in bytes.lines {
                    errorBody += line
                }
            } catch {
                // Ignore error-body parsing failures and preserve status.
            }
            throw StreamingError.providerError(
                httpResponse.statusCode,
                errorBody.isEmpty ? "Anthropic API error" : errorBody
            )
        }

        var accumulatedContent = ""

        for try await line in bytes.lines {
            guard let data = SSEParser.parseDataLine(line) else { continue }

            if let event = SSEParser.parseAnthropicEvent(data) {
                switch event {
                case .contentBlockDelta(_, let text):
                    accumulatedContent += text
                    continuation.yield(.textDelta(text))

                case .messageDelta(let stopReason, let usage):
                    if stopReason != nil {
                        var tokens: TokenUsage? = nil
                        if let u = usage {
                            tokens = TokenUsage(
                                input: u.inputTokens ?? 0,
                                output: u.outputTokens ?? 0,
                                total: (u.inputTokens ?? 0) + (u.outputTokens ?? 0)
                            )
                        }
                        continuation.yield(.completion(StreamingCompletion(
                            fullContent: accumulatedContent,
                            reasoning: nil,
                            toolCalls: [],
                            groundingSources: [],
                            memoryOperations: [],
                            tokens: tokens,
                            modelName: config.model,
                            providerName: "Anthropic"
                        )))
                        return  // Exit the function after completion
                    }

                case .error(let type, let message):
                    throw StreamingError.providerError(0, "\(type): \(message)")

                default:
                    break
                }
            }
        }
    }

    // MARK: - OpenAI Streaming

    private func streamOpenAI(
        config: StreamingConfig,
        messages: [Message],
        continuation: AsyncThrowingStream<StreamingEvent, Error>.Continuation
    ) async throws {
        try await streamOpenAICompatible(
            config: StreamingConfig(
                provider: config.provider,
                apiKey: config.apiKey,
                model: config.model,
                baseUrl: "https://api.openai.com/v1",
                system: config.system,
                maxTokens: config.maxTokens,
                modelParams: config.modelParams
            ),
            messages: messages,
            continuation: continuation
        )
    }

    private func streamOpenAICompatible(
        config: StreamingConfig,
        messages: [Message],
        continuation: AsyncThrowingStream<StreamingEvent, Error>.Continuation
    ) async throws {
        // Normalize base URL - handle various formats users might enter
        var baseUrl = (config.baseUrl ?? "https://api.openai.com/v1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing slashes
        while baseUrl.hasSuffix("/") {
            baseUrl.removeLast()
        }
        
        // Remove common path suffixes that users might accidentally include
        // Order matters - check longest paths first
        let pathsToStrip = [
            "/chat/completions",  // Full OpenAI-compatible endpoint
            "/completions",       // Legacy completions endpoint
        ]
        
        for path in pathsToStrip {
            if baseUrl.lowercased().hasSuffix(path.lowercased()) {
                baseUrl = String(baseUrl.dropLast(path.count))
                break
            }
        }
        
        // Clean up any remaining trailing slashes after stripping paths
        while baseUrl.hasSuffix("/") {
            baseUrl.removeLast()
        }
        
        let fullUrlString = "\(baseUrl)/chat/completions"
        
        // Debug logging for custom provider issues
        print("[StreamingHTTP] OpenAI-compatible request:")
        print("[StreamingHTTP]   Base URL: \(baseUrl)")
        print("[StreamingHTTP]   Full URL: \(fullUrlString)")
        print("[StreamingHTTP]   Model: \(config.model)")
        print("[StreamingHTTP]   API Key present: \(!config.apiKey.isEmpty)")
        if config.apiKey.isEmpty {
            print("[StreamingHTTP]   ⚠️ WARNING: API key is empty!")
        }
        
        guard let url = URL(string: fullUrlString) else {
            print("[StreamingHTTP]   ❌ ERROR: Invalid URL constructed")
            throw StreamingError.connectionFailed("Invalid URL: \(fullUrlString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = []
        if let system = config.system, !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages where msg.role != .system {
            // Grok uses a stricter payload than general OpenAI-compatible providers
            let content: Any
            if config.provider.lowercased() == "grok" {
                content = grokContent(for: msg)
            } else {
                content = openAIContent(for: msg)
            }
            apiMessages.append(["role": msg.role.rawValue, "content": content])
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": apiMessages,
            "stream": true
        ]
        body.merge(openAIStyleSamplingParameters(from: config.modelParams, provider: config.provider)) { _, new in new }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Log request body size for debugging large payloads
        if let bodyData = request.httpBody {
            print("[StreamingHTTP]   Request body size: \(bodyData.count) bytes")
        }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            // Capture the actual network error
            let nsError = error as NSError
            print("[StreamingHTTP] ❌ Network error:")
            print("[StreamingHTTP]   Domain: \(nsError.domain)")
            print("[StreamingHTTP]   Code: \(nsError.code)")
            print("[StreamingHTTP]   Description: \(nsError.localizedDescription)")
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                print("[StreamingHTTP]   Underlying: \(underlyingError)")
            }
            throw StreamingError.connectionFailed("Network error: \(nsError.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[StreamingHTTP] ❌ Invalid response type")
            throw StreamingError.connectionFailed("Invalid response")
        }
        
        print("[StreamingHTTP]   HTTP Status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            // Try to read the error response body
            var errorBody = ""
            do {
                for try await line in bytes.lines {
                    errorBody += line
                }
            } catch {
                // Ignore errors reading the error body
            }
            print("[StreamingHTTP] ❌ Provider error (\(httpResponse.statusCode)): \(errorBody)")
            throw StreamingError.providerError(httpResponse.statusCode, errorBody.isEmpty ? "OpenAI API error" : errorBody)
        }

        var accumulatedContent = ""
        var accumulatedReasoning = ""
        var sawAnyProviderEvent = false
        var sawCompletionSignal = false
        var loggedUnknownPayload = false
        let providerName = providerDisplayName(for: config.provider, baseUrl: baseUrl)

        for try await line in bytes.lines {
            guard let data = SSEParser.parseDataLine(line) else { continue }

            guard let event = SSEParser.parseOpenAIEvent(data) else {
                if !loggedUnknownPayload {
                    loggedUnknownPayload = true
                    print("[StreamingHTTP] ⚠️ Unrecognized stream frame: provider=\(config.provider) model=\(config.model) payload=\(String(data.prefix(240)))")
                }
                continue
            }

            sawAnyProviderEvent = true

            switch event {
            case .delta(let content, _, let finishReason):
                if let content, !content.isEmpty {
                    accumulatedContent += content
                    continuation.yield(.textDelta(content))
                }
                if finishReason != nil {
                    sawCompletionSignal = true
                    continuation.yield(.completion(StreamingCompletion(
                        fullContent: accumulatedContent,
                        reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                        toolCalls: [],
                        groundingSources: [],
                        memoryOperations: [],
                        tokens: nil,
                        modelName: config.model,
                        providerName: providerName
                    )))
                    return
                }

            case .reasoningDelta(let text):
                guard !text.isEmpty else { continue }
                accumulatedReasoning += text
                continuation.yield(.reasoningDelta(text))

            case .completion(_):
                sawCompletionSignal = true
                continuation.yield(.completion(StreamingCompletion(
                    fullContent: accumulatedContent,
                    reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                    toolCalls: [],
                    groundingSources: [],
                    memoryOperations: [],
                    tokens: nil,
                    modelName: config.model,
                    providerName: providerName
                )))
                return

            case .providerError(let type, let message, let code):
                var detail = "\(type): \(message)"
                if let code, !code.isEmpty {
                    detail += " (code: \(code))"
                }
                throw StreamingError.providerError(0, detail)

            case .done:
                sawCompletionSignal = true
                continuation.yield(.completion(StreamingCompletion(
                    fullContent: accumulatedContent,
                    reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                    toolCalls: [],
                    groundingSources: [],
                    memoryOperations: [],
                    tokens: nil,
                    modelName: config.model,
                    providerName: providerName
                )))
                return
            }
        }

        // Some providers end stream without finish_reason or [DONE].
        // Emit deterministic completion when we parsed valid provider events.
        if sawAnyProviderEvent && !sawCompletionSignal {
            continuation.yield(.completion(StreamingCompletion(
                fullContent: accumulatedContent,
                reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                toolCalls: [],
                groundingSources: [],
                memoryOperations: [],
                tokens: nil,
                modelName: config.model,
                providerName: providerName
            )))
        }
    }

    // MARK: - Gemini Streaming

    private func streamGemini(
        config: StreamingConfig,
        messages: [Message],
        continuation: AsyncThrowingStream<StreamingEvent, Error>.Continuation
    ) async throws {
        // Gemini uses streamGenerateContent endpoint
        let baseUrl = "https://generativelanguage.googleapis.com/v1beta"
        let modelId = config.model.starts(with: "models/") ? config.model : "models/\(config.model)"
        let url = URL(string: "\(baseUrl)/\(modelId):streamGenerateContent?key=\(config.apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert messages to Gemini format
        var contents: [[String: Any]] = []
        for msg in messages where msg.role != .system {
            let role = msg.role == .assistant ? "model" : "user"
            contents.append([
                "role": role,
                "parts": geminiParts(for: msg)
            ])
        }

        var body: [String: Any] = ["contents": contents]

        if let system = config.system, !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }

        var generationConfig: [String: Any] = [
            "maxOutputTokens": config.maxTokens
        ]
        generationConfig.merge(geminiGenerationConfig(from: config.modelParams)) { _, new in new }
        body["generationConfig"] = generationConfig

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.connectionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            do {
                for try await line in bytes.lines {
                    errorBody += line
                }
            } catch {
                // Ignore error-body parsing failures and preserve status.
            }
            throw StreamingError.providerError(
                httpResponse.statusCode,
                errorBody.isEmpty ? "Gemini API error" : errorBody
            )
        }

        var accumulatedContent = ""
        var lastTokens: TokenUsage? = nil
        var sawAnyProviderEvent = false
        var sawCompletionSignal = false
        var loggedUnknownPayload = false

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let events = SSEParser.parseGeminiChunk(trimmed)
            if events.isEmpty {
                let looksLikePayload = trimmed.hasPrefix("data:") || trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
                if looksLikePayload && !loggedUnknownPayload {
                    loggedUnknownPayload = true
                    print("[StreamingGemini] ⚠️ Unrecognized stream frame: provider=\(config.provider) model=\(config.model) payload=\(String(trimmed.prefix(240)))")
                }
                continue
            }

            sawAnyProviderEvent = true

            for event in events {
                switch event {
                case .textDelta(let text):
                    accumulatedContent += text
                    continuation.yield(.textDelta(text))

                case .usageMetadata(let promptTokens, let candidatesTokens, let totalTokens):
                    lastTokens = TokenUsage(
                        input: promptTokens,
                        output: candidatesTokens,
                        total: totalTokens
                    )

                case .finishReason(_):
                    sawCompletionSignal = true
                    continuation.yield(.completion(StreamingCompletion(
                        fullContent: accumulatedContent,
                        reasoning: nil,
                        toolCalls: [],
                        groundingSources: [],
                        memoryOperations: [],
                        tokens: lastTokens,
                        modelName: config.model,
                        providerName: "Gemini"
                    )))
                    return

                case .providerError(let code, let status, let message):
                    let statusText = status ?? "UNKNOWN"
                    throw StreamingError.providerError(code ?? 0, "[\(statusText)] \(message)")

                case .done:
                    sawCompletionSignal = true
                    continuation.yield(.completion(StreamingCompletion(
                        fullContent: accumulatedContent,
                        reasoning: nil,
                        toolCalls: [],
                        groundingSources: [],
                        memoryOperations: [],
                        tokens: lastTokens,
                        modelName: config.model,
                        providerName: "Gemini"
                    )))
                    return

                default:
                    break
                }
            }
        }

        if sawAnyProviderEvent && !sawCompletionSignal {
            continuation.yield(.completion(StreamingCompletion(
                fullContent: accumulatedContent,
                reasoning: nil,
                toolCalls: [],
                groundingSources: [],
                memoryOperations: [],
                tokens: lastTokens,
                modelName: config.model,
                providerName: "Gemini"
            )))
        }
    }

    // MARK: - DeepSeek Streaming (with reasoning)

    private func streamDeepSeek(
        config: StreamingConfig,
        messages: [Message],
        continuation: AsyncThrowingStream<StreamingEvent, Error>.Continuation
    ) async throws {
        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: Any]] = []
        if let system = config.system, !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages where msg.role != .system {
            apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": apiMessages,
            "stream": true
        ]
        body.merge(openAIStyleSamplingParameters(from: config.modelParams, provider: "deepseek")) { _, new in new }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.connectionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            var errorBody = ""
            do {
                for try await line in bytes.lines {
                    errorBody += line
                }
            } catch {
                // Ignore error-body parsing failures and preserve status.
            }
            throw StreamingError.providerError(
                httpResponse.statusCode,
                errorBody.isEmpty ? "DeepSeek API error" : errorBody
            )
        }

        var accumulatedContent = ""
        var accumulatedReasoning = ""

        for try await line in bytes.lines {
            guard let data = SSEParser.parseDataLine(line) else { continue }

            if let event = SSEParser.parseReasoningModelEvent(data) {
                switch event {
                case .reasoningDelta(let text):
                    accumulatedReasoning += text
                    continuation.yield(.reasoningDelta(text))

                case .contentDelta(let text):
                    accumulatedContent += text
                    continuation.yield(.textDelta(text))

                case .done:
                    continuation.yield(.completion(StreamingCompletion(
                        fullContent: accumulatedContent,
                        reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                        toolCalls: [],
                        groundingSources: [],
                        memoryOperations: [],
                        tokens: nil,
                        modelName: config.model,
                        providerName: "DeepSeek"
                    )))
                    return  // Exit the function when [DONE] signal received
                }
            }
        }
    }

    // MARK: - Grok Streaming

    private func streamGrok(
        config: StreamingConfig,
        messages: [Message],
        continuation: AsyncThrowingStream<StreamingEvent, Error>.Continuation
    ) async throws {
        // Grok uses OpenAI-compatible API
        try await streamOpenAICompatible(
            config: StreamingConfig(
                provider: config.provider,
                apiKey: config.apiKey,
                model: config.model,
                baseUrl: "https://api.x.ai/v1",
                system: config.system,
                maxTokens: config.maxTokens,
                modelParams: config.modelParams
            ),
            messages: messages,
            continuation: continuation
        )
    }

    // MARK: - Attachment Formatting

    private func providerDisplayName(for provider: String, baseUrl: String?) -> String {
        let normalized = provider.lowercased()
        if normalized == "grok" { return "Grok" }
        if normalized == "openai" { return "OpenAI" }
        if normalized == "openai-compatible" {
            if let baseUrl, baseUrl.lowercased().contains("x.ai") {
                return "Grok"
            }
            return "OpenAI-Compatible"
        }
        return provider
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
            case .audio, .video:
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
            return [
                "type": type,
                "source": [
                    "type": "base64",
                    "media_type": mimeType,
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
            let mimeType = resolvedMimeType(for: attachment)

            switch attachment.type {
            case .image:
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
                if let base64 = attachment.base64 {
                    let format = mimeType.components(separatedBy: "/").last ?? "wav"
                    parts.append([
                        "type": "input_audio",
                        "input_audio": [
                            "data": base64,
                            "format": format
                        ]
                    ])
                }

            case .document, .video:
                continue
            }
        }

        if parts.isEmpty {
            return message.content
        }

        return parts
    }

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

        for attachment in attachments where attachment.type == .image {
            let mimeType = resolvedMimeType(for: attachment)

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
                parts.append([
                    "inline_data": [
                        "mime_type": mimeType,
                        "data": base64
                    ]
                ])
            } else if let url = attachment.url {
                var fileData: [String: Any] = ["file_uri": url]
                fileData["mime_type"] = mimeType
                parts.append(["file_data": fileData])
            }
        }

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return parts
    }

    private func resolvedMimeType(for attachment: MessageAttachment) -> String {
        AttachmentMimePolicyService.resolveMimeType(for: attachment)
    }
}

// MARK: - Non-Streaming Fallback

extension StreamingResponseHandler {

    /// Wrap a non-streaming response in streaming events for consistent UI handling
    static func wrapNonStreamingResponse(
        content: String,
        reasoning: String? = nil,
        tokens: TokenUsage? = nil,
        modelName: String? = nil,
        providerName: String? = nil
    ) -> AsyncThrowingStream<StreamingEvent, Error> {
        AsyncThrowingStream { continuation in
            // Emit the full content as a single delta
            continuation.yield(.textDelta(content))

            // Emit reasoning if present
            if let reasoning = reasoning, !reasoning.isEmpty {
                continuation.yield(.reasoningDelta(reasoning))
            }

            // Emit completion
            continuation.yield(.completion(StreamingCompletion(
                fullContent: content,
                reasoning: reasoning,
                toolCalls: [],
                groundingSources: [],
                memoryOperations: [],
                tokens: tokens,
                modelName: modelName,
                providerName: providerName
            )))

            continuation.finish()
        }
    }
}
