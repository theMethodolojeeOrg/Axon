//
//  AppContainerView.swift
//  Axon
//
//  Main app container with sidebar navigation and view switching
//

import SwiftUI

enum MainView {
    case chat
    case memory
    case settings
}

struct AppContainerView: View {
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var authService = AuthenticationService.shared
    @State private var showSidebar = false
    @State private var selectedConversation: Conversation?
    @State private var currentView: MainView = .chat

    var body: some View {
        ZStack {
            // Main content area - switches between Chat/Memory/Settings
            NavigationView {
                Group {
                    switch currentView {
                    case .chat:
                        ChatContainerView(
                            conversation: selectedConversation,
                            onNewChat: startNewChat
                        )
                    case .memory:
                        MemoryListView()
                    case .settings:
                        SettingsView()
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { withAnimation { showSidebar.toggle() } }) {
                            Image(systemName: "sidebar.left")
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        Text(navigationTitle)
                            .font(AppTypography.titleMedium())
                            .foregroundColor(AppColors.textPrimary)
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        if currentView == .chat {
                            Button(action: startNewChat) {
                                Image(systemName: "square.and.pencil")
                                    .foregroundColor(AppColors.signalMercury)
                            }
                        }
                    }
                }
            }
            .navigationViewStyle(.stack)

            // Sidebar overlay
            if showSidebar {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showSidebar = false
                        }
                    }

                SidebarView(
                    isPresented: $showSidebar,
                    selectedConversation: $selectedConversation,
                    currentView: $currentView,
                    onSelectConversation: selectConversation,
                    onNewChat: startNewChat,
                    onNavigate: navigateToView
                )
                .transition(.move(edge: .leading))
            }
        }
        .background(AppColors.substratePrimary)
    }

    private var navigationTitle: String {
        switch currentView {
        case .chat:
            return selectedConversation?.title ?? "New Chat"
        case .memory:
            return "Memory"
        case .settings:
            return "Settings"
        }
    }

    private func startNewChat() {
        selectedConversation = nil
        conversationService.clearCurrentConversation()
        currentView = .chat
        showSidebar = false
    }

    private func selectConversation(_ conversation: Conversation) {
        selectedConversation = conversation
        currentView = .chat
        showSidebar = false
    }

    private func navigateToView(_ view: MainView) {
        currentView = view
        showSidebar = false
    }
}

// MARK: - Chat Container View

struct ChatContainerView: View {
    let conversation: Conversation?
    let onNewChat: () -> Void

    @StateObject private var conversationService = ConversationService.shared
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var showWelcome = true

    var body: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let conversation = conversation {
                    // Existing conversation
                    existingChatView(conversation: conversation)
                } else {
                    // Welcome screen for new chat
                    welcomeView
                }

                // Input bar (always visible)
                MessageInputBar(
                    text: $messageText,
                    isLoading: isLoading,
                    onSend: sendMessage
                )
            }
        }
        .task {
            if let conversation = conversation {
                await loadMessages(for: conversation)
            }
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 60)

                // Logo and title
                VStack(spacing: 16) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 60))
                        .foregroundColor(AppColors.signalMercury)

                    Text("NeurX AxonChat")
                        .font(AppTypography.displaySmall())
                        .foregroundColor(AppColors.textPrimary)

                    Text("Memory-augmented AI assistant")
                        .font(AppTypography.bodyLarge())
                        .foregroundColor(AppColors.textSecondary)
                }

                // Suggested prompts
                VStack(spacing: 12) {
                    Text("Suggested prompts")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textTertiary)

                    VStack(spacing: 12) {
                        PromptCard(
                            icon: "lightbulb.fill",
                            title: "Explain a concept",
                            prompt: "Explain quantum computing in simple terms"
                        ) { prompt in
                            messageText = prompt
                            sendMessage()
                        }

                        PromptCard(
                            icon: "chevron.left.forwardslash.chevron.right",
                            title: "Write code",
                            prompt: "Write a Python function to sort a list"
                        ) { prompt in
                            messageText = prompt
                            sendMessage()
                        }

                        PromptCard(
                            icon: "brain",
                            title: "Remember something",
                            prompt: "Remember that I prefer TypeScript over JavaScript"
                        ) { prompt in
                            messageText = prompt
                            sendMessage()
                        }

                        PromptCard(
                            icon: "list.bullet",
                            title: "Create a plan",
                            prompt: "Help me plan a mobile app project"
                        ) { prompt in
                            messageText = prompt
                            sendMessage()
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
        }
    }

    // MARK: - Existing Chat View

    private func existingChatView(conversation: Conversation) -> some View {
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
            .onChange(of: conversationService.messages.count) { _ in
                if let lastMessage = conversationService.messages.last {
                    withAnimation(AppAnimations.standardEasing) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadMessages(for conversation: Conversation) async {
        do {
            try await conversationService.getMessages(conversationId: conversation.id)
        } catch {
            print("Error loading messages: \(error.localizedDescription)")
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let content = messageText
        messageText = ""
        isLoading = true
        showWelcome = false

        Task {
            do {
                // Create conversation if needed
                let conv: Conversation
                if let existing = conversation {
                    conv = existing
                } else {
                    // Create new conversation with first message as title
                    let title = String(content.prefix(50))
                    conv = try await conversationService.createConversation(
                        title: title,
                        firstMessage: content
                    )
                }

                // Send message
                _ = try await conversationService.sendMessage(
                    conversationId: conv.id,
                    content: content
                )
            } catch {
                print("Error sending message: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}

// MARK: - Prompt Card

struct PromptCard: View {
    let icon: String
    let title: String
    let prompt: String
    let onTap: (String) -> Void

    var body: some View {
        Button(action: { onTap(prompt) }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTypography.titleSmall())
                        .foregroundColor(AppColors.textPrimary)

                    Text(prompt)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    AppContainerView()
}
