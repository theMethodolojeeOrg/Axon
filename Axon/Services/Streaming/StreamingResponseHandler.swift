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

        init(
            provider: String,
            apiKey: String,
            model: String,
            baseUrl: String? = nil,
            system: String? = nil,
            maxTokens: Int = 4096
        ) {
            self.provider = provider
            self.apiKey = apiKey
            self.model = model
            self.baseUrl = baseUrl
            self.system = system
            self.maxTokens = maxTokens
        }
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
                    continuation.finish(throwing: error)
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
            apiMessages.append(["role": role, "content": msg.content])
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

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.connectionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw StreamingError.providerError(httpResponse.statusCode, "Anthropic API error")
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
                    if let _ = stopReason {
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
                maxTokens: config.maxTokens
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
        let baseUrl = config.baseUrl ?? "https://api.openai.com/v1"
        let url = URL(string: "\(baseUrl)/chat/completions")!
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

        let body: [String: Any] = [
            "model": config.model,
            "messages": apiMessages,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.connectionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw StreamingError.providerError(httpResponse.statusCode, "OpenAI API error")
        }

        var accumulatedContent = ""

        for try await line in bytes.lines {
            guard let data = SSEParser.parseDataLine(line) else { continue }

            if let event = SSEParser.parseOpenAIEvent(data) {
                switch event {
                case .delta(let content, _, let finishReason):
                    if let content = content {
                        accumulatedContent += content
                        continuation.yield(.textDelta(content))
                    }
                    if let _ = finishReason {
                        continuation.yield(.completion(StreamingCompletion(
                            fullContent: accumulatedContent,
                            reasoning: nil,
                            toolCalls: [],
                            groundingSources: [],
                            memoryOperations: [],
                            tokens: nil,
                            modelName: config.model,
                            providerName: "OpenAI"
                        )))
                    }
                case .done:
                    break
                }
            }
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
        let url = URL(string: "\(baseUrl)/models/\(config.model):streamGenerateContent?key=\(config.apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert messages to Gemini format
        var contents: [[String: Any]] = []
        for msg in messages where msg.role != .system {
            let role = msg.role == .assistant ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }

        var body: [String: Any] = ["contents": contents]

        if let system = config.system, !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }

        body["generationConfig"] = [
            "maxOutputTokens": config.maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.connectionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw StreamingError.providerError(httpResponse.statusCode, "Gemini API error")
        }

        var accumulatedContent = ""
        var lastTokens: TokenUsage? = nil
        let lineBuffer = SSELineBuffer()

        // Gemini returns newline-delimited JSON chunks
        for try await chunk in bytes {
            let lines = await lineBuffer.append(Data([chunk]))
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let events = SSEParser.parseGeminiChunk(trimmed)
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

                    default:
                        break
                    }
                }
            }
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

        let body: [String: Any] = [
            "model": config.model,
            "messages": apiMessages,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingError.connectionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw StreamingError.providerError(httpResponse.statusCode, "DeepSeek API error")
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
                maxTokens: config.maxTokens
            ),
            messages: messages,
            continuation: continuation
        )
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
