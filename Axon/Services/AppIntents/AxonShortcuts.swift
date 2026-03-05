//
//  AxonShortcuts.swift
//  Axon
//
//  AppShortcutsProvider - registers Axon's intents with Siri and Shortcuts
//

import AppIntents
import Foundation

/// Provides App Shortcuts for Siri integration
/// These phrases are discoverable system-wide and can be triggered via voice
///
/// Note: String parameters cannot be substituted in phrases (only AppEntity/AppEnum).
/// Users will be prompted to provide the parameter value after triggering the phrase.
struct AxonShortcuts: AppShortcutsProvider {

    /// Maximum of 10 app shortcuts allowed by iOS
    static var appShortcuts: [AppShortcut] {
        // MARK: - AI Query
        AppShortcut(
            intent: AskAxonIntent(),
            phrases: [
                "Ask \(.applicationName) a question",
                "Hey \(.applicationName)",
                "Question for \(.applicationName)"
            ],
            shortTitle: "Ask Axon",
            systemImageName: "brain.head.profile"
        )

        // MARK: - Memory Creation
        AppShortcut(
            intent: CreateMemoryIntent(),
            phrases: [
                "Remember something in \(.applicationName)",
                "Save to \(.applicationName) memory",
                "Create \(.applicationName) memory"
            ],
            shortTitle: "Create Memory",
            systemImageName: "brain"
        )

        // MARK: - Memory Search
        AppShortcut(
            intent: SearchMemoriesIntent(),
            phrases: [
                "What does \(.applicationName) know",
                "Search \(.applicationName) memory",
                "Check \(.applicationName) memory"
            ],
            shortTitle: "Search Memories",
            systemImageName: "magnifyingglass"
        )

        // MARK: - Conversation Search
        AppShortcut(
            intent: SearchConversationsIntent(),
            phrases: [
                "Search \(.applicationName) conversations",
                "Find in \(.applicationName)",
                "Search \(.applicationName)"
            ],
            shortTitle: "Search Conversations",
            systemImageName: "bubble.left.and.bubble.right"
        )

        // MARK: - Start Chat
        AppShortcut(
            intent: StartConversationIntent(),
            phrases: [
                "Start chat in \(.applicationName)",
                "New \(.applicationName) conversation",
                "Open \(.applicationName)"
            ],
            shortTitle: "Start Chat",
            systemImageName: "plus.bubble"
        )

        // MARK: - Send Message (Widget Voice Input)
        AppShortcut(
            intent: SendMessageToConversationIntent(),
            phrases: [
                "Tell \(.applicationName)",
                "Message \(.applicationName)",
                "Send to \(.applicationName)",
                "Say to \(.applicationName)"
            ],
            shortTitle: "Send Message",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}
