//
//  ConversationWidgetViews.swift
//  AxonLiveActivity
//
//  SwiftUI views for the conversation widget - header, message bubbles, and footer.
//

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Main Entry View

struct ConversationWidgetEntryView: View {
    var entry: ConversationWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let conversation = entry.conversation {
            conversationContent(conversation)
        } else {
            emptyState
        }
    }

    // MARK: - Conversation Content

    @ViewBuilder
    private func conversationContent(_ conversation: WidgetConversationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            WidgetHeaderView(title: conversation.title)

            // Messages
            messagesSection(conversation)

            Spacer(minLength: 4)

            // Footer with mic button
            WidgetFooterView(conversationId: conversation.conversationId)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func messagesSection(_ conversation: WidgetConversationSnapshot) -> some View {
        let messages = conversation.messagesForDisplay(limit: messageLimit)

        VStack(alignment: .leading, spacing: 6) {
            ForEach(messages) { message in
                WidgetMessageBubble(message: message)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("AxonLogoTemplate")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)

            Text("No Conversations")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Start chatting in Axon")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var messageLimit: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 2
        case .systemLarge: return 4
        case .systemExtraLarge: return 6
        default: return 2
        }
    }
}

// MARK: - Header View

struct WidgetHeaderView: View {
    let title: String
    @Environment(\.widgetFamily) var family

    var body: some View {
        HStack(spacing: 8) {
            // Axon logo
            Image("AxonLogoTemplate")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: logoSize, height: logoSize)
                .foregroundStyle(axonColor)

            // Title
            Text(title)
                .font(titleFont)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
    }

    private var logoSize: CGFloat {
        family == .systemSmall ? 16 : 20
    }

    private var titleFont: Font {
        family == .systemSmall ? .caption : .subheadline
    }

    private var axonColor: Color {
        Color(red: 0.18, green: 0.55, blue: 0.85) // Axon blue
    }
}

// MARK: - Message Bubble

struct WidgetMessageBubble: View {
    let message: WidgetMessage
    @Environment(\.widgetFamily) var family

    private var isUser: Bool {
        message.role == "user"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if !isUser {
                // Assistant icon
                assistantIcon
            }

            // Message content
            messageContent

            if isUser {
                Spacer(minLength: 0)
                // User indicator
                userIndicator
            }
        }
    }

    @ViewBuilder
    private var assistantIcon: some View {
        Image("AxonLogoTemplate")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .foregroundStyle(providerColor)
    }

    @ViewBuilder
    private var userIndicator: some View {
        Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: iconSize))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var messageContent: some View {
        Text(truncatedContent)
            .font(messageFont)
            .foregroundStyle(isUser ? .secondary : .primary)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var truncatedContent: String {
        let limit = family == .systemSmall ? 60 : 100
        if message.content.count > limit {
            return String(message.content.prefix(limit)) + "..."
        }
        return message.content
    }

    private var iconSize: CGFloat {
        family == .systemSmall ? 12 : 14
    }

    private var messageFont: Font {
        family == .systemSmall ? .caption2 : .caption
    }

    private var lineLimit: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 2
        case .systemLarge: return 3
        default: return 2
        }
    }

    private var providerColor: Color {
        // Could be dynamic based on provider, using Axon blue for now
        Color(red: 0.18, green: 0.55, blue: 0.85)
    }
}

// MARK: - Footer View

struct WidgetFooterView: View {
    let conversationId: String
    @Environment(\.widgetFamily) var family

    var body: some View {
        HStack {
            Spacer()

            // Mic button - tapping invokes Siri for voice input
            Link(destination: URL(string: "axon://speak?conversation=\(conversationId)")!) {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: iconSize))

                    if family != .systemSmall {
                        Text("Speak")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, family == .systemSmall ? 8 : 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(axonGradient)
                )
            }

            Spacer()
        }
    }

    private var iconSize: CGFloat {
        family == .systemSmall ? 12 : 14
    }

    private var axonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.55, blue: 0.85),
                Color(red: 0.25, green: 0.45, blue: 0.75)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Empty State View

struct WidgetEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("No Conversation Selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Tap to configure")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
