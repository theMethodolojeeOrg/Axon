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
    case internalThread
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

    #if os(macOS)
    @StateObject private var artifactPresenter = CodeArtifactPresenter()
    #endif

    var body: some View {
        ZStack {
            #if os(macOS)
            macBody
            #else
            iosBody
            #endif

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
                            .multilineTextAlignment(.center)
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

    #if os(macOS)
    private var macBody: some View {
        NavigationSplitView {
            MacSidebarContentView(
                selectedConversation: $selectedConversation,
                currentView: $currentView,
                onSelectConversation: selectConversation,
                onNewChat: startNewChat,
                onNavigate: navigateToView
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            MacDetailWithInspector(
                currentView: currentView,
                selectedConversation: selectedConversation,
                startNewChat: startNewChat,
                onConversationCreated: { conv in
                    selectedConversation = conv
                },
                presenter: artifactPresenter
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        // Standard macOS sidebar toggle in the toolbar.
                        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                }

                if currentView == .chat {
                    ToolbarItem {
                        Button(action: startNewChat) {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                    }

                    if selectedConversation != nil {
                        ToolbarItem {
                            Button(action: { showChatInfo = true }) {
                                Label("Chat Info", systemImage: "info.circle")
                            }
                        }

                        ToolbarItem {
                            ToolsStatusMenu(style: .pill)
                                .fixedSize()
                        }
                    }

                    // Inspector toggle button
                    ToolbarItem {
                        Button {
                            artifactPresenter.toggle()
                        } label: {
                            Label(
                                artifactPresenter.isOpen ? "Hide Inspector" : "Show Inspector",
                                systemImage: "apple.terminal.on.rectangle"
                            )
                        }
                        .help(artifactPresenter.isOpen ? "Hide Code Inspector" : "Show Code Inspector")
                    }
                }
            }
        }
    }
    #endif

    private var iosBody: some View {
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
                case .internalThread:
                    InternalThreadView()
                case .memory:
                    MemoryView()
                case .settings:
                    SettingsView()
                }
            }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Leading sidebar toggle
                ToolbarItem {
                    Button(action: { withAnimation { showSidebar.toggle() } }) {
                        Image(systemName: "sidebar.left")
                            .foregroundColor(AppColors.textPrimary)
                    }
                }

                // Center title
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        Text(navigationTitle)
                            .font(AppTypography.titleMedium())
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if currentView == .chat, selectedConversation != nil {
                            ToolsStatusMenu(style: .pill)
                                .fixedSize()
                        }
                    }
                }

                // Trailing chat actions
                ToolbarItem {
                    if currentView == .chat {
                        HStack(spacing: 12) {
                            if selectedConversation != nil {
                                Button(action: { showChatInfo = true }) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(AppColors.signalMercury)
                                }
                            }

                            Button(action: startNewChat) {
                                Image(systemName: "square.and.pencil")
                                    .foregroundColor(AppColors.signalMercury)
                            }
                        }
                    }
                }
            }
        }
        #if !os(macOS)
        .navigationViewStyle(.stack)
        #endif
        // Sidebar overlay
        .overlay {
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
        case .internalThread:
            return "Internal Thread"
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

        // For macOS split view, the UX is much better if “New Chat” actually creates
        // and selects a conversation immediately (so the detail pane switches to chat UI).
        // In local-first / device-direct CloudLLM mode this should be a local conversation.
        do {
            let conv = try conversationService.createConversationOffline(title: "New Chat")
            selectedConversation = conv
            conversationService.currentConversation = conv
        } catch {
            // If local creation fails (should be rare), fall back to clearing selection.
            selectedConversation = nil
            conversationService.clearCurrentConversation()
        }

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
    @StateObject private var draftService = DraftMessageService.shared
    @ObservedObject private var ttsService = TTSPlaybackService.shared
    @ObservedObject private var toolApprovalService = ToolApprovalService.shared
    @ObservedObject private var mlxService = MLXModelService.shared
    #if os(macOS)
    @ObservedObject private var bridgeServer = BridgeServer.shared
    #endif
    @State private var messageText = ""
    @State private var selectedAttachments: [MessageAttachment] = []
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var messageLoadTask: Task<Void, Never>?  // Track message loading to prevent races
    // Tools are now controlled via Settings > Tools tab
    // This computed property reflects the enabled tools from settings
    @State private var isLoading = false
    @State private var currentSendTask: Task<Void, Never>?
    @State private var showWelcome = true
    @State private var streamingOverrides: [String: String] = [:]
    @State private var regeneratingMessageIds: Set<String> = []
    @FocusState private var isInputFocused: Bool

    // Scroll tracking for scroll-to-bottom button
    @State private var showScrollToBottom = false
    @State private var scrollProxy: ScrollViewProxy?

    // Streaming state for real-time tool visibility
    @State private var streamingMessageId: String?
    @State private var streamedContent: [String: String] = [:]
    @State private var streamedReasoning: [String: String] = [:]
    @State private var liveToolCalls: [String: [LiveToolCall]] = [:]
    @State private var contextDebugInfos: [String: ContextDebugInfo] = [:]  // Debug info per message
    @State private var useRealStreaming: Bool = true  // Toggle for streaming vs pseudo-streaming

    // VS Code bridge connection banner
    #if os(macOS)
    @State private var showBridgeConnectedBanner = false
    @State private var bridgeWorkspaceName: String?
    #endif

    // First-run welcome card state
    @State private var showFirstRunWelcome = false
    @ObservedObject private var settingsViewModel = SettingsViewModel.shared

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
                    onStop: stopGeneration,
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
            .overlay(alignment: .center) {
                // MLX model download progress overlay
                if mlxService.isLoading {
                    VStack(spacing: 16) {
                        ProgressView(value: mlxService.downloadProgress) {
                            Text(mlxService.loadingStatus)
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .progressViewStyle(LinearProgressViewStyle(tint: AppColors.signalLichen))
                        .frame(maxWidth: 280)

                        Text("First-time download from HuggingFace")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppColors.substrateSecondary)
                            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(AppAnimations.standardEasing, value: mlxService.isLoading)
            #if os(macOS)
            .overlay(alignment: .top) {
                if showBridgeConnectedBanner, let workspace = bridgeWorkspaceName {
                    VSCodeBridgeBanner(workspaceName: workspace, isConnected: true)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .animation(AppAnimations.standardEasing, value: showBridgeConnectedBanner)
            .onReceive(NotificationCenter.default.publisher(for: .bridgeConnectionDidChange)) { notification in
                handleBridgeConnectionChange(notification)
            }
            #endif

            // Audio player overlay
            AudioPlayerView(ttsService: ttsService)

            // Tool approval overlay (Claude Code style)
            // Uses a full-screen overlay with semi-transparent background to ensure visibility
            if let pendingApproval = toolApprovalService.pendingApproval {
                ZStack {
                    // Semi-transparent backdrop to draw attention
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // Dismiss keyboard if open, but don't dismiss the approval
                            isInputFocused = false
                        }

                    VStack {
                        Spacer()
                        ToolApprovalRequestView(
                            approval: pendingApproval,
                            onApprove: {
                                await toolApprovalService.approve()
                            },
                            onApproveForSession: {
                                await toolApprovalService.approveForSession()
                            },
                            onDeny: {
                                toolApprovalService.deny()
                            },
                            onStop: {
                                toolApprovalService.stop()
                            }
                        )
                        .environmentObject(BiometricAuthService.shared)
                        .padding(.horizontal, 16)
                        #if os(iOS)
                        .padding(.bottom, 32) // Smaller padding on iOS - sits above safe area
                        #else
                        .padding(.bottom, 120) // Above the input bar on macOS
                        #endif
                    }
                }
                .transition(.opacity)
                .animation(AppAnimations.standardEasing, value: toolApprovalService.pendingApproval != nil)
                .zIndex(999) // Ensure it's always on top
            }
        }
        .task(id: conversation?.id) {
            // Cancel any in-flight message load to prevent race conditions
            // This fixes the issue where switching conversations quickly could cause
            // stale data from a previous load to overwrite the current conversation's messages
            messageLoadTask?.cancel()

            if let conversation = conversation {
                isInputFocused = false
                // Set conversation for session-based approvals
                toolApprovalService.setCurrentConversation(UUID(uuidString: conversation.id) ?? UUID())

                // Load draft for this conversation
                loadDraft(for: conversation.id)

                // Create a cancellable task for message loading
                messageLoadTask = Task {
                    // Check for cancellation before starting
                    guard !Task.isCancelled else { return }
                    await loadMessages(for: conversation)
                }
                await messageLoadTask?.value
            } else {
                conversationService.clearCurrentConversation()
                conversationService.messages = []

                // Load "New Chat" draft if exists
                loadDraft(for: DraftMessageService.newChatDraftKey)
            }
        }
        .onChange(of: messageText) { oldValue, newValue in
            // Auto-save draft with debouncing
            saveDraftDebounced()
        }
        .onChange(of: selectedAttachments) { oldValue, newValue in
            // Auto-save draft when attachments change
            saveDraftDebounced()
        }
        .onAppear {
            // Show first-run welcome card if user hasn't seen it yet
            showFirstRunWelcome = !settingsViewModel.settings.hasSeenFirstRunWelcome
        }
    }

    #if os(macOS)
    private func handleBridgeConnectionChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let connected = userInfo["connected"] as? Bool else { return }

        if connected, let session = userInfo["session"] as? BridgeSession {
            bridgeWorkspaceName = session.workspaceName
            withAnimation {
                showBridgeConnectedBanner = true
            }
            // Auto-hide after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    showBridgeConnectedBanner = false
                }
            }
        } else {
            // Disconnected - could show a disconnect banner briefly if desired
            withAnimation {
                showBridgeConnectedBanner = false
            }
        }
    }
    #endif

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
                        .multilineTextAlignment(.center)
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
                                            AppClipboard.copy(msg.content)
                                        }
                                    )
                                    .padding(.vertical, 8)
                                } else {
                                    AssistantMessageView(
                                        message: message,
                                        overrideContent: streamedContent[message.id] ?? streamingOverrides[message.id],
                                        onCopy: { msg in
                                            AppClipboard.copy(msg.content)
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
                                        },
                                        liveToolCalls: liveToolCalls[message.id],
                                        streamingReasoning: streamedReasoning[message.id],
                                        contextDebugInfo: contextDebugInfos[message.id]
                                    )

                                    // Show first-run welcome card after the first assistant response
                                    if index == 1 && message.role == .assistant && showFirstRunWelcome {
                                        FirstRunWelcomeCard(onDismiss: {
                                            showFirstRunWelcome = false
                                        })
                                        .padding(.horizontal)
                                        .padding(.top, 16)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
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
                            .background(
                                GeometryReader { geometry in
                                    Color.clear
                                        .preference(
                                            key: BottomAnchorOffsetPreferenceKey.self,
                                            value: geometry.frame(in: .named("chat_scroll")).minY
                                        )
                                }
                            )
                    }
                    .padding(.vertical)
                }
                .coordinateSpace(name: "chat_scroll")
                .onPreferenceChange(BottomAnchorOffsetPreferenceKey.self) { bottomY in
                    // `bottomY` is the bottom anchor's minY in the scroll view's coordinate space.
                    // As you scroll UP (reading older messages), the bottom anchor moves DOWN
                    // relative to the viewport, so its Y value in the coordinate space DECREASES
                    // (becomes smaller or negative as it goes below the visible area).
                    //
                    // When at the bottom (most recent messages), bottomY is near the viewport height.
                    // When scrolled up, bottomY decreases toward 0 or negative.
                    //
                    // Show the jump button when NOT at the bottom (bottomY is small/negative).
                    let threshold: CGFloat = 100
                    let isAwayFromBottom = bottomY < threshold
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScrollToBottom = isAwayFromBottom
                    }
                }
                .refreshable {
                    // Pull-to-refresh: Force refresh messages from API
                    await loadMessages(for: conversation)
                }
                .onChange(of: conversationService.messages.count) { oldCount, newCount in
                    guard newCount > oldCount else { return }

                    // If the user is reading older messages (jump button visible),
                    // do not auto-scroll. Otherwise keep the chat pinned to bottom.
                    guard !showScrollToBottom else { return }

                    withAnimation(AppAnimations.standardEasing) {
                        proxy.scrollTo("scroll_bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                    // Auto-scroll to bottom when entering chat
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("scroll_bottom", anchor: .bottom)
                    }
                }
            }

            // Glass scroll-to-bottom button
            if showScrollToBottom {
                ScrollToBottomButton {
                    withAnimation(AppAnimations.standardEasing) {
                        scrollProxy?.scrollTo("scroll_bottom", anchor: .bottom)
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

        // Check for slash commands first (only if no attachments)
        if SlashCommandParser.shared.isSlashCommand(messageText) && selectedAttachments.isEmpty {
            handleSlashCommand()
            return
        }

        let content = messageText
        let attachments = selectedAttachments

        // Clear draft before sending
        let draftKey = conversation?.id ?? DraftMessageService.newChatDraftKey
        draftService.clearDraft(conversationId: draftKey)

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

        // Check if we should use real streaming (On-Device mode only)
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        let isOnDeviceMode = settings.useOnDeviceOrchestration || settings.deviceMode == .onDevice
        let shouldStream = useRealStreaming && isOnDeviceMode

        // Store the task so we can cancel it if needed
        currentSendTask = Task {
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

                    // Transfer "New Chat" draft to actual conversation
                    draftService.transferNewChatDraft(to: conv.id)
                }

                // Get enabled tools - check for per-conversation overrides first
                let enabledTools: [String] = {
                    guard settings.toolSettings.toolsEnabled else { return [] }

                    // Check for per-conversation tool overrides
                    let overridesKey = "conversation_overrides_\(conv.id)"
                    if let data = UserDefaults.standard.data(forKey: overridesKey),
                       let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data),
                       let toolOverrides = overrides.enabledToolIds {
                        // Use per-conversation tool settings
                        return Array(toolOverrides)
                    }

                    // Fall back to global tool settings
                    return Array(settings.toolSettings.enabledToolIds)
                }()

                if shouldStream {
                    // Use real streaming with inline tool visibility
                    try await sendMessageWithStreaming(
                        conversationId: conv.id,
                        content: content,
                        attachments: attachments,
                        enabledTools: enabledTools
                    )
                } else {
                    // Fallback to non-streaming path
                    let assistant = try await conversationService.sendMessage(
                        conversationId: conv.id,
                        content: content,
                        attachments: attachments,
                        enabledTools: enabledTools
                    )

                    // Pseudo-stream the assistant content
                    startPseudoStream(for: assistant)

                    // Record usage
                    recordUsage(for: assistant, inputContent: content)
                }
            } catch is CancellationError {
                // Task was cancelled - this is expected when user stops generation
                print("[ChatContainer] Message generation was stopped by user")
                await MainActor.run { cleanupStreamingState() }
            } catch {
                print("Error sending message: \(error.localizedDescription)")
                await MainActor.run { cleanupStreamingState() }
            }
            isLoading = false
            currentSendTask = nil
        }
    }

    /// Handle slash command input (e.g., /tool google_search)
    private func handleSlashCommand() {
        let commandText = messageText
        let command = SlashCommandParser.shared.parse(commandText)

        // Clear input
        messageText = ""
        selectedAttachments = []

        // Dismiss keyboard
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #elseif canImport(AppKit)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
        isInputFocused = false

        Task {
            // Execute the slash command
            let result = await SlashCommandParser.shared.execute(command)

            // Add messages to the conversation
            guard let conv = conversation else {
                // For slash commands in "new chat" mode, just show a temporary message
                // We'll create a system-level display without persisting
                let systemMessage = Message(
                    conversationId: "temp",
                    role: .assistant,
                    content: result.resultText,
                    modelName: "System",
                    providerName: "internal"
                )
                conversationService.messages.append(systemMessage)
                return
            }

            // Create user message showing the command
            let userMessage = Message(
                conversationId: conv.id,
                role: .user,
                content: result.displayText
            )
            conversationService.messages.append(userMessage)

            // Create system response with command result
            let systemMessage = Message(
                conversationId: conv.id,
                role: .assistant,
                content: result.resultText,
                modelName: "System",
                providerName: "internal"
            )
            conversationService.messages.append(systemMessage)

            // Persist messages via LocalConversationStore
            // Slash command results are ephemeral context - they help the AI but don't need permanent storage
            // If persistence is desired, use LocalConversationStore.shared.saveLocalMessage()
        }
    }

    /// Send message with real streaming and inline tool visibility
    private func sendMessageWithStreaming(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment],
        enabledTools: [String]
    ) async throws {
        // Create user message
        let userMessage = Message(
            conversationId: conversationId,
            role: .user,
            content: content,
            attachments: attachments.isEmpty ? nil : attachments
        )
        conversationService.messages.append(userMessage)

        // Save user message to Core Data immediately
        // This ensures messages persist even if streaming is interrupted
        let syncManager = ConversationSyncManager.shared
        try await syncManager.saveMessagesToCoreData([userMessage], conversationId: conversationId)
        print("[ChatContainer] 💾 Saved user message to Core Data")

        // Create placeholder assistant message
        let assistantId = UUID().uuidString
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        let apiKeysStorage = APIKeysStorage.shared

        // Get provider and model info
        let providerString = settings.defaultProvider.rawValue
        let modelId = settings.defaultModel
        let providerDisplayName = settings.defaultProvider.displayName

        let placeholderMessage = Message(
            id: assistantId,
            conversationId: conversationId,
            role: .assistant,
            content: "",
            isStreaming: true,
            modelName: modelId,
            providerName: providerString
        )
        conversationService.messages.append(placeholderMessage)

        // Initialize streaming state
        streamingMessageId = assistantId
        streamedContent[assistantId] = ""
        streamedReasoning[assistantId] = ""
        liveToolCalls[assistantId] = []

        // Get API keys from storage
        let anthropicKey = try? apiKeysStorage.getAPIKey(for: .anthropic)
        let openaiKey = try? apiKeysStorage.getAPIKey(for: .openai)
        let geminiKey = try? apiKeysStorage.getAPIKey(for: .gemini)
        let grokKey = try? apiKeysStorage.getAPIKey(for: .xai)
        let perplexityKey = try? apiKeysStorage.getAPIKey(for: .perplexity)
        let deepseekKey = try? apiKeysStorage.getAPIKey(for: .deepseek)
        let zaiKey = try? apiKeysStorage.getAPIKey(for: .zai)
        let minimaxKey = try? apiKeysStorage.getAPIKey(for: .minimax)
        let mistralKey = try? apiKeysStorage.getAPIKey(for: .mistral)

        // Get custom provider config if needed
        var customBaseUrl: String? = nil
        var customApiKey: String? = nil
        if providerString == "openai-compatible",
           let providerId = settings.selectedCustomProviderId,
           let customProvider = settings.customProviders.first(where: { $0.id == providerId }) {
            customBaseUrl = customProvider.apiEndpoint
            if let apiKey = try? apiKeysStorage.getCustomProviderAPIKey(providerId: providerId), !apiKey.isEmpty {
                customApiKey = apiKey
            }
        }

        // Build orchestration config
        let contextWindowLimit = AIProvider.contextWindowForModel(modelId, settings: settings)
        let config = OrchestrationConfig(
            provider: providerString,
            model: modelId,
            providerName: providerDisplayName,
            contextWindowLimit: contextWindowLimit,
            anthropicKey: anthropicKey,
            openaiKey: openaiKey,
            geminiKey: geminiKey,
            grokKey: grokKey,
            perplexityKey: perplexityKey,
            deepseekKey: deepseekKey,
            zaiKey: zaiKey,
            minimaxKey: minimaxKey,
            mistralKey: mistralKey,
            customBaseUrl: customBaseUrl,
            customApiKey: customApiKey
        )

        // Get all messages for context
        let contextMessages = conversationService.messages.filter { $0.id != assistantId }

        // Stream the response
        let orchestrator = OnDeviceConversationOrchestrator()
        let stream = orchestrator.sendMessageStreaming(
            conversationId: conversationId,
            content: content,
            attachments: attachments,
            enabledTools: enabledTools,
            messages: contextMessages,
            config: config
        )

        var finalContent = ""
        var finalReasoning = ""
        var finalToolCalls: [LiveToolCall] = []
        var finalSources: [MessageGroundingSource] = []
        var finalMemoryOps: [MessageMemoryOperation] = []

        for try await event in stream {
            try Task.checkCancellation()

            await MainActor.run {
                switch event {
                case .textDelta(let text):
                    finalContent += text
                    streamedContent[assistantId] = finalContent

                case .reasoningDelta(let text):
                    finalReasoning += text
                    streamedReasoning[assistantId] = finalReasoning

                case .toolCallStart(let toolCall):
                    finalToolCalls.append(toolCall)
                    liveToolCalls[assistantId] = finalToolCalls

                case .toolCallProgress(let id, let progress):
                    if let index = finalToolCalls.firstIndex(where: { $0.id == id }) {
                        finalToolCalls[index].state = progress.state
                        finalToolCalls[index].statusMessage = progress.statusMessage
                        liveToolCalls[assistantId] = finalToolCalls
                    }

                case .toolCallComplete(let id, let result):
                    if let index = finalToolCalls.firstIndex(where: { $0.id == id }) {
                        finalToolCalls[index].state = result.success ? .success : .failure
                        finalToolCalls[index].result = result
                        finalToolCalls[index].completedAt = Date()
                        liveToolCalls[assistantId] = finalToolCalls
                    }

                case .completion(let completion):
                    finalContent = completion.fullContent
                    finalReasoning = completion.reasoning ?? ""
                    finalSources = completion.groundingSources
                    finalMemoryOps = completion.memoryOperations
                    // Store context debug info if available
                    if let debugInfo = completion.contextDebugInfo {
                        contextDebugInfos[assistantId] = debugInfo
                    }

                case .error(let error):
                    print("[ChatContainer] Streaming error: \(error.localizedDescription)")
                }
            }
        }

        // Finalize the message
        await MainActor.run {
            finalizeStreamingMessage(
                assistantId: assistantId,
                conversationId: conversationId,
                content: finalContent,
                reasoning: finalReasoning.isEmpty ? nil : finalReasoning,
                toolCalls: finalToolCalls,
                sources: finalSources,
                memoryOps: finalMemoryOps,
                modelName: config.model,
                providerName: config.providerName
            )
        }
    }

    /// Finalize a streaming message with all collected data
    private func finalizeStreamingMessage(
        assistantId: String,
        conversationId: String,
        content: String,
        reasoning: String?,
        toolCalls: [LiveToolCall],
        sources: [MessageGroundingSource],
        memoryOps: [MessageMemoryOperation],
        modelName: String,
        providerName: String?
    ) {
        // Retrieve context debug info from state
        let contextDebugInfo = contextDebugInfos[assistantId]

        // Update the placeholder message with final content
        if let index = conversationService.messages.firstIndex(where: { $0.id == assistantId }) {
            let finalMessage = Message(
                id: assistantId,
                conversationId: conversationId,
                role: .assistant,
                content: content,
                isStreaming: false,
                modelName: modelName,
                providerName: providerName,
                groundingSources: sources.isEmpty ? nil : sources,
                memoryOperations: memoryOps.isEmpty ? nil : memoryOps,
                reasoning: reasoning,
                contextDebugInfo: contextDebugInfo,
                liveToolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
            conversationService.messages[index] = finalMessage

            // Save assistant message to Core Data
            // This is critical for message persistence when using streaming
            Task {
                do {
                    let syncManager = ConversationSyncManager.shared
                    try await syncManager.saveMessagesToCoreData([finalMessage], conversationId: conversationId)
                    print("[ChatContainer] 💾 Saved assistant message to Core Data")
                } catch {
                    print("[ChatContainer] ❌ Failed to save assistant message to Core Data: \(error)")
                }
            }

            // Record usage
            recordUsage(for: finalMessage, inputContent: "")
        }

        // Clean up streaming state
        cleanupStreamingState()
    }

    /// Clean up streaming state after completion or error
    private func cleanupStreamingState() {
        if let messageId = streamingMessageId {
            streamedContent.removeValue(forKey: messageId)
            streamedReasoning.removeValue(forKey: messageId)
            liveToolCalls.removeValue(forKey: messageId)
            contextDebugInfos.removeValue(forKey: messageId)
        }
        streamingMessageId = nil
    }

    /// Record usage for cost tracking
    private func recordUsage(for assistant: Message, inputContent: String) {
        let inputTokens = max(1, inputContent.count / 4)
        let outputTokens = max(1, assistant.content.count / 4)

        // Map provider string to AIProvider
        var provider: AIProvider? = AIProvider(rawValue: assistant.providerName ?? "")
        if provider == nil {
            if assistant.providerName == "openai-compatible" {
                provider = .openai
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
    }
    
    private func stopGeneration() {
        print("[ChatContainer] Stopping message generation...")
        currentSendTask?.cancel()
        currentSendTask = nil
        isLoading = false
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
    
    // MARK: - Draft Management
    
    private func loadDraft(for conversationId: String) {
        if let draft = draftService.loadDraft(conversationId: conversationId) {
            messageText = draft.text
            selectedAttachments = draft.attachments
            print("[ChatContainer] Loaded draft for conversation: \(conversationId)")
        }
    }
    
    private func saveDraftDebounced() {
        // Cancel previous save task
        draftSaveTask?.cancel()
        
        // Schedule new save with debounce
        draftSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second debounce
                
                // Save draft
                let draftKey = conversation?.id ?? DraftMessageService.newChatDraftKey
                draftService.saveDraft(
                    conversationId: draftKey,
                    text: messageText,
                    attachments: selectedAttachments
                )
            } catch {
                // Task was cancelled, ignore
            }
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

// MARK: - Bottom Anchor Offset Preference Key

struct BottomAnchorOffsetPreferenceKey: PreferenceKey {
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

// MARK: - VS Code Bridge Banner

#if os(macOS)
struct VSCodeBridgeBanner: View {
    let workspaceName: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "personalhotspot")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppColors.signalLichen)

            VStack(alignment: .leading, spacing: 2) {
                Text("VS Code Connected")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Workspace: \(workspaceName)")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Text("AI tools available")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.signalMercury)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.substrateSecondary)
                .shadow(color: AppColors.shadowStrong, radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
    }
}
#endif

#Preview {
    AppContainerView()
}
