//
//  CreativeItem.swift
//  Axon
//
//  Model representing a creative item in the Create gallery.
//  Aggregates AI-generated images, audio, video, and code artifacts.
//

import Foundation

// MARK: - Creative Item Type

enum CreativeItemType: String, Codable, CaseIterable, Identifiable {
    case photo
    case video
    case audio
    case artifact  // Explicitly marked code artifacts
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .photo: return "Photos"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .artifact: return "Artifacts"
        }
    }
    
    var icon: String {
        switch self {
        case .photo: return "photo.fill"
        case .video: return "video.fill"
        case .audio: return "waveform"
        case .artifact: return "chevron.left.forwardslash.chevron.right"
        }
    }
    
    var emptyStateMessage: String {
        switch self {
        case .photo: return "No images generated yet"
        case .video: return "No videos generated yet"
        case .audio: return "No audio generated yet"
        case .artifact: return "No artifacts created yet"
        }
    }
    
    /// Whether this type is currently available (not coming soon)
    var isAvailable: Bool {
        switch self {
        case .photo, .audio, .artifact, .video: return true
        }
    }
}

// MARK: - Creative Item

/// A creative item generated or created within conversations
struct CreativeItem: Identifiable, Codable, Equatable {
    let id: String
    let type: CreativeItemType
    let conversationId: String
    let messageId: String
    let createdAt: Date
    
    // Content
    let contentURL: String?      // Remote URL or file:// for local
    let contentBase64: String?   // For inline images/audio
    let mimeType: String?
    
    // Metadata
    var title: String?           // For artifacts: filename or title (mutable for user editing)
    let prompt: String?          // Generation prompt if available
    let language: String?        // For code artifacts: programming language
    let fileSize: Int64?         // In bytes, if known
    
    // Thumbnail (for gallery display)
    let thumbnailBase64: String? // Smaller preview image
    
    // Deletion tracking
    var isDeleted: Bool = false
    var deletedAt: Date?
    
    init(
        id: String = UUID().uuidString,
        type: CreativeItemType,
        conversationId: String,
        messageId: String,
        createdAt: Date = Date(),
        contentURL: String? = nil,
        contentBase64: String? = nil,
        mimeType: String? = nil,
        title: String? = nil,
        prompt: String? = nil,
        language: String? = nil,
        fileSize: Int64? = nil,
        thumbnailBase64: String? = nil,
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.conversationId = conversationId
        self.messageId = messageId
        self.createdAt = createdAt
        self.contentURL = contentURL
        self.contentBase64 = contentBase64
        self.mimeType = mimeType
        self.title = title
        self.prompt = prompt
        self.language = language
        self.fileSize = fileSize
        self.thumbnailBase64 = thumbnailBase64
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }
    
    // MARK: - Computed Properties
    
    /// Best available content source
    var hasContent: Bool {
        contentURL != nil || contentBase64 != nil
    }
    
    /// Display title for the item
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        
        switch type {
        case .photo:
            return "Generated Image"
        case .video:
            return "Generated Video"
        case .audio:
            return "Generated Audio"
        case .artifact:
            if let language = language {
                return "\(language.capitalized) Code"
            }
            return "Code Artifact"
        }
    }
    
    /// File extension based on mimeType or type
    var fileExtension: String {
        if let mimeType = mimeType {
            // Extract extension from mime type
            let parts = mimeType.split(separator: "/")
            if parts.count == 2 {
                let format = String(parts[1])
                switch format {
                case "jpeg", "jpg": return "jpg"
                case "png": return "png"
                case "gif": return "gif"
                case "webp": return "webp"
                case "mp4": return "mp4"
                case "webm": return "webm"
                case "mpeg": return "mp3"
                case "wav": return "wav"
                case "aac": return "aac"
                default: return format
                }
            }
        }
        
        // Fallback based on type
        switch type {
        case .photo: return "png"
        case .video: return "mp4"
        case .audio: return "mp3"
        case .artifact: return language ?? "txt"
        }
    }
}

// MARK: - Gallery Filter

enum GalleryFilter: Equatable, Identifiable {
    case all
    case type(CreativeItemType)
    
    var id: String {
        switch self {
        case .all: return "all"
        case .type(let type): return type.rawValue
        }
    }
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .type(let type): return type.displayName
        }
    }
}
