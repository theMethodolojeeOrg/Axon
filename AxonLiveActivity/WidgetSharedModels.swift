//
//  WidgetSharedModels.swift
//  AxonLiveActivity
//
//  Shared data models for widget <-> main app communication via App Group.
//  NOTE: This is a copy of the models in main app's Widget service folder.
//  Keep these in sync when making changes.
//

import Foundation

// MARK: - Widget Message

/// A lightweight message representation for the widget
struct WidgetMessage: Codable, Identifiable, Equatable {
    let id: String
    let role: String  // "user" | "assistant" | "system"
    let content: String
    let timestamp: Date
    let modelName: String?
    let providerName: String?

    init(
        id: String = UUID().uuidString,
        role: String,
        content: String,
        timestamp: Date = Date(),
        modelName: String? = nil,
        providerName: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.modelName = modelName
        self.providerName = providerName
    }
}

// MARK: - Widget Conversation Snapshot

/// A snapshot of a conversation for display in the widget
struct WidgetConversationSnapshot: Codable, Identifiable, Equatable {
    let conversationId: String
    let title: String
    let messages: [WidgetMessage]  // Last N messages (typically 5)
    let updatedAt: Date
    let messageCount: Int

    var id: String { conversationId }

    /// Get messages suitable for widget display (most recent first, limited count)
    func messagesForDisplay(limit: Int = 3) -> [WidgetMessage] {
        Array(messages.suffix(limit))
    }

    /// Placeholder snapshot for widget preview
    static var placeholder: WidgetConversationSnapshot {
        WidgetConversationSnapshot(
            conversationId: "placeholder",
            title: "Axon Chat",
            messages: [
                WidgetMessage(
                    role: "user",
                    content: "What's the weather like today?",
                    timestamp: Date().addingTimeInterval(-120)
                ),
                WidgetMessage(
                    role: "assistant",
                    content: "I don't have access to real-time weather data, but I can help you find that information!",
                    timestamp: Date().addingTimeInterval(-60),
                    modelName: "Claude",
                    providerName: "Anthropic"
                )
            ],
            updatedAt: Date(),
            messageCount: 2
        )
    }
}

// MARK: - Widget Data Store

/// The complete data store written to App Group container
struct WidgetDataStore: Codable {
    /// Conversations pinned to widgets, keyed by widget configuration ID
    var pinnedConversations: [String: WidgetConversationSnapshot]

    /// Recent conversations for quick access
    var recentConversations: [WidgetConversationSnapshot]

    /// When this store was last updated
    var lastUpdated: Date

    init(
        pinnedConversations: [String: WidgetConversationSnapshot] = [:],
        recentConversations: [WidgetConversationSnapshot] = [],
        lastUpdated: Date = Date()
    ) {
        self.pinnedConversations = pinnedConversations
        self.recentConversations = recentConversations
        self.lastUpdated = lastUpdated
    }

    /// Empty store
    static var empty: WidgetDataStore {
        WidgetDataStore()
    }
}

// MARK: - App Group Constants

enum WidgetAppGroup {
    /// The App Group identifier shared between main app and widget extension
    static let identifier = "group.com.e2a0f78c018434b3.Axon"

    /// Filename for the widget data store JSON
    static let dataStoreFilename = "widget_data_store.json"

    /// Get the App Group container URL
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Get the full path to the widget data store
    static var dataStoreURL: URL? {
        containerURL?.appendingPathComponent(dataStoreFilename)
    }
}
