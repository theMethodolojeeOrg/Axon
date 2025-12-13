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
    let attachments: [MessageAttachment]?
    let groundingSources: [MessageGroundingSource]?  // Sources from tool calls (web search, etc.)
    let memoryOperations: [MessageMemoryOperation]?  // Memory operations performed by assistant

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
        case attachments
        case groundingSources
        case memoryOperations
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
        providerName: String? = nil,
        attachments: [MessageAttachment]? = nil,
        groundingSources: [MessageGroundingSource]? = nil,
        memoryOperations: [MessageMemoryOperation]? = nil
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
        self.attachments = attachments
        self.groundingSources = groundingSources
        self.memoryOperations = memoryOperations
    }

    // Custom decoder to handle timestamp conversion from milliseconds
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        // conversationId is optional when messages are nested in listAll responses
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
        role = try container.decode(MessageRole.self, forKey: .role)
        
        // Handle content which can be String or [ContentPart]
        if let contentString = try? container.decode(String.self, forKey: .content) {
            content = contentString
            attachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments)
        } else if let contentParts = try? container.decode([ContentPart].self, forKey: .content) {
            // Extract text parts
            content = contentParts.filter { $0.type == "text" }.compactMap { $0.text }.joined(separator: "\n")
            
            // Extract attachments
            let extractedAttachments = contentParts.compactMap { part -> MessageAttachment? in
                switch part.type {
                case "image_base64":
                    return MessageAttachment(type: .image, base64: part.data, mimeType: part.media_type)
                case "image_url":
                    return MessageAttachment(type: .image, url: part.image_url?.url)
                case "file_url":
                    return MessageAttachment(type: .document, url: part.file_url?.url)
                case "audio_base64":
                    return MessageAttachment(type: .audio, base64: part.data, mimeType: part.media_type)
                case "audio_url":
                    return MessageAttachment(type: .audio, url: part.audio_url?.url)
                case "video_base64":
                    return MessageAttachment(type: .video, base64: part.data, mimeType: part.media_type)
                case "video_url":
                    return MessageAttachment(type: .video, url: part.video_url?.url)
                default:
                    return nil
                }
            }
            
            // Merge with any explicitly provided attachments (though usually it's one or the other)
            let explicitAttachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments) ?? []
            attachments = explicitAttachments + extractedAttachments
        } else {
            content = ""
            attachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments)
        }

        // Handle timestamp (createdAt) as milliseconds
        let timestampMillis = try container.decode(Double.self, forKey: .timestamp)
        timestamp = Date(timeIntervalSince1970: timestampMillis / 1000)

        tokens = try container.decodeIfPresent(TokenUsage.self, forKey: .tokens)
        artifacts = try container.decodeIfPresent([String].self, forKey: .artifacts)
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        groundingSources = try container.decodeIfPresent([MessageGroundingSource].self, forKey: .groundingSources)
        memoryOperations = try container.decodeIfPresent([MessageMemoryOperation].self, forKey: .memoryOperations)
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
        try container.encodeIfPresent(attachments, forKey: .attachments)
        try container.encodeIfPresent(groundingSources, forKey: .groundingSources)
        try container.encodeIfPresent(memoryOperations, forKey: .memoryOperations)
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

struct MessageAttachment: Codable, Equatable, Identifiable {
    let id: String
    let type: AttachmentType
    let url: String?      // For remote URLs
    let base64: String?   // For local uploads
    let name: String?
    let mimeType: String?

    enum AttachmentType: String, Codable {
        case image
        case document
        case audio
        case video
    }

    init(
        id: String = UUID().uuidString,
        type: AttachmentType,
        url: String? = nil,
        base64: String? = nil,
        name: String? = nil,
        mimeType: String? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.base64 = base64
        self.name = name
        self.mimeType = mimeType
    }
}

// MARK: - Memory Operations

/// Represents a memory operation result from the assistant (create, update, etc.)
struct MessageMemoryOperation: Codable, Equatable, Identifiable {
    let id: String
    let operationType: OperationType
    let success: Bool
    let memoryType: String  // "allocentric", "egoic", etc.
    let content: String
    let tags: [String]
    let confidence: Double
    let errorMessage: String?

    enum OperationType: String, Codable {
        case create
        case update
        case delete
    }

    init(
        id: String = UUID().uuidString,
        operationType: OperationType = .create,
        success: Bool,
        memoryType: String,
        content: String,
        tags: [String] = [],
        confidence: Double = 0.8,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.operationType = operationType
        self.success = success
        self.memoryType = memoryType
        self.content = content
        self.tags = tags
        self.confidence = confidence
        self.errorMessage = errorMessage
    }
}

// MARK: - Grounding Sources

/// A source referenced in tool call results (web search, maps, etc.)
struct MessageGroundingSource: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let url: String
    let sourceType: SourceType

    enum SourceType: String, Codable {
        case web
        case maps
    }

    init(id: String = UUID().uuidString, title: String, url: String, sourceType: SourceType = .web) {
        self.id = id
        self.title = title
        self.url = url
        self.sourceType = sourceType
    }

    /// Create from GroundingChunk (from GeminiToolService)
    init(from chunk: GroundingChunk) {
        self.id = chunk.id
        self.title = chunk.title
        self.url = chunk.uri ?? ""
        self.sourceType = chunk.maps != nil ? .maps : .web
    }
}

// Helper struct for decoding multimodal content from backend
private struct ContentPart: Codable {
    let type: String
    let text: String?
    let image_url: ImageUrl?
    let file_url: FileUrl?
    let audio_url: AudioUrl?
    let video_url: VideoUrl?
    let media_type: String?
    let data: String?

    struct ImageUrl: Codable { let url: String }
    struct FileUrl: Codable { let url: String }
    struct AudioUrl: Codable { let url: String }
    struct VideoUrl: Codable { let url: String }
}
