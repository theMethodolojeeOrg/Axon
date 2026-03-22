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
    /// If set, the UI should hide the assistant message body behind a banner.
    /// The full text should still be available via the Select Text sheet.
    let hiddenReason: String?
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
    let reasoning: String?  // Chain-of-thought / thinking tokens from reasoning models
    let editHistory: [MessageEdit]?  // Version history for edited messages
    let currentVersion: Int?  // Which version is currently displayed (0 = original)
    let contextDebugInfo: ContextDebugInfo?  // Token usage breakdown for this message
    let liveToolCalls: [LiveToolCall]?  // Rich tool call details with state/timing/request/result
    let isDeleted: Bool?  // Soft-delete flag (if true, show placeholder instead of content)

    // Computed property to check if message has been edited
    var isEdited: Bool {
        return editHistory != nil && !(editHistory?.isEmpty ?? true)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case role
        case content
        case hiddenReason
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
        case reasoning
        case editHistory
        case currentVersion
        case contextDebugInfo
        case liveToolCalls
        case isDeleted
    }

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        role: MessageRole,
        content: String,
        hiddenReason: String? = nil,
        timestamp: Date = Date(),
        tokens: TokenUsage? = nil,
        artifacts: [String]? = nil,
        toolCalls: [ToolCall]? = nil,
        isStreaming: Bool? = nil,
        modelName: String? = nil,
        providerName: String? = nil,
        attachments: [MessageAttachment]? = nil,
        groundingSources: [MessageGroundingSource]? = nil,
        memoryOperations: [MessageMemoryOperation]? = nil,
        reasoning: String? = nil,
        editHistory: [MessageEdit]? = nil,
        currentVersion: Int? = nil,
        contextDebugInfo: ContextDebugInfo? = nil,
        liveToolCalls: [LiveToolCall]? = nil,
        isDeleted: Bool? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.hiddenReason = hiddenReason
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
        self.reasoning = reasoning
        self.editHistory = editHistory
        self.currentVersion = currentVersion
        self.contextDebugInfo = contextDebugInfo
        self.liveToolCalls = liveToolCalls
        self.isDeleted = isDeleted
    }

    // Custom decoder to handle timestamp conversion from milliseconds
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        // conversationId is optional when messages are nested in listAll responses
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
        role = try container.decode(MessageRole.self, forKey: .role)
        hiddenReason = try container.decodeIfPresent(String.self, forKey: .hiddenReason)

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
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
        editHistory = try container.decodeIfPresent([MessageEdit].self, forKey: .editHistory)
        currentVersion = try container.decodeIfPresent(Int.self, forKey: .currentVersion)
        contextDebugInfo = try container.decodeIfPresent(ContextDebugInfo.self, forKey: .contextDebugInfo)
        liveToolCalls = try container.decodeIfPresent([LiveToolCall].self, forKey: .liveToolCalls)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted)
    }

    // Custom encoder to convert timestamp back to milliseconds
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(hiddenReason, forKey: .hiddenReason)

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
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(editHistory, forKey: .editHistory)
        try container.encodeIfPresent(currentVersion, forKey: .currentVersion)
        try container.encodeIfPresent(contextDebugInfo, forKey: .contextDebugInfo)
        try container.encodeIfPresent(liveToolCalls, forKey: .liveToolCalls)
        try container.encodeIfPresent(isDeleted, forKey: .isDeleted)
    }
}

// MARK: - Message Edit History

/// Represents a single edit/version of a message
struct MessageEdit: Codable, Equatable, Identifiable {
    let id: String
    let content: String
    let timestamp: Date
    let version: Int  // 0 = original, 1 = first edit, etc.

    init(
        id: String = UUID().uuidString,
        content: String,
        timestamp: Date = Date(),
        version: Int
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.version = version
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
    let success: Bool?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case arguments
        case result
        case success
        case errorMessage
    }

    init(
        id: String,
        name: String,
        arguments: [String: AnyCodable]? = nil,
        result: String? = nil,
        success: Bool? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.result = result
        self.success = success
        self.errorMessage = errorMessage
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

// MARK: - AttachmentType UI Helpers

extension MessageAttachment.AttachmentType {
    /// SF Symbol name for this attachment type.
    var iconName: String {
        switch self {
        case .image: return "photo.fill"
        case .document: return "doc.fill"
        case .video: return "video.fill"
        case .audio: return "waveform"
        }
    }
}

// MARK: - URL Attachment Helpers

extension URL {
    /// Returns the MIME type based on file extension.
    var mimeType: String {
        let ext = pathExtension.lowercased()
        switch ext {
        // Documents
        case "pdf": return "application/pdf"
        case "txt", "text": return "text/plain"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "doc", "docx": return "application/msword"
        case "xls", "xlsx": return "application/vnd.ms-excel"
        case "ppt", "pptx": return "application/vnd.ms-powerpoint"

        // Images
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"

        // Video formats
        case "mp4", "m4v": return "video/mp4"
        case "mpeg", "mpg": return "video/mpeg"
        case "mov": return "video/mov"
        case "avi": return "video/avi"
        case "flv": return "video/x-flv"
        case "webm": return "video/webm"
        case "wmv": return "video/wmv"
        case "3gp", "3gpp": return "video/3gpp"

        // Audio formats
        case "wav": return "audio/wav"
        case "mp3": return "audio/mp3"
        case "aiff", "aif": return "audio/aiff"
        case "aac", "m4a": return "audio/aac"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"

        default: return "application/octet-stream"
        }
    }

    /// Infers the attachment type based on file extension.
    var attachmentType: MessageAttachment.AttachmentType {
        let ext = pathExtension.lowercased()

        // Video extensions
        if ["mp4", "m4v", "mpeg", "mpg", "mov", "avi", "flv", "webm", "wmv", "3gp", "3gpp"].contains(ext) {
            return .video
        }

        // Audio extensions
        if ["wav", "mp3", "aiff", "aif", "aac", "m4a", "ogg", "flac"].contains(ext) {
            return .audio
        }

        // Image extensions
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"].contains(ext) {
            return .image
        }

        // Default to document
        return .document
    }
}
