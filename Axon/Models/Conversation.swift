//
//  Conversation.swift
//  Axon
//
//  Conversation/Thread model
//

import Foundation

struct Conversation: Codable, Identifiable, Equatable {
    let id: String
    let userId: String?  // Optional because some old conversations don't have it
    let title: String
    let projectId: String
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
    let lastMessageAt: Date?
    let archived: Bool

    // Additional optional fields for local use
    let summary: String?
    let lastMessage: String?
    let tags: [String]?
    let isPinned: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case title
        case summary
        case lastMessage
        case lastMessageAt
        case createdAt
        case updatedAt
        case messageCount
        case projectId
        case tags
        case isPinned
        case archived
    }

    init(
        id: String = UUID().uuidString,
        userId: String? = nil,
        title: String,
        projectId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messageCount: Int = 0,
        lastMessageAt: Date? = nil,
        archived: Bool = false,
        summary: String? = nil,
        lastMessage: String? = nil,
        tags: [String]? = nil,
        isPinned: Bool? = false
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.lastMessageAt = lastMessageAt
        self.archived = archived
        self.summary = summary
        self.lastMessage = lastMessage
        self.tags = tags
        self.isPinned = isPinned
    }

    // Custom decoder to handle timestamp conversion
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields from API
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)  // Optional for legacy conversations
        title = try container.decode(String.self, forKey: .title)
        projectId = try container.decode(String.self, forKey: .projectId)
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        archived = try container.decode(Bool.self, forKey: .archived)

        // Handle createdAt as timestamp (milliseconds)
        let createdAtTimestamp = try container.decode(Double.self, forKey: .createdAt)
        createdAt = Date(timeIntervalSince1970: createdAtTimestamp / 1000)

        // Handle updatedAt as timestamp (milliseconds)
        let updatedAtTimestamp = try container.decode(Double.self, forKey: .updatedAt)
        updatedAt = Date(timeIntervalSince1970: updatedAtTimestamp / 1000)

        // Handle lastMessageAt as optional timestamp
        if let lastMessageTimestamp = try? container.decodeIfPresent(Double.self, forKey: .lastMessageAt) {
            lastMessageAt = Date(timeIntervalSince1970: lastMessageTimestamp / 1000)
        } else {
            lastMessageAt = nil
        }

        // Optional fields for local use
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
    }

    // Custom encoder to convert dates back to timestamps
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Required fields
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(title, forKey: .title)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encode(archived, forKey: .archived)

        // Timestamps (convert to milliseconds)
        try container.encode(createdAt.timeIntervalSince1970 * 1000, forKey: .createdAt)
        try container.encode(updatedAt.timeIntervalSince1970 * 1000, forKey: .updatedAt)

        if let lastMessageAt = lastMessageAt {
            try container.encode(lastMessageAt.timeIntervalSince1970 * 1000, forKey: .lastMessageAt)
        }

        // Optional fields
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
    }
}

struct ConversationListResponse: Codable {
    let conversations: [Conversation]
    let total: Int
    let hasMore: Bool
}
