//
//  StartConversationIntent.swift
//  Axon
//
//  AppIntent to start a new conversation - opens Axon to new chat
//

import AppIntents
import Foundation

/// Intent to start a new conversation in Axon
/// Siri: "Start chat in Axon"
struct StartConversationIntent: AppIntent {

    // MARK: - Metadata

    static var title: LocalizedStringResource = "Start New Chat"

    static var description = IntentDescription(
        "Start a new conversation with Axon AI",
        categoryName: "Conversations"
    )

    /// Opens the app when run
    static var openAppWhenRun: Bool = true

    // MARK: - Parameters

    @Parameter(title: "Initial Message", description: "Optional first message to send")
    var initialMessage: String?

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        Summary("Start a new chat in Axon") {
            \.$initialMessage
        }
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        // The app will open and show the new chat screen
        // If initialMessage is provided, it could be passed via deep link or notification

        if let message = initialMessage, !message.isEmpty {
            // Post notification for the app to handle
            NotificationCenter.default.post(
                name: .startConversationWithMessage,
                object: nil,
                userInfo: ["message": message]
            )
        }

        return .result()
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let startConversationWithMessage = Notification.Name("startConversationWithMessage")
}
