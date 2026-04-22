//
//  AppContainerView.swift
//  Axon
//
//  Main app container with sidebar navigation and view switching
//

import SwiftUI
import Combine
import MarkdownUI

enum MainView {
    case chat
    case cognition  // Combines Memory + Internal Thread
    case settings
    case create     // Creative gallery for generated media and artifacts
}

extension MainView {
    var agentViewRef: String {
        switch self {
        case .chat:
            return "chat"
        case .cognition:
            return "cognition"
        case .settings:
            return "settings"
        case .create:
            return "create"
        }
    }
}

struct AppContainerView: View {
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var costService = CostService.shared
    @StateObject private var taglineManager = TaglineManager.shared
    @StateObject private var liveService = LiveSessionService.shared
    @StateObject private var settingsViewModel = SettingsViewModel.shared

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

            // Live Session Overlay
            if liveService.status != .idle && liveService.status != .disconnected {
                LiveSessionOverlay()
                    .zIndex(200) // Ensure visibility
                    .onAppear {
                        debugLog(.liveSession, "[LiveOverlay] Overlay appeared, status: \(liveService.status)")
                    }
                    .onDisappear {
                        debugLog(.liveSession, "[LiveOverlay] Overlay disappeared, status: \(liveService.status)")
                    }
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
            publishAgentActionUIState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .axonUIActionRequest)) { notification in
            Task { @MainActor in
                await handleAgentActionRequest(notification)
            }
        }
        .task {
            // Eagerly load V2 tools at app startup so they're available immediately
            // This runs once when the view appears and loads tools in the background
            if ToolsV2Toggle.shared.isV2Active {
                await ToolPluginLoader.shared.loadAllTools()
            }
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

                        ToolbarItem {
                            Button(action: {
                                debugLog(.liveSession, "🔘 Live button tapped!")
                                startLiveSession()
                            }) {
                                Label("Live", systemImage: "waveform.circle")
                            }
                            .help("Start Live voice session")
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
        NavigationStack {
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
                case .cognition:
                    CognitionView()
                case .settings:
                    SettingsView()
                case .create:
                    CreateGalleryView()
                }
            }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Leading sidebar toggle
                ToolbarItem {
                    chatToolbarButton(
                        icon: "sidebar.left",
                        tint: AppColors.textPrimary
                    ) {
                        withAnimation {
                            showSidebar.toggle()
                        }
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
                        HStack(spacing: 8) {
                            if selectedConversation != nil {
                                chatToolbarButton(
                                    icon: "info.circle",
                                    tint: AppColors.signalMercury,
                                    accessibilityLabel: "Chat Info"
                                ) {
                                    showChatInfo = true
                                }
                            }

                            chatToolbarButton(
                                icon: "square.and.pencil",
                                tint: AppColors.signalMercury,
                                accessibilityLabel: "New Chat"
                            ) {
                                startNewChat()
                            }

                            if selectedConversation != nil {
                                chatToolbarButton(
                                    icon: "waveform.circle",
                                    tint: AppColors.signalMercury,
                                    accessibilityLabel: "Start Live Session"
                                ) {
                                    startLiveSession()
                                }
                            }
                        }
                    }
                }
            }
        }
        // Sidebar overlay
        .overlay {
            if showSidebar {
                Color.black.opacity(ChatVisualTokens.sidebarScrimOpacity)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(AppAnimations.standardEasing) {
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
        .animation(AppAnimations.standardEasing, value: showSidebar)
    }

    @ViewBuilder
    private func chatToolbarButton(
        icon: String,
        tint: Color,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: ChatVisualTokens.toolbarButtonSize, height: ChatVisualTokens.toolbarButtonSize)
                .background(
                    Circle()
                        .fill(AppColors.substrateSecondary.opacity(0.7))
                )
                .overlay(
                    Circle()
                        .stroke(AppColors.glassBorder.opacity(0.6), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? icon)
    }

    private var navigationTitle: String {
        switch currentView {
        case .chat:
            if let conv = selectedConversation {
                return SettingsStorage.shared.displayName(for: conv.id) ?? conv.title
            }
            return "New Chat"
        case .cognition:
            return "Cognition"
        case .settings:
            return "Settings"
        case .create:
            return "Create"
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

        // Discard any existing ephemeral conversation from the previous selection
        // This prevents empty "New Chat" threads from accumulating
        if let previousId = selectedConversation?.id {
            conversationService.discardEphemeralConversation(previousId)
        }

        // Create an ephemeral conversation (in-memory only, not persisted to Core Data)
        // The conversation will only be persisted when the user sends their first message
        // This prevents empty "New Chat" threads from cluttering the sidebar
        let conv = conversationService.createEphemeralConversation(title: "New Chat")
        selectedConversation = conv
        conversationService.currentConversation = conv

        // Update temporal context with the new conversation
        TemporalContextService.shared.setCurrentConversation(conv.id)

        currentView = .chat
        showSidebar = false
        publishAgentActionUIState()
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

        // Discard any ephemeral conversation from the previous selection
        // This prevents empty "New Chat" threads from accumulating when user
        // creates a new chat but then selects an existing conversation instead
        if let previousId = selectedConversation?.id {
            conversationService.discardEphemeralConversation(previousId)
        }

        selectedConversation = conversation
        conversationService.currentConversation = conversation
        currentView = .chat
        showSidebar = false

        // Update temporal context with the new conversation
        TemporalContextService.shared.setCurrentConversation(conversation.id)
        publishAgentActionUIState()
    }

    private func navigateToView(_ view: MainView) {
        // Discard any ephemeral conversation when navigating away from chat
        // This prevents empty "New Chat" threads from accumulating
        if view != .chat, let currentId = selectedConversation?.id {
            conversationService.discardEphemeralConversation(currentId)
        }

        currentView = view
        showSidebar = false
        publishAgentActionUIState()
    }

    private func publishAgentActionUIState() {
        AgentActionRegistry.shared.updateUIState(
            currentView: currentView.agentViewRef,
            selectedConversation: selectedConversation
        )
    }

    private func handleAgentActionRequest(_ notification: Notification) async {
        guard let request = notification.userInfo?["request"] as? AgentActionUIRequest else {
            return
        }

        let result = await processAgentActionRequest(request)
        AgentActionRegistry.shared.completeUIRequest(requestId: request.requestId, result: result)
    }

    private func processAgentActionRequest(_ request: AgentActionUIRequest) async -> AgentActionResult {
        switch request.actionId {
        case "open_chat":
            navigateToView(.chat)
            return .success("Opened chat view")

        case "open_cognition":
            navigateToView(.cognition)
            return .success("Opened cognition view")

        case "open_settings":
            navigateToView(.settings)
            return .success("Opened settings view")

        case "open_create":
            navigateToView(.create)
            return .success("Opened create view")

        case "new_chat":
            startNewChat()
            return .success(
                "Started new chat",
                data: selectedConversation.map {
                    ["conversation_id": .string($0.id)]
                }
            )

        case "select_conversation":
            guard let conversationId = request.params["conversation_id"]?.stringValue else {
                return .failure("Missing required parameter: conversation_id", code: "invalid_params")
            }

            if let conversation = conversationService.conversations.first(where: { $0.id == conversationId }) {
                selectConversation(conversation)
                return .success("Selected conversation \(conversationId)")
            }

            do {
                try await conversationService.listConversations(limit: 200, offset: 0)
            } catch {
                return .failure("Failed to refresh conversations: \(error.localizedDescription)", code: "refresh_failed")
            }

            guard let refreshed = conversationService.conversations.first(where: { $0.id == conversationId }) else {
                return .failure("Conversation not found: \(conversationId)", code: "not_found")
            }

            selectConversation(refreshed)
            return .success("Selected conversation \(conversationId)")

        default:
            return .failure("Unsupported UI action: \(request.actionId)", code: "unsupported_ui_action")
        }
    }


    private func startLiveSession() {
        guard let conversation = selectedConversation else {
            debugLog(.liveSession, "⚠️ startLiveSession called but no selectedConversation")
            return
        }

        debugLog(.liveSession, "🎬 startLiveSession called for conversation: \(conversation.id), isEphemeral: \(conversationService.isEphemeral(conversation.id))")

        let settings = settingsViewModel.settings.liveSettings
        var provider: AIProvider = settings.defaultProvider
        var modelId = settings.defaultModelId
        var voice = (provider == .openai) ? settings.openAIVoice : settings.geminiVoice
        
        // Check for overrides
        let key = "conversation_overrides_\(conversation.id)"
        if let data = UserDefaults.standard.data(forKey: key),
           let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {
            
            if let pRaw = overrides.liveProvider {
                 if pRaw == "openai" { provider = .openai }
                 else if pRaw == "gemini" { provider = .gemini }
            }
            if let m = overrides.liveModel { modelId = m }
            if let v = overrides.liveVoice { voice = v }
        }
        
        // Update voice based on provider if not overridden specifically (simplified logic)
        // Ideally we should check if voice matches provider context, but we trust the user/logic here.

        debugLog(.liveSession, "🚀 Starting Live session with provider: \(provider), model: \(modelId), voice: \(voice)")

        Task {
            // Build full Axon context with personality and memories
            let systemInstruction = await LiveContextBuilder.shared.buildLiveSystemInstruction(
                tokenBudget: 1500 // Keep concise for voice latency
            )

            // Debug: log what we're injecting
            let debugInfo = await LiveContextBuilder.shared.debugContextInfo()
            debugLog(.liveSession, debugInfo)

            let config = LiveSessionConfig(
                 apiKey: "", // Resolved by Service
                 modelId: modelId,
                 voice: voice,
                 systemInstruction: systemInstruction,
                 tools: nil
            )

            await liveService.startSession(config: config, providerType: provider)
        }
    }
}

// MARK: - Chat Container View

struct ChatContainerView: View {
    let conversation: Conversation?
    let onNewChat: () -> Void
    let onConversationCreated: (Conversation) -> Void

    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var memoryService = MemoryService.shared
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
    @State private var isFirstMessageSending: Bool = false  // Prevents message reload race condition during first message

    // VS Code bridge connection banner
    #if os(macOS)
    @State private var showBridgeConnectedBanner = false
    @State private var bridgeWorkspaceName: String?
    #endif

    // First-run welcome card state
    @State private var showFirstRunWelcome = false
    @ObservedObject private var settingsViewModel = SettingsViewModel.shared

    // Message editing state
    @State private var messageToEdit: Message? = nil
    @State private var messageToDelete: Message? = nil
    @State private var showDeleteConfirmation = false
    @State private var attachmentSendValidationMessage: String?

    var body: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }

            VStack(spacing: 0) {
                if let conversation = conversation {
                    // Solo thread status bar (if applicable)
                    if conversation.isSoloThread {
                        SoloThreadStatusBar(conversation: conversation)
                    }
                    
                    // Existing conversation
                    existingChatView(conversation: conversation)
                } else {
                    // Welcome screen for new chat
                    welcomeView
                }
                #if os(macOS)
                composerOrSoloToolbar
                #endif
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
            #if os(iOS)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerOrSoloToolbar
            }
            #endif
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

                // Skip loading if we're in the middle of sending the first message
                // The streaming code handles adding messages to the array, and loading
                // would wipe them out since the new conversation has no saved messages yet
                guard !isFirstMessageSending else { return }

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
        .sheet(item: $messageToEdit) { message in
            MessageEditSheet(
                message: message,
                onSave: { newContent in
                    // Save without regenerating
                    Task {
                        if let convId = conversation?.id {
                            _ = try? await conversationService.editMessage(
                                conversationId: convId,
                                messageId: message.id,
                                content: newContent
                            )
                        }
                    }
                    messageToEdit = nil
                },
                onSaveAndRegenerate: { newContent in
                    // Save and regenerate AI response
                    Task {
                        if let convId = conversation?.id {
                            let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
                            let enabledTools = settings.toolSettings.toolsEnabled ? Array(settings.toolSettings.enabledToolIds) : []
                            isLoading = true
                            _ = try? await conversationService.editAndRegenerate(
                                conversationId: convId,
                                messageId: message.id,
                                content: newContent,
                                enabledTools: enabledTools
                            )
                            isLoading = false
                        }
                    }
                    messageToEdit = nil
                },
                onCancel: {
                    messageToEdit = nil
                }
            )
        }
        .alert("Delete Message?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                messageToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let message = messageToDelete, let convId = conversation?.id {
                    Task {
                        try? await conversationService.deleteMessage(
                            conversationId: convId,
                            messageId: message.id
                        )
                    }
                }
                messageToDelete = nil
            }
        } message: {
            Text("This message will be replaced with a placeholder. This action cannot be undone.")
        }
        .alert("Attachment Not Supported", isPresented: Binding(
            get: { attachmentSendValidationMessage != nil },
            set: { shown in
                if !shown { attachmentSendValidationMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {
                attachmentSendValidationMessage = nil
            }
        } message: {
            Text(attachmentSendValidationMessage ?? "")
        }
    }

    @ViewBuilder
    private var composerOrSoloToolbar: some View {
        if let conversation = conversation,
           conversation.isSoloThread,
           conversation.isSoloActive {
            SoloThreadToolbar(
                conversation: conversation,
                onPause: {
                    SoloThreadService.shared.pauseSession()
                },
                onTakeOver: {
                    SoloThreadService.shared.userTakeOver(threadId: conversation.id)
                }
            )
        } else {
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
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: ChatVisualTokens.welcomeHeroTopSpacing)

                // Logo and title
                VStack(spacing: 12) {
                    Image("AxonMercury")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: ChatVisualTokens.welcomeHeroLogoSize,
                            height: ChatVisualTokens.welcomeHeroLogoSize
                        )
                        .shadow(color: AppColors.shadow, radius: 8, x: 0, y: 4)

                    Text("Axon")
                        .font(AppTypography.headlineLarge())
                        .foregroundColor(AppColors.textPrimary)

                    Text(taglineManager.currentTagline)
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Suggested prompts
                VStack(spacing: ChatVisualTokens.welcomePromptCardSpacing) {
                    Text("Suggested prompts")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textTertiary)

                    VStack(spacing: ChatVisualTokens.welcomePromptCardSpacing) {
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

                Spacer(minLength: 16)
            }
            .padding(.bottom, 12)
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
                            let previousRole = role(at: index - 1)
                            let nextRole = role(at: index + 1)
                            let isEndOfCluster = nextRole != message.role

                            VStack(spacing: 0) {
                                // Render appropriate view based on role
                                if message.role == .user {
                                    // Check if message is deleted - show placeholder
                                    if message.isDeleted == true {
                                        DeletedMessageView()
                                    } else {
                                        VStack(spacing: 0) {
                                            UserMessageView(
                                                message: message,
                                                onCopy: { msg in
                                                    AppClipboard.copy(msg.content)
                                                },
                                                onEdit: { msg in
                                                    messageToEdit = msg
                                                },
                                                onDelete: { msg in
                                                    messageToDelete = msg
                                                    showDeleteConfirmation = true
                                                },
                                                showAvatar: isEndOfCluster,
                                                showMetadata: isEndOfCluster
                                            )

                                            // Show edit icon at end of a user turn for discoverability.
                                            if isEndOfCluster {
                                                // This is the last user message before an assistant response
                                                HStack {
                                                    Spacer()
                                                    Button {
                                                        messageToEdit = message
                                                    } label: {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "pencil")
                                                                .font(.system(size: 12, weight: .semibold))
                                                            Text("Edit")
                                                                .font(AppTypography.labelSmall())
                                                        }
                                                        .foregroundColor(AppColors.textTertiary)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 6)
                                                        .background(AppColors.substrateSecondary.opacity(0.8))
                                                        .clipShape(Capsule())
                                                        .overlay(
                                                            Capsule()
                                                                .stroke(AppColors.glassBorder.opacity(0.6), lineWidth: 1)
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                    .padding(.trailing)
                                                    .padding(.top, 4)
                                                }
                                            }
                                        }
                                    }
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
                                        contextDebugInfo: contextDebugInfos[message.id],
                                        showMetadata: isEndOfCluster
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

                                    // Show temporal status bar after the last assistant message
                                    if message.role == .assistant && index == conversationService.messages.count - 1 {
                                        TemporalStatusBar(
                                            contextSaturation: getContextSaturation(for: message.id),
                                            contextLimit: getContextLimit(for: message.id)
                                        )
                                        .padding(.horizontal)
                                        .padding(.top, 10)
                                    }
                                }
                            }
                            .padding(.top, verticalSpacingBeforeMessage(at: index, previousRole: previousRole))
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
                    .padding(.vertical, ChatVisualTokens.messageSectionVerticalPadding)
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
                    withAnimation(AppAnimations.standardEasing) {
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
        .overlay(alignment: .top) {
            if let warning = memoryService.subconsciousWarning(for: conversation.id) {
                SubconsciousLoggingWarningBanner(
                    message: warning.message,
                    onClose: {
                        memoryService.dismissSubconsciousWarning(conversationId: conversation.id)
                    },
                    onIgnoreThread: {
                        memoryService.ignoreSubconsciousLoggingForThread(conversationId: conversation.id)
                    }
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }

    private func role(at index: Int) -> MessageRole? {
        guard conversationService.messages.indices.contains(index) else { return nil }
        return conversationService.messages[index].role
    }

    private func verticalSpacingBeforeMessage(at index: Int, previousRole: MessageRole?) -> CGFloat {
        guard index > 0 else { return 0 }
        return previousRole == conversationService.messages[index].role
            ? ChatVisualTokens.intraClusterSpacing
            : ChatVisualTokens.interTurnSpacing
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

        guard validateSelectedAttachmentsBeforeSend() else {
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
            // Ensure UI state is always finalized on the MainActor
            defer {
                Task { @MainActor in
                    isLoading = false
                    currentSendTask = nil
                }
            }

            do {
                // Create or persist conversation if needed
                let conv: Conversation
                if let existing = conversation {
                    // Check if this is an ephemeral conversation that needs to be persisted
                    if conversationService.isEphemeral(existing.id) {
                        // Set flag to prevent .task from reloading messages during first send
                        // This prevents a race condition where the conversation ID change triggers
                        // a message reload that wipes out the messages we're about to add
                        await MainActor.run { isFirstMessageSending = true }

                        // Persist the ephemeral conversation now that user is sending first message
                        let title = content.isEmpty ? "New Chat" : String(content.prefix(50))
                        conv = try conversationService.persistEphemeralConversation(existing.id, title: title)
                        onConversationCreated(conv)

                        // Transfer "New Chat" draft to actual conversation
                        draftService.transferNewChatDraft(to: conv.id)
                    } else {
                        conv = existing
                    }
                } else {
                    // No conversation exists - create new one with first message as title
                    let title = content.isEmpty ? "New Chat" : String(content.prefix(50))
                    conv = try await conversationService.createConversation(
                        title: title,
                        firstMessage: nil  // Don't send message during creation
                    )
                    onConversationCreated(conv)

                    // Transfer "New Chat" draft to actual conversation
                    draftService.transferNewChatDraft(to: conv.id)
                }

                // Check if this is a private thread - if so, just save message without AI
                // Check both the model flag and UserDefaults (for persistence across app launches)
                if conv.isPrivate == true || Self.isConversationPrivate(conv.id) {
                    try await sendPrivateMessage(
                        conversationId: conv.id,
                        content: content,
                        attachments: attachments
                    )
                    return
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
                await MainActor.run {
                    cleanupStreamingState()
                    // Ensure UI state ends cleanly even on cancellation
                    isLoading = false
                    isFirstMessageSending = false
                }
            } catch {
                print("[ChatContainer] Error sending message: \(error.localizedDescription)")
                await MainActor.run {
                    cleanupStreamingState()
                    // Ensure UI state ends cleanly even on error
                    isLoading = false
                    isFirstMessageSending = false
                }

                // If we errored after creating a conversation, surface an error bubble so the user
                // doesn’t experience a silent “no response”.
                // Prefer the resolved conversation ID if available.
                let convId = conversationService.currentConversation?.id ?? conversation?.id
                if let convId {
                    let errorBubble = Message(
                        conversationId: convId,
                        role: .assistant,
                        content: "⚠️ Request failed: \(error.localizedDescription)\n\nTry again, or check provider/API key/network.",
                        modelName: "System",
                        providerName: "internal"
                    )
                    conversationService.messages.append(errorBubble)
                }
            }
        }
    }

    private func validateSelectedAttachmentsBeforeSend() -> Bool {
        guard !selectedAttachments.isEmpty else { return true }

        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        let policy: AttachmentMimePolicy
        if let conversationId = conversation?.id {
            let resolved = ConversationModelResolver.resolve(conversationId: conversationId, settings: settings)
            let runtime = ConversationRuntimeOverrideManager.shared.resolve(
                conversationId: conversationId,
                baseProvider: resolved.normalizedProvider,
                baseModel: resolved.modelId,
                baseProviderDisplayName: resolved.providerName,
                baseModelParams: settings.modelGenerationSettings
            )
            policy = AttachmentMimePolicyService.resolvePolicy(
                provider: runtime.provider,
                modelId: runtime.model,
                providerName: runtime.providerDisplayName,
                conversationId: conversationId,
                settings: settings
            )
        } else {
            let resolved = ConversationModelResolver.resolveGlobal(settings: settings)
            policy = AttachmentMimePolicyService.resolvePolicy(
                provider: resolved.normalizedProvider,
                modelId: resolved.modelId,
                providerName: resolved.providerName,
                conversationId: nil,
                settings: settings
            )
        }
        let result = AttachmentMimePolicyService.validate(attachments: selectedAttachments, policy: policy)

        switch result {
        case .accepted:
            return true
        case .rejected(let failures):
            attachmentSendValidationMessage = AttachmentMimePolicyService.validationErrorMessage(
                failures: failures,
                policy: policy
            )
            return false
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

        // Handle /private command specially - it needs to create a private conversation
        if case .privateThread = command {
            handlePrivateThreadCommand()
            return
        }

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
            // Slash command results are ephemeral context - they help Axon but don't need permanent storage
            // If persistence is desired, use LocalConversationStore.shared.saveLocalMessage()
        }
    }

    /// Handle /private command - creates a private thread where AI won't respond
    private func handlePrivateThreadCommand() {
        // /private can only be used as the first message in a new conversation
        // Allow if: no conversation exists, OR conversation exists but has no messages yet
        if conversation != nil && !conversationService.messages.isEmpty {
            // Already in a conversation with messages - show error
            let errorMessage = Message(
                conversationId: conversation?.id ?? "temp",
                role: .assistant,
                content: """
                ⚠️ **Cannot make this thread private**

                The `/private` command can only be used when starting a new conversation.

                This thread already has messages, so it cannot be converted to private mode.

                To create a private thread, start a new chat and type `/private` as your first message.
                """,
                modelName: "System",
                providerName: "internal"
            )
            conversationService.messages.append(errorMessage)
            return
        }

        // Create a new private conversation, or convert existing empty conversation to private
        Task {
            do {
                showWelcome = false

                let privateConv: Conversation
                let privateConvWithFlag: Conversation

                if let existingConv = conversation {
                    // Convert existing empty conversation to private
                    privateConv = existingConv

                    // Mark as private in UserDefaults (persists the private flag)
                    Self.setConversationPrivate(privateConv.id, isPrivate: true)

                    // Update the title to indicate it's private
                    try LocalConversationStore.shared.updateLocalConversation(
                        id: privateConv.id,
                        title: "🔒 Private Notes"
                    )

                    // Create a version with isPrivate set for in-memory use
                    privateConvWithFlag = Conversation(
                        id: privateConv.id,
                        userId: privateConv.userId,
                        title: "🔒 Private Notes",
                        projectId: privateConv.projectId,
                        createdAt: privateConv.createdAt,
                        updatedAt: privateConv.updatedAt,
                        messageCount: privateConv.messageCount,
                        lastMessageAt: privateConv.lastMessageAt,
                        archived: privateConv.archived,
                        summary: privateConv.summary,
                        lastMessage: privateConv.lastMessage,
                        tags: privateConv.tags,
                        isPinned: privateConv.isPinned,
                        isPrivate: true
                    )

                    // Update UI with the private-flagged conversation
                    onConversationCreated(privateConvWithFlag)

                    print("[ChatContainer] Converted existing conversation to private: \(privateConv.id)")
                } else {
                    // Create new private conversation locally
                    privateConv = try LocalConversationStore.shared.createLocalConversation(
                        title: "🔒 Private Notes",
                        projectId: "default"
                    )

                    // Mark as private in UserDefaults (persists the private flag)
                    Self.setConversationPrivate(privateConv.id, isPrivate: true)

                    // Create a version with isPrivate set for in-memory use
                    privateConvWithFlag = Conversation(
                        id: privateConv.id,
                        userId: privateConv.userId,
                        title: privateConv.title,
                        projectId: privateConv.projectId,
                        createdAt: privateConv.createdAt,
                        updatedAt: privateConv.updatedAt,
                        messageCount: privateConv.messageCount,
                        lastMessageAt: privateConv.lastMessageAt,
                        archived: privateConv.archived,
                        summary: privateConv.summary,
                        lastMessage: privateConv.lastMessage,
                        tags: privateConv.tags,
                        isPinned: privateConv.isPinned,
                        isPrivate: true
                    )

                    // Update UI
                    onConversationCreated(privateConvWithFlag)

                    print("[ChatContainer] Created new private thread: \(privateConv.id)")
                }

                // Add welcome message
                let welcomeMessage = Message(
                    conversationId: privateConv.id,
                    role: .assistant,
                    content: """
                    🔒 **Private Thread Started**

                    This thread is now private. Axon will not respond to messages here.

                    Use this space for:
                    - Personal notes and drafts
                    - Thinking out loud
                    - Storing information for later

                    *All messages in this thread are stored locally on your device.*
                    """,
                    modelName: "System",
                    providerName: "internal"
                )
                conversationService.messages.append(welcomeMessage)

                // Save the welcome message
                try await ConversationSyncManager.shared.saveMessagesToCoreData([welcomeMessage], conversationId: privateConv.id)
            } catch {
                print("[ChatContainer] Failed to create private thread: \(error)")
                let errorMessage = Message(
                    conversationId: "temp",
                    role: .assistant,
                    content: "Failed to create private thread: \(error.localizedDescription)",
                    modelName: "System",
                    providerName: "internal"
                )
                conversationService.messages.append(errorMessage)
            }
        }
    }

    /// Check if a conversation is marked as private
    static func isConversationPrivate(_ conversationId: String) -> Bool {
        UserDefaults.standard.bool(forKey: "private_thread_\(conversationId)")
    }

    /// Mark a conversation as private
    static func setConversationPrivate(_ conversationId: String, isPrivate: Bool) {
        UserDefaults.standard.set(isPrivate, forKey: "private_thread_\(conversationId)")
    }

    /// Send a message in a private thread (no AI response)
    private func sendPrivateMessage(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment]
    ) async throws {
        // Create user message
        let userMessage = Message(
            conversationId: conversationId,
            role: .user,
            content: content,
            attachments: attachments.isEmpty ? nil : attachments
        )

        // Add to UI
        conversationService.messages.append(userMessage)

        // Save to Core Data
        try await ConversationSyncManager.shared.saveMessagesToCoreData([userMessage], conversationId: conversationId)

        print("[ChatContainer] Saved private message to thread: \(conversationId)")

        // No AI response - just clean up
        await MainActor.run {
            isLoading = false
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

        // Get provider and model info - use ConversationModelResolver to respect conversation overrides
        let resolved = ConversationModelResolver.resolve(conversationId: conversationId, settings: settings)
        var providerString = resolved.normalizedProvider  // This handles xai -> grok mapping
        var modelId = resolved.modelId
        var providerDisplayName = resolved.providerName
        let runtimeOverrides = ConversationRuntimeOverrideManager.shared.resolve(
            conversationId: conversationId,
            baseProvider: providerString,
            baseModel: modelId,
            baseProviderDisplayName: providerDisplayName,
            baseModelParams: settings.modelGenerationSettings
        )
        providerString = runtimeOverrides.provider
        modelId = runtimeOverrides.model
        providerDisplayName = runtimeOverrides.providerDisplayName
        let resolvedModelParams = runtimeOverrides.modelParams

        // Pre-flight check: Verify built-in providers (Apple Intelligence, MLX) are available
        // This prevents the "generating forever" issue when the provider can't actually respond
        // Only check for built-in providers that have availability requirements
        let availabilityProviderRaw = providerString == "grok" ? "xai" : providerString
        let resolvedBuiltInProvider = AIProvider(rawValue: availabilityProviderRaw)
        if let builtInProvider = resolvedBuiltInProvider, !builtInProvider.isAvailable {
            let reason = builtInProvider.unavailableReason ?? "Provider is not available on this device"
            let guidance: String
            switch builtInProvider {
            case .appleFoundation:
                guidance = """
                **Apple Intelligence is not available.**

                \(reason)

                **To fix this:**
                1. Go to **Settings > Apple Intelligence & Siri**
                2. Enable Apple Intelligence and complete setup
                3. Wait for the on-device model to download

                Alternatively, configure an API key in Axon Settings to use a cloud provider.
                """
            case .localMLX:
                guidance = """
                **On-device MLX models are not available.**

                \(reason)

                MLX requires a physical iPhone or iPad with Apple Silicon. The iOS Simulator cannot run Metal-based models.

                Please run on a physical device, or switch to a cloud provider in Settings.
                """
            default:
                guidance = "⚠️ \(reason)"
            }

            // Show error message immediately instead of starting a failing stream
            let errorMessage = Message(
                conversationId: conversationId,
                role: .assistant,
                content: guidance,
                modelName: "System",
                providerName: "internal"
            )
            conversationService.messages.append(errorMessage)
            return
        }

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

        // Get custom provider config if needed - check conversation overrides first
        var customBaseUrl: String? = nil
        var customApiKey: String? = nil
        if providerString == "openai-compatible" {
            // Get custom provider ID from conversation overrides or global settings
            let overridesKey = "conversation_overrides_\(conversationId)"
            var customProviderId: UUID? = nil

            // Check conversation overrides first
            if let data = UserDefaults.standard.data(forKey: overridesKey),
               let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {
                customProviderId = overrides.customProviderId
            } else {
                // Fall back to global settings
                customProviderId = settings.selectedCustomProviderId
            }

            // Get custom provider config and API key
            if let providerId = customProviderId,
               let customProvider = settings.customProviders.first(where: { $0.id == providerId }) {
                customBaseUrl = customProvider.apiEndpoint
                if let apiKey = try? apiKeysStorage.getCustomProviderAPIKey(providerId: providerId), !apiKey.isEmpty {
                    customApiKey = apiKey
                }
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
            customApiKey: customApiKey,
            modelParams: resolvedModelParams
        )

        // Get all messages for context
        let contextMessages = conversationService.messages.filter { $0.id != assistantId }

        // Stream the response
        print("[ChatContainer] Starting streaming: provider=\(config.provider) model=\(config.model) conv=\(conversationId)")
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

        var didReceiveAnyDelta = false
        var didReceiveProviderError = false

        for try await event in stream {
            try Task.checkCancellation()

            await MainActor.run {
                switch event {
                case .textDelta(let text):
                    if !didReceiveAnyDelta {
                        didReceiveAnyDelta = true
                        print("[ChatContainer] First text delta received for \(assistantId)")
                    }
                    finalContent += text
                    streamedContent[assistantId] = finalContent

                case .reasoningDelta(let text):
                    if !didReceiveAnyDelta {
                        didReceiveAnyDelta = true
                        print("[ChatContainer] First reasoning delta received for \(assistantId)")
                    }
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
                    // SAFETY: never overwrite our locally accumulated deltas with a shorter completion payload.
                    // Some providers / fast models can emit a completion event whose fullContent is stale.
                    if completion.fullContent.count > finalContent.count {
                        finalContent = completion.fullContent
                    } else if completion.fullContent.count < finalContent.count {
                        print("[Streaming] Completion fullContent shorter than accumulated deltas (completion=\(completion.fullContent.count), accumulated=\(finalContent.count)). Keeping accumulated.")
                    }

                    if let completionReasoning = completion.reasoning, !completionReasoning.isEmpty {
                        finalReasoning = completionReasoning
                    }
                    finalSources = completion.groundingSources
                    finalMemoryOps = completion.memoryOperations
                    // Store context debug info if available
                    if let debugInfo = completion.contextDebugInfo {
                        contextDebugInfos[assistantId] = debugInfo
                    }

                case .error(let error):
                    print("[ChatContainer] Streaming error: \(error.localizedDescription)")
                    didReceiveProviderError = true
                    // Surface streaming errors to the user instead of silent failure
                    let errorText = error.localizedDescription
                    if finalContent.isEmpty {
                        // If we haven't received any content yet, this is likely a provider issue
                        finalContent = "⚠️ **Request failed**: \(errorText)\n\nCheck your provider settings or try a different model."
                    }
                }
            }
        }

        // If streaming ended but we never received any deltas, surface a visible error.
        if !didReceiveAnyDelta && finalContent.isEmpty && finalReasoning.isEmpty && !didReceiveProviderError {
            // Provide more actionable guidance based on the provider
            let providerGuidance: String
            if config.provider == "appleFoundation" {
                providerGuidance = """
                ⚠️ **Apple Intelligence did not respond.**

                This can happen if:
                • Apple Intelligence is not enabled on this device
                • The on-device model is still downloading
                • This device doesn't support Apple Intelligence

                **To fix:** Go to Settings > Apple Intelligence & Siri and ensure it's fully set up.
                """
            } else if config.provider == "localMLX" {
                providerGuidance = """
                ⚠️ **MLX model did not respond.**

                On-device models require a physical device with Apple Silicon. The Simulator cannot run Metal-based inference.
                """
            } else {
                providerGuidance = "⚠️ No response received from \(config.providerName).\n\nThis may be a network issue or provider outage. Try again or check your API key."
            }

            await MainActor.run {
                finalizeStreamingMessage(
                    assistantId: assistantId,
                    conversationId: conversationId,
                    content: providerGuidance,
                    reasoning: nil,
                    toolCalls: [],
                    sources: [],
                    memoryOps: [],
                    modelName: config.model,
                    providerName: config.providerName,
                    triggerSubconsciousLogging: false
                )
                // Clear first-message flag on error path
                isFirstMessageSending = false
            }
            return
        }

        let shouldConsumeTurnLease = !didReceiveProviderError && (
            !finalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !finalReasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )

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
                providerName: config.providerName,
                triggerSubconsciousLogging: shouldConsumeTurnLease
            )
            if shouldConsumeTurnLease {
                ConversationRuntimeOverrideManager.shared.consumeTurnLeaseOnSuccessfulReply(conversationId: conversationId)
            }
            // Clear first-message flag after streaming completes
            isFirstMessageSending = false
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
        providerName: String?,
        triggerSubconsciousLogging: Bool = false
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

            // Notify temporal service of message (session tracking, context saturation)
            // Turn counts are derived from Core Data automatically
            let contextTokens = contextDebugInfo?.totalTokens ?? 0
            let contextLimit = contextDebugInfo?.contextWindowLimit ?? 128_000
            TemporalContextService.shared.notifyMessageAdded(
                conversationId: conversationId,
                contextTokens: contextTokens,
                contextLimit: contextLimit
            )

            if triggerSubconsciousLogging {
                memoryService.enqueuePostTurnLogging(
                    conversationId: conversationId,
                    messages: conversationService.messages
                )
            }
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

    // MARK: - Temporal Context Helpers

    /// Get current context saturation for the temporal status bar
    private func getContextSaturation(for messageId: String? = nil) -> Double {
        // Try to get from the specified message's debug info, or latest
        let targetId = messageId ?? conversationService.messages.last?.id
        if let id = targetId, let debugInfo = contextDebugInfos[id] {
            return debugInfo.usagePercentage
        }

        // Fallback: estimate based on message count
        let messageCount = conversationService.messages.count
        let estimatedTokensPerMessage = 200
        let contextLimit = getContextLimit()
        let estimated = Double(messageCount * estimatedTokensPerMessage) / Double(contextLimit)
        return min(estimated, 1.0)
    }

    /// Get context window limit for current model
    private func getContextLimit(for messageId: String? = nil) -> Int {
        // Try to get from the specified message's debug info
        let targetId = messageId ?? conversationService.messages.last?.id
        if let id = targetId, let debugInfo = contextDebugInfos[id] {
            return debugInfo.contextWindowLimit
        }

        // Fallback: get from settings
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        return AIProvider.contextWindowForModel(settings.defaultModel, settings: settings)
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.signalMercury.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTypography.bodyMedium(.medium))
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.substrateSecondary.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.glassBorder.opacity(0.8), lineWidth: 1)
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
            .frame(minHeight: ChatVisualTokens.minTouchTarget)
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
        .accessibilityLabel("Jump to latest message")
    }
}

struct SubconsciousLoggingWarningBanner: View {
    let message: String
    let onClose: () -> Void
    let onIgnoreThread: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accentWarning)

                Text("Subconscious Memory Logging")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.accentWarning)
            }

            Text(message)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Close", action: onClose)
                    .buttonStyle(.plain)
                    .font(AppTypography.labelSmall(.medium))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.glassBorder, lineWidth: 1)
                    )

                Button("Ignore This Thread", action: onIgnoreThread)
                    .buttonStyle(.plain)
                    .font(AppTypography.labelSmall(.medium))
                    .foregroundColor(AppColors.accentWarning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.accentWarning.opacity(0.6), lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.accentWarning.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.accentWarning.opacity(0.35), lineWidth: 1)
                )
        )
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
