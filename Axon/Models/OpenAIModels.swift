//
//  OpenAIModels.swift
//  Axon
//
//  OpenAI-compatible API request/response models
//

import Foundation

// MARK: - Chat Completion Request

struct ChatCompletionRequest: Codable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let maxTokens: Int?
    let topP: Double?
    let stream: Bool?
    let stop: [String]?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let user: String?

    // Custom Axon parameters
    let disableMemories: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case stream
        case stop
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case user
        case disableMemories = "disable_memories"
    }
}

struct ChatMessage: Codable, Sendable {
    let role: String  // "system", "user", "assistant", "developer"
    let content: String
    let name: String?
}

// MARK: - Chat Completion Response

struct ChatCompletionResponse: Codable, Sendable {
    let id: String
    let object: String = "chat.completion"
    let created: Int
    let model: String
    let choices: [ChatChoice]
    let usage: Usage
    let systemFingerprint: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case model
        case choices
        case usage
        case systemFingerprint = "system_fingerprint"
    }
}

struct ChatChoice: Codable, Sendable {
    let index: Int
    let message: ChatMessage
    let finishReason: String

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

struct Usage: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Error Response

struct OpenAIErrorResponse: Codable, Sendable {
    let error: OpenAIError
}

struct OpenAIError: Codable, Sendable {
    let message: String
    let type: String
    let code: String?
}

// MARK: - Helper Extensions

extension ChatMessage {
    /// Convert to Axon MessageRole
    var axonRole: MessageRole {
        switch role.lowercased() {
        case "system", "developer":
            return .system
        case "assistant":
            return .assistant
        default:
            return .user
        }
    }

    /// Create from Axon Message
    init(from message: Message) {
        self.role = message.role.rawValue
        self.content = message.content
        self.name = nil
    }
}

extension ChatCompletionResponse {
    /// Create successful response from Axon conversation
    nonisolated static func from(
        conversationId: String,
        messages: [Message],
        assistantMessage: Message,
        model: String,
        usage: TokenUsage?
    ) -> ChatCompletionResponse {
        let chatMessage = ChatMessage(from: assistantMessage)

        return ChatCompletionResponse(
            id: "chatcmpl-\(conversationId)",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [
                ChatChoice(
                    index: 0,
                    message: chatMessage,
                    finishReason: "stop"
                )
            ],
            usage: Usage(
                promptTokens: usage?.input ?? 0,
                completionTokens: usage?.output ?? 0,
                totalTokens: usage?.total ?? 0
            ),
            systemFingerprint: nil
        )
    }
}

extension OpenAIErrorResponse {
    /// Create error response from error message
    nonisolated static func from(message: String, type: String = "invalid_request_error", code: String? = nil) -> OpenAIErrorResponse {
        return OpenAIErrorResponse(
            error: OpenAIError(
                message: message,
                type: type,
                code: code
            )
        )
    }
}
