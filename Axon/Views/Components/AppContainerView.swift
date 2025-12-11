//
//  AppContainerView.swift
//  Axon
//
//  Main app container with sidebar navigation and view switching
//

import SwiftUI
import MarkdownUI

enum MainView {
    case chat
    case memory
    case settings
}

struct AppContainerView: View {
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var costService = CostService.shared
    @StateObject private var taglineManager = TaglineManager.shared
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
                            .lineLimit(1)
                            .truncationMode(.tail)
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

                        Text(taglineManager.currentTagline)
                            .font(AppTypography.bodyLarge())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .transition(.opacity)
                .onAppear {
                    // Increment tagline view count
                    taglineManager.incrementViewCount()
                    
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
        // Generate summary for the previous conversation before starting new chat
        // This provides continuity context for the new conversation
        if let previousConversation = selectedConversation,
           !conversationService.messages.isEmpty {
            Task {
                await ConversationSummaryService.shared.generateSummary(
                    messages: conversationService.messages,
                    conversationId: previousConversation.id,
                    conversationTitle: previousConversation.title
                )
            }
        }

        selectedConversation = nil
        conversationService.clearCurrentConversation()
        currentView = .chat
        showSidebar = false
    }

    private func selectConversation(_ conversation: Conversation) {
        // Generate summary for the previous conversation before switching
        // This provides continuity context for future conversations
        if let previousConversation = selectedConversation,
           !conversationService.messages.isEmpty {
            Task {
                await ConversationSummaryService.shared.generateSummary(
                    messages: conversationService.messages,
                    conversationId: previousConversation.id,
                    conversationTitle: previousConversation.title
                )
            }
        }

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
    @StateObject private var taglineManager = TaglineManager.shared
    @StateObject private var promptManager = PromptManager.shared
    @ObservedObject private var ttsService = TTSPlaybackService.shared
    @State private var messageText = ""
    @State private var selectedAttachments: [MessageAttachment] = []
    // Tools are now controlled via Settings > Tools tab
    // This computed property reflects the enabled tools from settings
    @State private var isLoading = false
    @State private var showWelcome = true
    @State private var streamingOverrides: [String: String] = [:]
    @State private var regeneratingMessageIds: Set<String> = []
    @FocusState private var isInputFocused: Bool

    // Scroll tracking for scroll-to-bottom button
    @State private var showScrollToBottom = false
    @State private var scrollProxy: ScrollViewProxy?

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
                    attachments: $selectedAttachments,
                    isLoading: isLoading,
                    onSend: sendMessage,
                    focus: $isInputFocused,
                    conversationId: conversation?.id
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

            // Audio player overlay
            AudioPlayerView(ttsService: ttsService)
        }
        .task(id: conversation?.id) {
            if let conversation = conversation {
                isInputFocused = false
                await loadMessages(for: conversation)
            } else {
                conversationService.clearCurrentConversation()
                conversationService.messages = []
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

                    Text(taglineManager.currentTagline)
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
                            prompt: promptManager.currentPrompts.explain
                        ) { prompt in
                            messageText = prompt
                            sendMessage()
                        }

                        PromptCard(
                            icon: "chevron.left.forwardslash.chevron.right",
                            title: "Write code",
                            prompt: promptManager.currentPrompts.code
                        ) { prompt in
                            messageText = prompt
                            sendMessage()
                        }

                        PromptCard(
                            icon: "brain",
                            title: "Remember something",
                            prompt: promptManager.currentPrompts.remember
                        ) { prompt in
                            messageText = prompt
                            sendMessage()
                        }

                        PromptCard(
                            icon: "list.bullet",
                            title: "Create a plan",
                            prompt: promptManager.currentPrompts.plan
                        ) { prompt in
                            messageText = prompt
                            sendMessage()
                        }
                    }
                }
                .padding(.horizontal)
                .onAppear {
                    // Increment prompt view count to trigger generation
                    promptManager.incrementViewCount()
                }

                Spacer()
            }
        }
    }

    // MARK: - Existing Chat View

    private func existingChatView(conversation: Conversation) -> some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Invisible anchor at top for scroll detection
                        Color.clear
                            .frame(height: 1)
                            .id("scroll_top")

                        ForEach(Array(conversationService.messages.enumerated()), id: \.element.id) { index, message in
                            VStack(spacing: 0) {
                                // Add separator before assistant messages (except first message)
                                if message.role == .assistant && index > 0 {
                                    MessageSeparator()
                                        .padding(.vertical, 12)
                                }

                                // Render appropriate view based on role
                                if message.role == .user {
                                    UserMessageView(
                                        message: message,
                                        onCopy: { msg in
                                            #if canImport(UIKit)
                                            UIPasteboard.general.string = msg.content
                                            #elseif canImport(AppKit)
                                            let pb = NSPasteboard.general
                                            pb.clearContents()
                                            pb.setString(msg.content, forType: .string)
                                            #endif
                                        }
                                    )
                                    .padding(.vertical, 8)
                                } else {
                                    AssistantMessageView(
                                        message: message,
                                        overrideContent: streamingOverrides[message.id],
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
                                        onQuote: { quotedText in
                                            // Insert quoted text at cursor position in message input
                                            if messageText.isEmpty {
                                                messageText = quotedText
                                            } else {
                                                messageText += "\n\n" + quotedText
                                            }
                                        }
                                    )
                                }

                                // Add separator after assistant messages (before next user message)
                                if message.role == .assistant && index < conversationService.messages.count - 1 {
                                    let nextMessage = conversationService.messages[index + 1]
                                    if nextMessage.role == .user {
                                        MessageSeparator()
                                            .padding(.vertical, 12)
                                    }
                                }
                            }
                            .id(message.id)
                        }

                        // Invisible anchor at bottom for scroll-to-bottom
                        Color.clear
                            .frame(height: 1)
                            .id("scroll_bottom")
                    }
                    .padding(.vertical)
                    .background(
                        // Geometry reader to detect scroll position
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geometry.frame(in: .named("chat_scroll")).minY
                                )
                        }
                    )
                }
                .coordinateSpace(name: "chat_scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    // Show button when scrolled up (offset becomes more positive as you scroll up)
                    let threshold: CGFloat = -100
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScrollToBottom = offset < threshold
                    }
                }
                .refreshable {
                    // Pull-to-refresh: Force refresh messages from API
                    await loadMessages(for: conversation)
                }
                .onChange(of: conversationService.messages.count) { oldCount, newCount in
                    if newCount > oldCount, let lastMessage = conversationService.messages.last {
                        withAnimation(AppAnimations.standardEasing) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                        // Hide the button since we auto-scrolled
                        showScrollToBottom = false
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                    // Auto-scroll to bottom when entering chat
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastMessage = conversationService.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Glass scroll-to-bottom button
            if showScrollToBottom {
                ScrollToBottomButton {
                    withAnimation(AppAnimations.standardEasing) {
                        if let lastMessage = conversationService.messages.last {
                            scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                        showScrollToBottom = false
                    }
                }
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Actions

    private func loadMessages(for conversation: Conversation) async {
        do {
            _ = try await conversationService.getMessages(conversationId: conversation.id)
        } catch {
            print("Error loading messages: \(error.localizedDescription)")
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty || !selectedAttachments.isEmpty else { return }

        let content = messageText
        let attachments = selectedAttachments
        messageText = ""
        selectedAttachments = []
        
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
                    let title = content.isEmpty ? "New Chat" : String(content.prefix(50))
                    conv = try await conversationService.createConversation(
                        title: title,
                        firstMessage: nil  // Don't send message during creation
                    )
                    onConversationCreated(conv)
                }

                // Get enabled tools from settings
                let settings = SettingsViewModel.shared.settings
                let enabledTools: [String] = settings.toolSettings.toolsEnabled
                    ? Array(settings.toolSettings.enabledToolIds)
                    : []

                // Send message and get assistant response
                let assistant = try await conversationService.sendMessage(
                    conversationId: conv.id,
                    content: content,
                    attachments: attachments,
                    enabledTools: enabledTools
                )

                // Pseudo-stream the assistant content
                startPseudoStream(for: assistant)

                // Record usage with actual provider/model from response
                let inputTokens = max(1, content.count / 4)
                let outputTokens = max(1, assistant.content.count / 4)
                
                // Map provider string to AIProvider
                var provider: AIProvider? = AIProvider(rawValue: assistant.providerName ?? "")
                if provider == nil {
                    if assistant.providerName == "openai-compatible" {
                        provider = .openai // Fallback for pricing
                    } else if let name = assistant.providerName?.lowercased() {
                        if name.contains("anthropic") { provider = .anthropic }
                        else if name.contains("openai") { provider = .openai }
                        else if name.contains("gemini") || name.contains("google") { provider = .gemini }
                        else if name.contains("grok") || name.contains("xai") { provider = .xai }
                    }
                }
                
                if let provider = provider {
                    costService.recordUsage(
                        provider: provider,
                        modelId: assistant.modelName ?? "unknown",
                        inputTokens: inputTokens,
                        outputTokens: outputTokens
                    )
                }
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

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Scroll To Bottom Button

struct ScrollToBottomButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                Text("Jump to latest")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(AppColors.glassBorder, lineWidth: 1)
                    )
            )
            .shadow(color: AppColors.shadow.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    AppContainerView()
}
