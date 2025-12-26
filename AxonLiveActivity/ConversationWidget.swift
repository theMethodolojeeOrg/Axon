//
//  ConversationWidget.swift
//  AxonLiveActivity
//
//  Home screen widget displaying a mini chat view from a pinned conversation.
//  Supports voice input via Siri App Intents.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Entry

struct ConversationWidgetEntry: TimelineEntry {
    let date: Date
    let conversation: WidgetConversationSnapshot?
    let configuration: SelectConversationIntent

    static var placeholder: ConversationWidgetEntry {
        ConversationWidgetEntry(
            date: Date(),
            conversation: .placeholder,
            configuration: SelectConversationIntent()
        )
    }
}

// MARK: - Timeline Provider

struct ConversationTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = ConversationWidgetEntry
    typealias Intent = SelectConversationIntent

    func placeholder(in context: Context) -> Entry {
        .placeholder
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        // Return cached data or placeholder for gallery preview
        let conversation = resolveConversation(for: configuration)
        return ConversationWidgetEntry(
            date: Date(),
            conversation: conversation ?? .placeholder,
            configuration: configuration
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let conversation = resolveConversation(for: configuration)

        let entry = ConversationWidgetEntry(
            date: Date(),
            conversation: conversation,
            configuration: configuration
        )

        // Use push-based updates - main app will call reloadTimelines when needed
        // Backup refresh every hour in case push fails
        let refreshDate = Date().addingTimeInterval(3600)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    // MARK: - Helpers

    private func resolveConversation(for configuration: Intent) -> WidgetConversationSnapshot? {
        let store = loadWidgetData()

        // If user selected a specific conversation, try to find it
        if let selectedId = configuration.conversation?.id {
            // Check pinned first
            if let pinned = store?.pinnedConversations.values.first(where: { $0.conversationId == selectedId }) {
                return pinned
            }
            // Then check recent
            if let recent = store?.recentConversations.first(where: { $0.conversationId == selectedId }) {
                return recent
            }
        }

        // Fall back to most recent conversation
        return store?.recentConversations.first
    }

    private func loadWidgetData() -> WidgetDataStore? {
        guard let url = WidgetAppGroup.dataStoreURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WidgetDataStore.self, from: data)
        } catch {
            print("[ConversationWidget] Failed to load data: \(error)")
            return nil
        }
    }
}

// MARK: - Widget Definition

struct ConversationWidget: Widget {
    let kind: String = "ConversationWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectConversationIntent.self,
            provider: ConversationTimelineProvider()
        ) { entry in
            ConversationWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Axon Chat")
        .description("Quick access to your AI conversations with voice input")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #if os(macOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        #endif
    }
}

// MARK: - Widget Configuration Intent

struct SelectConversationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Conversation"
    static var description = IntentDescription("Choose which conversation to display in the widget")

    @Parameter(title: "Conversation")
    var conversation: ConversationWidgetEntity?

    init() {}

    init(conversation: ConversationWidgetEntity?) {
        self.conversation = conversation
    }
}

// MARK: - Conversation Entity for Widget Configuration

struct ConversationWidgetEntity: AppEntity {
    var id: String
    var title: String
    var lastMessage: String?
    var messageCount: Int

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Conversation")
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle = lastMessage ?? "\(messageCount) messages"
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)",
            image: .init(systemName: "bubble.left.and.bubble.right.fill")
        )
    }

    static var defaultQuery = ConversationWidgetEntityQuery()
}

// MARK: - Entity Query

struct ConversationWidgetEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ConversationWidgetEntity] {
        let store = loadWidgetData()
        var results: [ConversationWidgetEntity] = []

        for id in identifiers {
            if let snapshot = store?.recentConversations.first(where: { $0.conversationId == id }) {
                results.append(ConversationWidgetEntity(
                    id: snapshot.conversationId,
                    title: snapshot.title,
                    lastMessage: snapshot.messages.last?.content,
                    messageCount: snapshot.messageCount
                ))
            }
        }

        return results
    }

    func suggestedEntities() async throws -> [ConversationWidgetEntity] {
        let store = loadWidgetData()
        return store?.recentConversations.map { snapshot in
            ConversationWidgetEntity(
                id: snapshot.conversationId,
                title: snapshot.title,
                lastMessage: snapshot.messages.last?.content,
                messageCount: snapshot.messageCount
            )
        } ?? []
    }

    func defaultResult() async -> ConversationWidgetEntity? {
        let store = loadWidgetData()
        guard let first = store?.recentConversations.first else { return nil }
        return ConversationWidgetEntity(
            id: first.conversationId,
            title: first.title,
            lastMessage: first.messages.last?.content,
            messageCount: first.messageCount
        )
    }

    private func loadWidgetData() -> WidgetDataStore? {
        guard let url = WidgetAppGroup.dataStoreURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(WidgetDataStore.self, from: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    ConversationWidget()
} timeline: {
    ConversationWidgetEntry.placeholder
}

#Preview(as: .systemSmall) {
    ConversationWidget()
} timeline: {
    ConversationWidgetEntry.placeholder
}

#Preview(as: .systemLarge) {
    ConversationWidget()
} timeline: {
    ConversationWidgetEntry.placeholder
}
