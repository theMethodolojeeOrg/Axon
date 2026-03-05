//
//  SSEParser.swift
//  Axon
//
//  Server-Sent Events (SSE) parsing utilities for streaming AI provider responses.
//  Handles Anthropic, OpenAI, and Gemini streaming formats.
//

import Foundation

// MARK: - SSE Parser

/// Utility for parsing Server-Sent Events from AI providers
struct SSEParser {

    // MARK: - Generic SSE Parsing

    /// Parse an SSE data line, returning the JSON data if valid
    static func parseDataLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }

        let data = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)

        // Check for stream termination signals
        if data == "[DONE]" || data.isEmpty { return nil }

        return data
    }

    /// Parse event type from SSE event line
    static func parseEventLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("event:") else { return nil }
        return String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Anthropic SSE Events

enum AnthropicSSEEvent: Sendable {
    case messageStart(messageId: String, model: String)
    case contentBlockStart(index: Int, type: String)
    case contentBlockDelta(index: Int, text: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?, usage: AnthropicUsage?)
    case messageStop
    case ping
    case error(type: String, message: String)

    struct AnthropicUsage: Sendable {
        let inputTokens: Int?
        let outputTokens: Int?
    }
}

extension SSEParser {

    /// Parse Anthropic SSE event from JSON data
    static func parseAnthropicEvent(_ data: String) -> AnthropicSSEEvent? {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "message_start":
            if let message = json["message"] as? [String: Any],
               let messageId = message["id"] as? String,
               let model = message["model"] as? String {
                return .messageStart(messageId: messageId, model: model)
            }

        case "content_block_start":
            if let index = json["index"] as? Int,
               let contentBlock = json["content_block"] as? [String: Any],
               let blockType = contentBlock["type"] as? String {
                return .contentBlockStart(index: index, type: blockType)
            }

        case "content_block_delta":
            if let index = json["index"] as? Int,
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return .contentBlockDelta(index: index, text: text)
            }

        case "content_block_stop":
            if let index = json["index"] as? Int {
                return .contentBlockStop(index: index)
            }

        case "message_delta":
            let delta = json["delta"] as? [String: Any]
            let stopReason = delta?["stop_reason"] as? String
            var usage: AnthropicSSEEvent.AnthropicUsage?
            if let usageDict = json["usage"] as? [String: Any] {
                usage = AnthropicSSEEvent.AnthropicUsage(
                    inputTokens: usageDict["input_tokens"] as? Int,
                    outputTokens: usageDict["output_tokens"] as? Int
                )
            }
            return .messageDelta(stopReason: stopReason, usage: usage)

        case "message_stop":
            return .messageStop

        case "ping":
            return .ping

        case "error":
            let errorDict = json["error"] as? [String: Any]
            let errorType = errorDict?["type"] as? String ?? "unknown"
            let errorMessage = errorDict?["message"] as? String ?? "Unknown error"
            return .error(type: errorType, message: errorMessage)

        default:
            break
        }

        return nil
    }
}

// MARK: - OpenAI SSE Events

enum OpenAISSEEvent: Sendable {
    case delta(content: String?, role: String?, finishReason: String?)
    case done

    struct Choice: Sendable {
        let index: Int
        let delta: Delta
        let finishReason: String?

        struct Delta: Sendable {
            let content: String?
            let role: String?
        }
    }
}

extension SSEParser {

    /// Parse OpenAI SSE event from JSON data
    static func parseOpenAIEvent(_ data: String) -> OpenAISSEEvent? {
        // Check for done signal
        if data == "[DONE]" {
            return .done
        }

        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        let delta = firstChoice["delta"] as? [String: Any]
        let content = delta?["content"] as? String
        let role = delta?["role"] as? String
        let finishReason = firstChoice["finish_reason"] as? String

        return .delta(content: content, role: role, finishReason: finishReason)
    }
}

// MARK: - Gemini Streaming Events

enum GeminiStreamEvent: Sendable {
    case textDelta(String)
    case functionCall(name: String, args: [String: Any])
    case finishReason(String)
    case safetyRating(category: String, probability: String)
    case usageMetadata(promptTokens: Int, candidatesTokens: Int, totalTokens: Int)
}

extension SSEParser {

    /// Parse Gemini streaming response chunk
    /// Gemini uses chunked JSON, not SSE format
    static func parseGeminiChunk(_ data: String) -> [GeminiStreamEvent] {
        var events: [GeminiStreamEvent] = []

        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return events
        }

        // Parse candidates array
        if let candidates = json["candidates"] as? [[String: Any]] {
            for candidate in candidates {
                // Parse content parts
                if let content = candidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]] {
                    for part in parts {
                        // Text content
                        if let text = part["text"] as? String {
                            events.append(.textDelta(text))
                        }

                        // Function call
                        if let functionCall = part["functionCall"] as? [String: Any],
                           let name = functionCall["name"] as? String,
                           let args = functionCall["args"] as? [String: Any] {
                            events.append(.functionCall(name: name, args: args))
                        }
                    }
                }

                // Parse finish reason
                if let finishReason = candidate["finishReason"] as? String {
                    events.append(.finishReason(finishReason))
                }

                // Parse safety ratings
                if let safetyRatings = candidate["safetyRatings"] as? [[String: Any]] {
                    for rating in safetyRatings {
                        if let category = rating["category"] as? String,
                           let probability = rating["probability"] as? String {
                            events.append(.safetyRating(category: category, probability: probability))
                        }
                    }
                }
            }
        }

        // Parse usage metadata
        if let usageMetadata = json["usageMetadata"] as? [String: Any],
           let promptTokens = usageMetadata["promptTokenCount"] as? Int,
           let candidatesTokens = usageMetadata["candidatesTokenCount"] as? Int,
           let totalTokens = usageMetadata["totalTokenCount"] as? Int {
            events.append(.usageMetadata(
                promptTokens: promptTokens,
                candidatesTokens: candidatesTokens,
                totalTokens: totalTokens
            ))
        }

        return events
    }
}

// MARK: - DeepSeek/Reasoning Model Events

enum ReasoningModelEvent: Sendable {
    case reasoningDelta(String)
    case contentDelta(String)
    case done
}

extension SSEParser {

    /// Parse DeepSeek/reasoning model SSE events
    /// DeepSeek uses OpenAI-compatible format with reasoning_content field
    static func parseReasoningModelEvent(_ data: String) -> ReasoningModelEvent? {
        if data == "[DONE]" {
            return .done
        }

        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any] else {
            return nil
        }

        // Check for reasoning content (DeepSeek R1 specific)
        if let reasoningContent = delta["reasoning_content"] as? String, !reasoningContent.isEmpty {
            return .reasoningDelta(reasoningContent)
        }

        // Regular content
        if let content = delta["content"] as? String, !content.isEmpty {
            return .contentDelta(content)
        }

        return nil
    }
}

// MARK: - Line Buffer for Streaming

/// Buffer for accumulating SSE lines from byte streams
actor SSELineBuffer {
    private var buffer: String = ""

    /// Append data to buffer and return complete lines
    func append(_ data: Data) -> [String] {
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        buffer += string

        var lines: [String] = []
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            lines.append(line)
            buffer = String(buffer[range.upperBound...])
        }

        return lines
    }

    /// Get any remaining content in buffer
    func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let remaining = buffer
        buffer = ""
        return remaining
    }
}
