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
        isStreaming: Bool? = nil
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
