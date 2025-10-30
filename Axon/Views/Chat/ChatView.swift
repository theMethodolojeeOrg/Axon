//
//  ChatView.swift
//  Axon
//
//  Main chat interface
//

import SwiftUI
import Combine

struct ChatView: View {
    @StateObject private var conversationService = ConversationService.shared
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false

    let conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(conversationService.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: conversationService.messages.count) { newValue, oldValue in
                    if newValue != oldValue, let lastMessage = conversationService.messages.last {
                        withAnimation(AppAnimations.standardEasing) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input area
            MessageInputBar(
                text: $messageText,
                isLoading: isLoading,
                onSend: sendMessage
            )
        }
        .background(AppColors.substratePrimary)
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMessages()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
            Button("Retry") {
                Task {
                    await retryLastMessage()
                }
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }

    private func loadMessages() async {
        do {
            try await conversationService.getMessages(conversationId: conversation.id)
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let content = messageText
        messageText = ""
        isLoading = true

        Task {
            do {
                _ = try await conversationService.sendMessage(
                    conversationId: conversation.id,
                    content: content
                )
            } catch {
                errorMessage = "Failed to send message: \(error.localizedDescription)\n\nPlease check:\n• Your API key is configured in Settings\n• You have internet connection\n• The message is valid"
                showingError = true
                // Restore the message text so user can retry
                messageText = content
            }
            isLoading = false
        }
    }

    private func retryLastMessage() async {
        if !messageText.isEmpty {
            sendMessage()
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isUser {
                // AI avatar
                Circle()
                    .fill(AppColors.signalMercury)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                // Message content
                Text(message.content)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? AppColors.signalLichen.opacity(0.2) : AppColors.substrateSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        isUser ? AppColors.signalLichen.opacity(0.3) : AppColors.glassBorder,
                                        lineWidth: 1
                                    )
                            )
                    )

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if isUser {
                // User avatar
                Circle()
                    .fill(AppColors.signalLichen)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

// MARK: - Message Input Bar

struct MessageInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                // Text field
                TextField("Type a message...", text: $text, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(20)
                    .disabled(isLoading)
                    .lineLimit(1...5)

                // Send button
                Button(action: onSend) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 40, height: 40)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(text.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AppColors.textDisabled
                                : AppColors.signalMercury
                            )
                    }
                }
                .disabled(isLoading || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ChatView(conversation: Conversation(
            userId: "user1",
            title: "Test Conversation",
            summary: "A test conversation",
            messageCount: 5
        ))
    }
}

