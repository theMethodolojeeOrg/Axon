//
//  Message.swift
//  Axon
//
//  Message model for chat conversations
//

import Foundation

struct Message: Codable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    let tokens: TokenUsage?
    let artifacts: [String]?
    let toolCalls: [ToolCall]?
    let isStreaming: Bool?
    let modelName: String?  // For display purposes (e.g., "GPT-4", "Claude Sonnet 4.5")
    let providerName: String?  // For display purposes (e.g., "OpenAI", "Anthropic")

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case role
        case content
        case timestamp = "createdAt"
        case tokens
        case artifacts
        case toolCalls
        case isStreaming
        case modelName
        case providerName
    }

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        tokens: TokenUsage? = nil,
        artifacts: [String]? = nil,
        toolCalls: [ToolCall]? = nil,
        isStreaming: Bool? = nil,
        modelName: String? = nil,
        providerName: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tokens = tokens
        self.artifacts = artifacts
        self.toolCalls = toolCalls
        self.isStreaming = isStreaming
        self.modelName = modelName
        self.providerName = providerName
    }

    // Custom decoder to handle timestamp conversion from milliseconds
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        // conversationId is optional when messages are nested in listAll responses
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)

        // Handle timestamp (createdAt) as milliseconds
        let timestampMillis = try container.decode(Double.self, forKey: .timestamp)
        timestamp = Date(timeIntervalSince1970: timestampMillis / 1000)

        tokens = try container.decodeIfPresent(TokenUsage.self, forKey: .tokens)
        artifacts = try container.decodeIfPresent([String].self, forKey: .artifacts)
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
    }

    // Custom encoder to convert timestamp back to milliseconds
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)

        // Convert timestamp to milliseconds
        try container.encode(timestamp.timeIntervalSince1970 * 1000, forKey: .timestamp)

        try container.encodeIfPresent(tokens, forKey: .tokens)
        try container.encodeIfPresent(artifacts, forKey: .artifacts)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(isStreaming, forKey: .isStreaming)
        try container.encodeIfPresent(modelName, forKey: .modelName)
        try container.encodeIfPresent(providerName, forKey: .providerName)
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct TokenUsage: Codable, Equatable {
    let input: Int
    let output: Int
    let total: Int
}

struct ToolCall: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let arguments: [String: AnyCodable]?
    let result: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case arguments
        case result
    }
}
