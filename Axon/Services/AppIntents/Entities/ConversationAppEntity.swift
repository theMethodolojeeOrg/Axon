//
//  ConversationAppEntity.swift
//  Axon
//
//  AppEntity wrapper for Conversation model - exposes conversations to Siri/Shortcuts
//

import AppIntents
import Foundation

/// Conversation exposed as an AppEntity for Siri and Shortcuts integration
struct ConversationAppEntity: AppEntity {

    // MARK: - Type Display

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Conversation",
            numericFormat: "\(placeholder: .int) conversations"
        )
    }

    // MARK: - Properties

    var id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Last Message")
    var lastMessage: String?

    @Property(title: "Message Count")
    var messageCount: Int

    @Property(title: "Updated")
    var updatedAt: Date

    @Property(title: "Created")
    var createdAt: Date

    // MARK: - Display Representation

    var displayRepresentation: DisplayRepresentation {
        let subtitle: String
        if let lastMsg = lastMessage, !lastMsg.isEmpty {
            let truncated = lastMsg.count > 50
                ? String(lastMsg.prefix(50)) + "..."
                : lastMsg
            subtitle = truncated
        } else {
            subtitle = "\(messageCount) messages"
        }

        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)",
            image: .init(systemName: "bubble.left.and.bubble.right.fill")
        )
    }

    // MARK: - Default Query

    static var defaultQuery = ConversationEntityQuery()

    // MARK: - Initialization

    init(
        id: String,
        title: String,
        lastMessage: String?,
        messageCount: Int,
        updatedAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.messageCount = messageCount
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

// MARK: - Conversation Extension

extension Conversation {
    /// Convert Conversation model to AppEntity for Siri/Shortcuts
    func toAppEntity() -> ConversationAppEntity {
        ConversationAppEntity(
            id: id,
            title: title,
            lastMessage: lastMessage,
            messageCount: messageCount,
            updatedAt: updatedAt,
            createdAt: createdAt
        )
    }
}
