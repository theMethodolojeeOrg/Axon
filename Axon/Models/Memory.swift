//
//  Memory.swift
//  Axon
//
//  Memory model for the intelligent memory system
//

import Foundation

struct Memory: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let content: String
    let type: MemoryType
    let confidence: Double
    let tags: [String]
    let metadata: [String: AnyCodable]
    let source: MemorySource?
    let relatedMemories: [String]?
    let createdAt: Date
    let updatedAt: Date
    let lastAccessedAt: Date?
    let accessCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case content
        case type
        case confidence
        case tags
        case metadata
        case source
        case relatedMemories
        case createdAt
        case updatedAt
        case lastAccessedAt
        case accessCount
    }

    init(
        id: String = UUID().uuidString,
        userId: String,
        content: String,
        type: MemoryType,
        confidence: Double,
        tags: [String] = [],
        metadata: [String: AnyCodable] = [:],
        source: MemorySource? = nil,
        relatedMemories: [String]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAccessedAt: Date? = nil,
        accessCount: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.content = content
        self.type = type
        self.confidence = confidence
        self.tags = tags
        self.metadata = metadata
        self.source = source
        self.relatedMemories = relatedMemories
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
    }
}

enum MemoryType: String, Codable, CaseIterable {
    case fact = "fact"
    case procedure = "procedure"
    case context = "context"
    case relationship = "relationship"

    var displayName: String {
        switch self {
        case .fact: return "Fact"
        case .procedure: return "Procedure"
        case .context: return "Context"
        case .relationship: return "Relationship"
        }
    }

    var icon: String {
        switch self {
        case .fact: return "lightbulb.fill"
        case .procedure: return "list.bullet"
        case .context: return "bubble.left.and.bubble.right.fill"
        case .relationship: return "link"
        }
    }
}

struct MemorySource: Codable, Equatable {
    let conversationId: String?
    let messageId: String?
    let timestamp: Date

    init(conversationId: String? = nil, messageId: String? = nil, timestamp: Date = Date()) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.timestamp = timestamp
    }
}

struct MemoryListResponse: Codable {
    let memories: [Memory]
    let total: Int
    let hasMore: Bool
}

struct MemorySearchRequest: Codable {
    let query: String
    let types: [MemoryType]?
    let limit: Int
    let minConfidence: Double?

    init(query: String, types: [MemoryType]? = nil, limit: Int = 10, minConfidence: Double? = nil) {
        self.query = query
        self.types = types
        self.limit = limit
        self.minConfidence = minConfidence
    }
}
