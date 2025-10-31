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
    @StateObject private var costService = CostService.shared
    @State private var showSidebar = false
    @State private var selectedConversation: Conversation?
    @State private var currentView: MainView = .chat
    @State private var showChatInfo = false
    @State private var showLaunchScreen: Bool = true

    var body: some View {
        ZStack {
            // Main content area - switches between Chat/Memory/Settings
            NavigationView {
                Group {
                    switch currentView {
                    case .chat:
                        ChatContainerView(
                            conversation: selectedConversation,
                            onNewChat: startNewChat,
                            onConversationCreated: { conv in
                                selectedConversation = conv
                            }
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
                            HStack(spacing: 12) {
                                // Chat info button (only if conversation exists)
                                if selectedConversation != nil {
                                    Button(action: { showChatInfo = true }) {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 20))
                                            .foregroundColor(AppColors.signalMercury)
                                    }
                                }

                                // New chat button
                                Button(action: startNewChat) {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundColor(AppColors.signalMercury)
                                }
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

            // Launch Screen Overlay
            if showLaunchScreen {
                ZStack {
                    AppColors.substratePrimary
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Image("AxonMercury")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .shadow(color: AppColors.shadow, radius: 8, x: 0, y: 4)

                        Text("Axon")
                            .font(AppTypography.displaySmall())
                            .foregroundColor(AppColors.textPrimary)

                        Text("Memory-augmented AI assistant")
                            .font(AppTypography.bodyLarge())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .transition(.opacity)
                .onAppear {
                    // Dismiss launch overlay after a brief moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(AppAnimations.standardEasing) {
                            showLaunchScreen = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showChatInfo) {
            if let conversation = selectedConversation {
                ChatInfoSettingsView(conversation: conversation)
            }
        }
        .background(AppColors.substratePrimary)
        .onAppear {
            // Ensure launch overlay is visible on first appearance
            showLaunchScreen = true
        }
    }

    private var navigationTitle: String {
        switch currentView {
        case .chat:
            if let conv = selectedConversation {
                return SettingsStorage.shared.displayName(for: conv.id) ?? conv.title
            }
            return "New Chat"
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
        conversationService.currentConversation = conversation
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
    let onConversationCreated: (Conversation) -> Void

    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var costService = CostService.shared
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var showWelcome = true
    @State private var streamingOverrides: [String: String] = [:]
    @State private var regeneratingMessageIds: Set<String> = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }

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
                    onSend: sendMessage,
                    focus: $isInputFocused
                )
            }
            .overlay(alignment: .top) {
                if conversation != nil && conversationService.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                            .scaleEffect(0.8)
                        Text("Loading messages…")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .task(id: conversation?.id) {
            if let conversation = conversation {
                isInputFocused = false
                await loadMessages(for: conversation)
            } else {
                conversationService.clearCurrentConversation()
                conversationService.messages = []
                // New chat: focus the input so the keyboard is ready
                isInputFocused = true
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
                    Image("AxonMercury")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .shadow(color: AppColors.shadow, radius: 8, x: 0, y: 4)

                    Text("Axon")
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
                        MessageBubble(
                            message: message,
                            onCopy: { msg in
                                #if canImport(UIKit)
                                UIPasteboard.general.string = msg.content
                                #elseif canImport(AppKit)
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(msg.content, forType: .string)
                                #endif
                            },
                            onRegenerate: { msg in
                                Task {
                                    let convId = conversationService.currentConversation?.id ?? conversation.id
                                    // removed guard let convId = convId else { return } because convId is non-optional
                                    regeneratingMessageIds.insert(msg.id)
                                    do {
                                        let assistant = try await conversationService.regenerateAssistantMessage(
                                            conversationId: convId,
                                            messageId: msg.id
                                        )
                                        // Stream the regenerated assistant content
                                        startPseudoStream(for: assistant) {
                                            regeneratingMessageIds.remove(msg.id)
                                        }
                                    } catch {
                                        regeneratingMessageIds.remove(msg.id)
                                        print("Failed to regenerate: \(error)")
                                    }
                                }
                            },
                            overrideContent: streamingOverrides[message.id]
                        )
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
        // Dismiss keyboard on send
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #elseif canImport(AppKit)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
        isInputFocused = false
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
                    onConversationCreated(conv)
                }

                // Send message and get assistant response
                let assistant = try await conversationService.sendMessage(
                    conversationId: conv.id,
                    content: content
                )

                // Pseudo-stream the assistant content
                startPseudoStream(for: assistant)

                // Record an approximate input usage so the cost pill can tick up
                // TODO: Replace with real token usage and provider/model values from ConversationService
                let approxInputTokens = max(1, content.count / 4) // rough 4 chars per token heuristic
                costService.recordUsage(provider: .anthropic, modelId: "claude-sonnet-4-5-20250929", inputTokens: approxInputTokens, outputTokens: 0)
            } catch {
                print("Error sending message: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    // Simulate streaming by progressively revealing the assistant's content
    private func startPseudoStream(for assistant: Message, onComplete: (() -> Void)? = nil) {
        // Guard only assistant role
        guard assistant.role == .assistant else { return }
        let full = assistant.content
        guard !full.isEmpty else { return }

        // Start from empty override and progressively fill
        streamingOverrides[assistant.id] = ""

        Task { @MainActor in
            var current = ""
            // Stream in chunks of a few characters to feel responsive
            let characters = Array(full)
            let chunkSize = 3
            for i in stride(from: 0, to: characters.count, by: chunkSize) {
                let end = min(i + chunkSize, characters.count)
                current += String(characters[i..<end])
                streamingOverrides[assistant.id] = current
                try? await Task.sleep(nanoseconds: 25_000_000) // 25ms per chunk
            }
            // Remove override to use the canonical content (ensures formatting like Markdown re-renders once fully present)
            streamingOverrides.removeValue(forKey: assistant.id)
            onComplete?()
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

