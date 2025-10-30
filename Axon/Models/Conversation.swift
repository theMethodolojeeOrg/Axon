//
//  Conversation.swift
//  Axon
//
//  Conversation/Thread model
//

import Foundation

struct Conversation: Codable, Identifiable, Equatable {
    let id: String
    let userId: String?
    let title: String
    let summary: String?
    let lastMessage: String?
    let lastMessageAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
    let projectId: String?
    let tags: [String]?
    let isPinned: Bool?
    let archived: Bool?

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
        summary: String? = nil,
        lastMessage: String? = nil,
        lastMessageAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messageCount: Int = 0,
        projectId: String? = nil,
        tags: [String]? = nil,
        isPinned: Bool? = false,
        archived: Bool? = false
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.summary = summary
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.projectId = projectId
        self.tags = tags
        self.isPinned = isPinned
        self.archived = archived
    }
}

struct ConversationListResponse: Codable {
    let conversations: [Conversation]
    let total: Int
    let hasMore: Bool
}
