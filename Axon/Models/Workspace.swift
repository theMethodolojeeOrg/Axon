//
//  Workspace.swift
//  Axon
//
//  Model for organizing conversations, documents, and memories by project/topic.
//

import Foundation

struct Workspace: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var description: String?
    let createdAt: Date
    var updatedAt: Date
    var associatedTags: [String]  // Memory tags scoped to this workspace
    var iconName: String?
    var colorHex: String?
    var conversationIds: [String]

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        associatedTags: [String] = [],
        iconName: String? = "folder.fill",
        colorHex: String? = nil,
        conversationIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.associatedTags = associatedTags
        self.iconName = iconName
        self.colorHex = colorHex
        self.conversationIds = conversationIds
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Mutating Helpers

    mutating func addTag(_ tag: String) {
        if !associatedTags.contains(tag) {
            associatedTags.append(tag)
            updatedAt = Date()
        }
    }

    mutating func removeTag(_ tag: String) {
        associatedTags.removeAll { $0 == tag }
        updatedAt = Date()
    }

    mutating func addConversation(_ conversationId: String) {
        if !conversationIds.contains(conversationId) {
            conversationIds.append(conversationId)
            updatedAt = Date()
        }
    }

    mutating func removeConversation(_ conversationId: String) {
        conversationIds.removeAll { $0 == conversationId }
        updatedAt = Date()
    }
}

// MARK: - Default Icons

extension Workspace {
    static let availableIcons: [String] = [
        "folder.fill",
        "doc.fill",
        "book.fill",
        "briefcase.fill",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "lightbulb.fill",
        "star.fill",
        "heart.fill",
        "flag.fill",
        "bookmark.fill",
        "tag.fill",
        "graduationcap.fill",
        "chart.bar.fill",
        "globe",
        "house.fill",
        "person.fill",
        "person.2.fill",
        "building.2.fill",
        "cart.fill"
    ]

    static let availableColors: [String] = [
        "#6B8E9F",  // signalMercury equivalent
        "#7FB069",  // signalLichen equivalent
        "#E87461",  // Error/coral
        "#F4A261",  // Warm orange
        "#E9C46A",  // Yellow
        "#2A9D8F",  // Teal
        "#264653",  // Dark blue
        "#9B5DE5",  // Purple
        "#F15BB5",  // Pink
        "#00BBF9"   // Bright blue
    ]
}
