//
//  WidgetDataService.swift
//  Axon
//
//  Service to write conversation data to App Group for widget consumption.
//  Call updateWidget() after conversation changes to refresh widget content.
//

import Foundation
import WidgetKit

// MARK: - Widget Notifications

extension Notification.Name {
    /// Posted when a deep link from the widget requests opening a conversation
    /// userInfo: ["conversationId": String, "startVoice": Bool (optional)]
    static let openConversationFromWidget = Notification.Name("OpenConversationFromWidget")
}

// MARK: - Widget Data Service

/// Manages the data shared between the main app and widget extension via App Group
final class WidgetDataService {

    // MARK: - Singleton

    static let shared = WidgetDataService()

    private init() {}

    // MARK: - Properties

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Maximum number of messages to store per conversation for widget display
    private let maxMessagesPerConversation = 5

    /// Maximum number of recent conversations to cache
    private let maxRecentConversations = 5

    // MARK: - Public API

    /// Initialize widget data from existing conversations
    /// Call this on app launch to populate the widget with existing data
    @MainActor
    func initializeFromExistingConversations() async {
        // Load existing conversations from CoreData
        let localStore = LocalConversationStore.shared
        let conversations = localStore.loadConversations()

        guard !conversations.isEmpty else {
            print("[WidgetDataService] No existing conversations to initialize widget with")
            return
        }

        var store = loadDataStore() ?? WidgetDataStore.empty

        // Take the most recent conversations (up to maxRecentConversations)
        let recentConversations = Array(conversations.prefix(maxRecentConversations))

        for conversation in recentConversations {
            // Load messages for each conversation
            let messages = localStore.loadMessages(conversationId: conversation.id)
            let snapshot = createSnapshot(from: conversation, messages: messages)
            updateRecentConversations(&store, with: snapshot)
        }

        store.lastUpdated = Date()
        saveDataStore(store)
        refreshWidgets()

        print("[WidgetDataService] Initialized widget with \(recentConversations.count) existing conversations")
    }

    /// Update the widget data for a specific conversation
    /// Call this when messages are added/updated in a conversation
    func updateConversation(_ conversation: Conversation, messages: [Message]) {
        Task {
            await updateConversationAsync(conversation, messages: messages)
        }
    }

    /// Update widget data asynchronously
    @MainActor
    func updateConversationAsync(_ conversation: Conversation, messages: [Message]) async {
        var store = loadDataStore() ?? WidgetDataStore.empty

        // Create snapshot with recent messages
        let snapshot = createSnapshot(from: conversation, messages: messages)

        // Update recent conversations list
        updateRecentConversations(&store, with: snapshot)

        // Update pinned conversation if this is one
        if let pinnedKey = store.pinnedConversations.keys.first(where: { _ in
            store.pinnedConversations.values.contains { $0.conversationId == conversation.id }
        }) {
            store.pinnedConversations[pinnedKey] = snapshot
        }

        store.lastUpdated = Date()

        // Save and refresh widget
        saveDataStore(store)
        refreshWidgets()
    }

    /// Pin a conversation to a widget configuration
    func pinConversation(_ conversation: Conversation, messages: [Message], forWidgetId widgetId: String) {
        var store = loadDataStore() ?? WidgetDataStore.empty

        let snapshot = createSnapshot(from: conversation, messages: messages)
        store.pinnedConversations[widgetId] = snapshot
        store.lastUpdated = Date()

        saveDataStore(store)
        refreshWidgets()
    }

    /// Unpin a conversation from a widget
    func unpinConversation(forWidgetId widgetId: String) {
        var store = loadDataStore() ?? WidgetDataStore.empty

        store.pinnedConversations.removeValue(forKey: widgetId)
        store.lastUpdated = Date()

        saveDataStore(store)
        refreshWidgets()
    }

    /// Get all recent conversations for widget configuration picker
    func getRecentConversations() -> [WidgetConversationSnapshot] {
        let store = loadDataStore() ?? WidgetDataStore.empty
        return store.recentConversations
    }

    /// Force refresh all widgets
    func refreshWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "ConversationWidget")
    }

    // MARK: - Data Store I/O

    /// Load the data store from App Group container
    func loadDataStore() -> WidgetDataStore? {
        guard let url = WidgetAppGroup.dataStoreURL else {
            print("[WidgetDataService] No App Group container URL")
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let store = try decoder.decode(WidgetDataStore.self, from: data)
            return store
        } catch {
            print("[WidgetDataService] Failed to load data store: \(error)")
            return nil
        }
    }

    /// Save the data store to App Group container
    private func saveDataStore(_ store: WidgetDataStore) {
        guard let url = WidgetAppGroup.dataStoreURL else {
            print("[WidgetDataService] No App Group container URL")
            return
        }

        do {
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(store)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[WidgetDataService] Failed to save data store: \(error)")
        }
    }

    // MARK: - Helpers

    /// Create a widget snapshot from a conversation and its messages
    private func createSnapshot(from conversation: Conversation, messages: [Message]) -> WidgetConversationSnapshot {
        // Filter to user/assistant messages only, take most recent
        let relevantMessages = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(maxMessagesPerConversation)

        let widgetMessages = relevantMessages.map { msg in
            WidgetMessage(
                id: msg.id,
                role: msg.role.rawValue,
                content: msg.content,
                timestamp: msg.timestamp,
                modelName: nil,  // Could extract from conversation settings
                providerName: nil
            )
        }

        return WidgetConversationSnapshot(
            conversationId: conversation.id,
            title: conversation.title,
            messages: Array(widgetMessages),
            updatedAt: Date(),
            messageCount: conversation.messageCount
        )
    }

    /// Update the recent conversations list with a new/updated snapshot
    private func updateRecentConversations(_ store: inout WidgetDataStore, with snapshot: WidgetConversationSnapshot) {
        // Remove existing entry for this conversation
        store.recentConversations.removeAll { $0.conversationId == snapshot.conversationId }

        // Add to front (most recent)
        store.recentConversations.insert(snapshot, at: 0)

        // Trim to max size
        if store.recentConversations.count > maxRecentConversations {
            store.recentConversations = Array(store.recentConversations.prefix(maxRecentConversations))
        }
    }
}

// MARK: - Conversation Extension

extension Conversation {
    /// Convert to widget snapshot with given messages
    func toWidgetSnapshot(messages: [Message]) -> WidgetConversationSnapshot {
        let widgetMessages = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(5)
            .map { msg in
                WidgetMessage(
                    id: msg.id,
                    role: msg.role.rawValue,
                    content: msg.content,
                    timestamp: msg.timestamp
                )
            }

        return WidgetConversationSnapshot(
            conversationId: id,
            title: title,
            messages: Array(widgetMessages),
            updatedAt: Date(),
            messageCount: messageCount
        )
    }
}
