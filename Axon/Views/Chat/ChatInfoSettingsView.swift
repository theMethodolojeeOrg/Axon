//
//  ChatInfoSettingsView.swift
//  Axon
//
//  Per-conversation info and settings view
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ChatInfoSettingsView: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var costService = CostService.shared
    @ObservedObject private var sovereigntyService = SovereigntyService.shared
    #if os(macOS)
    @ObservedObject private var bridgeServer = BridgeServer.shared
    #else
    @ObservedObject private var bridgeManager = BridgeConnectionManager.shared
    @ObservedObject private var bridgeSettings = BridgeSettingsStorage.shared
    #endif

    // Per-conversation overrides (stored locally)
    @State private var selectedProvider: UnifiedProvider?
    @State private var selectedModel: UnifiedModel?
    @State private var estimatedTokens: Int = 0

    // Negotiation sheet
    @State private var showingNegotiationSheet = false

    // Export/share
    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil
    @State private var exportedFileURL: URL? = nil
    @State private var exportedShareItems: [Any] = []
    @State private var showingIOSShareSheet = false

    // Whether this conversation has custom overrides (vs using defaults)
    @State private var hasCustomOverrides: Bool = false

    // Track enabled tools locally for this conversation (per-chat override)
    @State private var localEnabledTools: Set<String> = []

    // Whether tool settings have been customized for this conversation
    @State private var hasCustomToolOverrides: Bool = false

    // Realtime Voice Overrides
    @State private var selectedLiveProvider: String?
    @State private var selectedLiveModel: String?
    @State private var selectedLiveVoice: String?

    // iOS Remote Mode connection state
    #if !os(macOS)
    @State private var remoteHost: String = ""
    @State private var remotePort: String = "8082"
    #endif

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    #if os(macOS)
    private var macOSBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    Text("Chat Settings")
                        .font(AppTypography.titleLarge())
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.signalMercury)
                }
                .padding(.bottom, 8)

                mainContent
            }
            .padding(24)
        }
        .background(AppColors.substratePrimary)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 500, idealHeight: 600)
        .task {
            loadConversationOverrides()
            loadEnabledTools()
            await estimateTokenCount()
        }
    }
    #endif

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    mainContent
                }
                .padding()
            }
            .background(AppColors.substratePrimary)
            .navigationTitle("Chat Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.signalMercury)
                }
            }
        }
        .task {
            loadConversationOverrides()
            loadEnabledTools()
            await estimateTokenCount()
            loadRemoteModeSettings()
        }
    }

    private func loadRemoteModeSettings() {
        remoteHost = bridgeSettings.settings.remoteHost
        remotePort = String(bridgeSettings.settings.remotePort)
    }
    #endif

    @ViewBuilder
    private var mainContent: some View {
        // MARK: - Provider Selection
        ChatInfoSection(title: "AI Provider") {
            let allProviders = settingsViewModel.selectableUnifiedProviders()
            let currentProvider = (selectedProvider ?? settingsViewModel.currentUnifiedProvider()).flatMap { provider in
                if allProviders.contains(where: { $0.id == provider.id }) {
                    return provider
                }
                return settingsViewModel.fallbackUnifiedProvider()
            } ?? settingsViewModel.fallbackUnifiedProvider()
            let isProviderChangeAllowed = sovereigntyService.isProviderChangeAllowed()
            let providerRestrictionReason = sovereigntyService.providerChangeRestrictionReason()

            // Show restriction banner if provider changes are restricted by covenant
            if !isProviderChangeAllowed, let reason = providerRestrictionReason {
                CovenantRestrictionBanner(
                    icon: "lock.shield",
                    message: reason,
                    actionLabel: "Renegotiate",
                    action: {
                        showingNegotiationSheet = true
                    }
                )
            }

            StyledMenuPicker(
                icon: currentProvider?.isCustom == true ? "server.rack" : "cpu.fill",
                title: currentProvider?.displayName ?? "Select Provider",
                selection: Binding(
                    get: { currentProvider?.id ?? "builtin_anthropic" },
                    set: { newProviderId in
                        selectProvider(allProviders.first(where: { $0.id == newProviderId }))
                    }
                )
            ) {
                #if os(macOS)
                Section("Built-in Providers") {
                    ForEach(AIProvider.allCases.filter { settingsViewModel.isBuiltInProviderSelectable($0) }) { provider in
                        MenuButtonItem(
                            id: "builtin_\(provider.rawValue)",
                            label: provider.displayName,
                            isSelected: currentProvider?.id == "builtin_\(provider.rawValue)"
                        ) {
                            selectProvider(allProviders.first(where: { $0.id == "builtin_\(provider.rawValue)" }))
                        }
                    }
                }

                let selectableCustomProviders = settingsViewModel.settings.customProviders.filter { settingsViewModel.isCustomProviderSelectable($0.id) }
                if !selectableCustomProviders.isEmpty {
                    Section("Custom Providers") {
                        ForEach(selectableCustomProviders) { provider in
                            MenuButtonItem(
                                id: "custom_\(provider.id.uuidString)",
                                label: provider.providerName,
                                isSelected: currentProvider?.id == "custom_\(provider.id.uuidString)"
                            ) {
                                selectProvider(allProviders.first(where: { $0.id == "custom_\(provider.id.uuidString)" }))
                            }
                        }
                    }
                }
                #else
                Section("Built-in Providers") {
                    ForEach(AIProvider.allCases.filter { settingsViewModel.isBuiltInProviderSelectable($0) }) { provider in
                        Text(provider.displayName).tag("builtin_\(provider.rawValue)")
                    }
                }

                let selectableCustomProviders = settingsViewModel.settings.customProviders.filter { settingsViewModel.isCustomProviderSelectable($0.id) }
                if !selectableCustomProviders.isEmpty {
                    Section("Custom Providers") {
                        ForEach(selectableCustomProviders) { provider in
                            Text(provider.providerName).tag("custom_\(provider.id.uuidString)")
                        }
                    }
                }
                #endif
            }
            .disabled(!isProviderChangeAllowed)
            .opacity(isProviderChangeAllowed ? 1.0 : 0.6)
        }

        // MARK: - Model Selection
        ChatInfoSection(title: "Model") {
            if let provider = selectedProvider ?? settingsViewModel.currentUnifiedProvider() {
                let providerIndex = settingsViewModel.settings.customProviders.firstIndex(where: {
                    if case .custom(let config) = provider {
                        return $0.id == config.id
                    }
                    return false
                }) ?? 0
                let availableModels = provider.availableModels(customProviderIndex: providerIndex + 1)
                let currentModel = selectedModel ?? availableModels.first

                // Filter models by context window if we have token estimate
                let validModels = availableModels.filter { model in
                    estimatedTokens == 0 || model.contextWindow >= estimatedTokens
                }
                let insufficientModels = availableModels.filter { !validModels.contains($0) }

                StyledMenuPicker(
                    icon: "brain.head.profile",
                    title: currentModel?.name ?? "Select Model",
                    selection: Binding(
                        get: { currentModel?.id ?? "" },
                        set: { newModelId in
                            if let model = availableModels.first(where: { $0.id == newModelId }) {
                                selectModel(model)
                            }
                        }
                    )
                ) {
                    #if os(macOS)
                    ForEach(validModels) { model in
                        MenuButtonItem(
                            id: model.id,
                            label: model.name,
                            isSelected: currentModel?.id == model.id
                        ) {
                            selectModel(model)
                        }
                    }

                    if !validModels.isEmpty && !insufficientModels.isEmpty {
                        Section("Insufficient Context") {
                            ForEach(insufficientModels) { model in
                                Button {
                                    selectModel(model)
                                } label: {
                                    Text("\(model.name) (needs \(model.contextWindow / 1000)K)")
                                }
                                .disabled(true)
                            }
                        }
                    }
                    #else
                    ForEach(validModels) { model in
                        Text(model.name).tag(model.id)
                    }

                    if !validModels.isEmpty && !insufficientModels.isEmpty {
                        Section("Insufficient Context") {
                            ForEach(insufficientModels) { model in
                                Text("\(model.name) (needs \(model.contextWindow / 1000)K)")
                                    .tag(model.id)
                                    .foregroundColor(AppColors.textDisabled)
                            }
                        }
                    }
                    #endif
                }
            }
        }

        // MARK: - Context Window Progress
        ChatInfoSection(title: "Context Usage") {
            if let model = selectedModel ?? settingsViewModel.currentUnifiedModel() {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("This Conversation")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)

                        Spacer()

                        Text("\(formatNumber(estimatedTokens)) / \(formatNumber(model.contextWindow))")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.substrateTertiary)
                                .frame(height: 12)

                            // Fill
                            RoundedRectangle(cornerRadius: 8)
                                .fill(progressColor)
                                .frame(width: geometry.size.width * progressPercentage, height: 12)
                        }
                    }
                    .frame(height: 12)

                    Text("\(formattedProgressPercentage) of context window used")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
        }

        // MARK: - Realtime Voice
        ChatInfoSection(title: "Realtime Voice") {
            VStack(spacing: 16) {
                // Live Provider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)

                    Menu {
                        Button("Default (\(settingsViewModel.settings.liveSettings.defaultProvider == .openai ? "OpenAI" : "Gemini"))") {
                            selectedLiveProvider = nil
                            selectedLiveModel = nil
                            selectedLiveVoice = nil
                            saveConversationOverrides()
                        }
                        Divider()
                        Button("Gemini Live") {
                            selectedLiveProvider = "gemini"
                            saveConversationOverrides()
                        }
                        Button("OpenAI Realtime") {
                            selectedLiveProvider = "openai"
                            saveConversationOverrides()
                        }
                    } label: {
                        HStack {
                            Text(selectedLiveProvider == "openai" ? "OpenAI Realtime" :
                                 selectedLiveProvider == "gemini" ? "Gemini Live" :
                                 "Default (\(settingsViewModel.settings.liveSettings.defaultProvider == .openai ? "OpenAI" : "Gemini"))")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .padding(12)
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                // Voice Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)

                    Menu {
                        Button("Default") {
                            selectedLiveVoice = nil
                            saveConversationOverrides()
                        }
                        Divider()
                        if (selectedLiveProvider == "openai") || (selectedLiveProvider == nil && settingsViewModel.settings.liveSettings.defaultProvider == .openai) {
                            Button("Alloy") { selectedLiveVoice = "alloy"; saveConversationOverrides() }
                            Button("Ash") { selectedLiveVoice = "ash"; saveConversationOverrides() }
                            Button("Ballad") { selectedLiveVoice = "ballad"; saveConversationOverrides() }
                            Button("Coral") { selectedLiveVoice = "coral"; saveConversationOverrides() }
                            Button("Echo") { selectedLiveVoice = "echo"; saveConversationOverrides() }
                            Button("Sage") { selectedLiveVoice = "sage"; saveConversationOverrides() }
                            Button("Shimmer") { selectedLiveVoice = "shimmer"; saveConversationOverrides() }
                            Button("Verse") { selectedLiveVoice = "verse"; saveConversationOverrides() }
                            Button("Marin") { selectedLiveVoice = "marin"; saveConversationOverrides() }
                        } else {
                            // Gemini voices
                            Button("Kore") { selectedLiveVoice = "Kore"; saveConversationOverrides() }
                            Button("Leda") { selectedLiveVoice = "Leda"; saveConversationOverrides() }
                            Button("Puck") { selectedLiveVoice = "Puck"; saveConversationOverrides() }
                            Button("Charon") { selectedLiveVoice = "Charon"; saveConversationOverrides() }
                            Button("Fenrir") { selectedLiveVoice = "Fenrir"; saveConversationOverrides() }
                            Button("Orus") { selectedLiveVoice = "Orus"; saveConversationOverrides() }
                            Button("Aoede") { selectedLiveVoice = "Aoede"; saveConversationOverrides() }
                            Button("Callirrhoe") { selectedLiveVoice = "Callirrhoe"; saveConversationOverrides() }
                            Button("Zenir") { selectedLiveVoice = "Zenir"; saveConversationOverrides() }
                        }
                    } label: {
                        HStack {
                            Text(selectedLiveVoice ?? "Default")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .padding(12)
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // MARK: - Cost Information
        ChatInfoSection(title: "Costs") {
            VStack(spacing: 12) {
                // Total this month
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Month")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                        Text(costService.totalThisMonthUSDFriendly)
                            .font(AppTypography.titleMedium())
                            .foregroundColor(AppColors.textPrimary)
                    }

                    Spacer()

                    #if !os(macOS)
                    NavigationLink(destination: CostsBreakdownView()) {
                        HStack(spacing: 6) {
                            Text("View Details")
                                .font(AppTypography.bodySmall())
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(AppColors.signalMercury)
                    }
                    #endif
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
        }

        // MARK: - Export
        ChatInfoSection(title: "Export") {
            VStack(spacing: 12) {
                exportButtonRow(
                    title: "Export JSON",
                    subtitle: "Full thread + metadata",
                    systemImage: "doc.text",
                    format: .json
                )

                exportButtonRow(
                    title: "Export Markdown",
                    subtitle: "Readable transcript",
                    systemImage: "doc.plaintext",
                    format: .markdown
                )

                exportButtonRow(
                    title: "Export ZIP",
                    subtitle: "JSON + MD + attachment payloads (when available)",
                    systemImage: "archivebox",
                    format: .zip
                )

                exportButtonRow(
                    title: "Session Audio (Cached)",
                    subtitle: "TTS audio stored on this device",
                    systemImage: "waveform",
                    format: .sessionAudioCached
                )

                exportButtonRow(
                    title: "Session Audio (All)",
                    subtitle: "Includes CloudKit audio when available",
                    systemImage: "waveform.and.arrow.down",
                    format: .sessionAudioAll
                )

                if let exportErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.accentError)

                        Text(exportErrorMessage)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.accentError)
                            .lineLimit(3)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.accentError.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }

        // MARK: - Tools Section
        ChatInfoSection(title: "Tools") {
            VStack(spacing: 16) {
                // Gemini Tools
                ChatInfoToolCategorySection(
                    title: "Google (Gemini)",
                    icon: "globe",
                    tools: ToolId.tools(for: .gemini),
                    enabledTools: localEnabledTools,
                    onToggle: { tool, enabled in toggleTool(tool, enabled: enabled) }
                )

                // OpenAI Tools
                ChatInfoToolCategorySection(
                    title: "OpenAI",
                    icon: "cpu",
                    tools: ToolId.tools(for: .openai),
                    enabledTools: localEnabledTools,
                    onToggle: { tool, enabled in toggleTool(tool, enabled: enabled) }
                )

                // Internal Tools (grouped by category)
                let internalCategories = ToolCategory.allCases.filter { category in
                    category != .geminiTools && category != .openaiTools && !ToolId.tools(for: category).isEmpty
                }

                ForEach(internalCategories) { category in
                    ChatInfoToolCategorySection(
                        title: category.displayName,
                        icon: category.icon,
                        tools: ToolId.tools(for: category),
                        enabledTools: localEnabledTools,
                        onToggle: { tool, enabled in toggleTool(tool, enabled: enabled) }
                    )
                }

                #if os(macOS)
                // VS Code Bridge status (macOS only)
                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    Image(systemName: bridgeServer.isConnected ? "personalhotspot" : "personalhotspot.slash")
                        .font(.system(size: 16))
                        .foregroundColor(bridgeServer.isConnected ? AppColors.signalLichen : AppColors.textTertiary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("VS Code Bridge")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if let session = bridgeServer.connectedSession {
                            Text(session.workspaceName)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalLichen)
                        } else if bridgeServer.isRunning {
                            Text("Waiting for connection...")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        } else {
                            Text("Not running")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    Spacer()

                    // Connection status indicator
                    Circle()
                        .fill(bridgeServer.isConnected ? AppColors.signalLichen : (bridgeServer.isRunning ? AppColors.accentWarning : AppColors.textTertiary))
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
                #else
                // VS Code Bridge (Remote Mode) for iOS
                Divider()
                    .padding(.vertical, 4)

                remoteBridgeSection
                #endif
            }
        }

        // MARK: - Info Note
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundColor(AppColors.signalMercury)
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Switching")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                Text("Changing the model sends the entire conversation history to the new model for continuity. Costs are tracked globally across all conversations and providers.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(AppColors.signalMercury.opacity(0.1))
        .cornerRadius(8)
        .sheet(isPresented: $showingNegotiationSheet) {
            CovenantNegotiationView(preselectedCategory: .providerChange)
                #if os(macOS)
                .frame(minWidth: 550, idealWidth: 650, minHeight: 600, idealHeight: 800)
                #endif
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showingIOSShareSheet) {
            if let exportedFileURL {
                ActivityView(activityItems: [exportedFileURL])
            } else {
                EmptyView()
            }
        }
        #endif
        // macOS SharePicker anchor view (shows when `exportedShareItems` changes)
        #if os(macOS)
        MacSharePicker(items: exportedShareItems)
            .frame(width: 0, height: 0)
        #endif
    }

    // MARK: - iOS Remote Bridge Section

    #if !os(macOS)
    @ViewBuilder
    private var remoteBridgeSection: some View {
        VStack(spacing: 12) {
            // Connection Status Header
            HStack(spacing: 12) {
                Image(systemName: bridgeStatusIcon)
                    .font(.system(size: 16))
                    .foregroundColor(bridgeStatusColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("VS Code Bridge")
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(bridgeStatusText)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(bridgeStatusColor)
                }

                Spacer()

                // Connection status indicator
                Circle()
                    .fill(bridgeStatusColor)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)

            // Server Address Inputs (only show when not connected)
            if !bridgeManager.isConnected {
                VStack(spacing: 8) {
                    // Host input
                    HStack {
                        Image(systemName: "network")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textTertiary)
                            .frame(width: 24)

                        TextField("VS Code IP (e.g., 192.168.1.100)", text: $remoteHost)
                            .font(AppTypography.bodySmall())
                            .textFieldStyle(.plain)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)

                    // Port input
                    HStack {
                        Image(systemName: "number")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textTertiary)
                            .frame(width: 24)

                        TextField("Port (default: 8082)", text: $remotePort)
                            .font(AppTypography.bodySmall())
                            .textFieldStyle(.plain)
                            .keyboardType(.numberPad)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
                }
            }

            // Connected Session Info
            if let session = bridgeManager.connectedSession {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.signalLichen)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.workspaceName)
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text(session.workspaceRoot)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }

            // Error Message
            if let error = bridgeManager.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.accentError)

                    Text(error)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.accentError)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.accentError.opacity(0.1))
                .cornerRadius(8)
            }

            // Connect/Disconnect Button
            Button {
                Task {
                    await toggleRemoteConnection()
                }
            } label: {
                HStack {
                    if bridgeManager.isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: bridgeManager.isConnected ? "xmark.circle" : "link")
                    }

                    Text(bridgeButtonText)
                        .font(AppTypography.bodySmall(.medium))
                }
                .foregroundColor(bridgeManager.isConnected ? AppColors.accentError : AppColors.signalMercury)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    (bridgeManager.isConnected ? AppColors.accentError : AppColors.signalMercury)
                        .opacity(0.15)
                )
                .cornerRadius(8)
            }
            .disabled(bridgeManager.isConnecting || (!bridgeManager.isConnected && remoteHost.isEmpty))
        }
    }

    // MARK: - Remote Bridge Helpers

    private var bridgeStatusIcon: String {
        if bridgeManager.isConnected {
            return "personalhotspot"
        } else if bridgeManager.isConnecting {
            return "antenna.radiowaves.left.and.right"
        } else {
            return "personalhotspot.slash"
        }
    }

    private var bridgeStatusColor: Color {
        if bridgeManager.isConnected {
            return AppColors.signalLichen
        } else if bridgeManager.isConnecting {
            return AppColors.accentWarning
        } else {
            return AppColors.textTertiary
        }
    }

    private var bridgeStatusText: String {
        if bridgeManager.isConnected {
            if let session = bridgeManager.connectedSession {
                return "Connected to \(session.workspaceName)"
            }
            return "Connected"
        } else if bridgeManager.isConnecting {
            return "Connecting..."
        } else {
            return "Not connected"
        }
    }

    private var bridgeButtonText: String {
        if bridgeManager.isConnecting {
            return "Connecting..."
        } else if bridgeManager.isConnected {
            return "Disconnect"
        } else {
            return "Connect to VS Code"
        }
    }

    private func toggleRemoteConnection() async {
        if bridgeManager.isConnected {
            await bridgeManager.stop()
        } else {
            // Save settings
            let port = UInt16(remotePort) ?? 8082
            bridgeSettings.setRemoteConfig(host: remoteHost, port: port)

            // Ensure we're in remote mode
            await bridgeManager.setMode(.remote)

            // Connect
            await bridgeManager.start()
        }
    }
    #endif

    // MARK: - Helpers

    private func selectProvider(_ provider: UnifiedProvider?) {
        guard let provider = provider else { return }
        selectedProvider = provider

        // Auto-select first model from new provider
        let providerIndex = settingsViewModel.settings.customProviders.firstIndex(where: {
            if case .custom(let config) = provider {
                return $0.id == config.id
            }
            return false
        }) ?? 0
        let models = provider.availableModels(customProviderIndex: providerIndex + 1)
        selectedModel = models.first

        saveConversationOverrides()
    }

    private func selectModel(_ model: UnifiedModel) {
        selectedModel = model
        saveConversationOverrides()
    }

    private var progressPercentage: Double {
        guard let model = selectedModel ?? settingsViewModel.currentUnifiedModel() else { return 0 }
        guard model.contextWindow > 0 else { return 0 }
        return min(Double(estimatedTokens) / Double(model.contextWindow), 1.0)
    }

    private var formattedProgressPercentage: String {
        let percent = progressPercentage * 100
        if percent == 0 {
            return "0%"
        } else if percent < 1 {
            return "<1%"
        } else {
            return "\(Int(round(percent)))%"
        }
    }

    private var progressColor: Color {
        let percentage = progressPercentage
        if percentage < 0.5 {
            return AppColors.accentSuccess
        } else if percentage < 0.8 {
            return AppColors.accentWarning
        } else {
            return AppColors.accentError
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }

    private func exportButtonRow(
        title: String,
        subtitle: String,
        systemImage: String,
        format: ChatExportService.ExportFormat
    ) -> some View {
        Button {
            Task { @MainActor in
                await exportAndShare(format: format)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(subtitle)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }

                Spacer()

                if isExporting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
    }

    @MainActor
    private func exportAndShare(format: ChatExportService.ExportFormat) async {
        exportErrorMessage = nil
        isExporting = true
        defer { isExporting = false }

        do {
            let exported = try await ChatExportService.shared.exportFile(for: conversation, format: format)
            exportedFileURL = exported.url

            #if os(macOS)
            // macOS: offer both Save As… and Share.
            // 1) Save panel
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = exported.suggestedFilename
            panel.allowedFileTypes = [exported.url.pathExtension]

            panel.begin { response in
                guard response == .OK, let destination = panel.url else { return }
                do {
                    try FileManager.default.copyItem(at: exported.url, to: destination)
                } catch {
                    // If file exists, overwrite
                    do {
                        try? FileManager.default.removeItem(at: destination)
                        try FileManager.default.copyItem(at: exported.url, to: destination)
                    } catch {
                        exportErrorMessage = error.localizedDescription
                    }
                }

                // 2) Share picker (shares the saved file if we have it, else temp file)
                exportedShareItems = [destination]
            }
            #else
            // iOS: share sheet
            showingIOSShareSheet = true
            #endif
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func estimateTokenCount() async {
        // Rough estimation: 4 characters per token
        // Use getMessages to ensure we're counting the right conversation.
        if let messages = try? await conversationService.getMessages(conversationId: conversation.id, limit: 10_000) {
            let totalCharacters = messages.reduce(0) { $0 + $1.content.count }
            estimatedTokens = max(1, totalCharacters / 4)
        } else {
            estimatedTokens = 0
        }
    }

    private func loadEnabledTools() {
        // Check for per-conversation tool overrides first
        let key = "conversation_overrides_\(conversation.id)"
        if let data = UserDefaults.standard.data(forKey: key),
           let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data),
           let toolOverrides = overrides.enabledToolIds {
            // Use per-conversation tool settings
            hasCustomToolOverrides = true
            localEnabledTools = toolOverrides
        } else {
            // Fall back to global defaults
            hasCustomToolOverrides = false
            localEnabledTools = settingsViewModel.settings.toolSettings.enabledToolIds
        }
    }

    private func toggleTool(_ tool: ToolId, enabled: Bool) {
        // Update local state immediately for UI
        if enabled {
            localEnabledTools.insert(tool.rawValue)
        } else {
            localEnabledTools.remove(tool.rawValue)
        }

        // Mark that we now have custom tool overrides for this conversation
        hasCustomToolOverrides = true

        // Save as per-conversation override (does NOT modify global settings)
        saveToolOverrides()
    }

    private func saveToolOverrides() {
        // Load existing overrides or create new ones
        let key = "conversation_overrides_\(conversation.id)"
        var overrides: ConversationOverrides

        if let data = UserDefaults.standard.data(forKey: key),
           let existingOverrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {
            overrides = existingOverrides
        } else {
            overrides = ConversationOverrides()
        }

        // Update tool settings
        overrides.enabledToolIds = localEnabledTools

        // Persist
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadConversationOverrides() {
        // Check for per-conversation overrides in UserDefaults
        let key = "conversation_overrides_\(conversation.id)"
        if let data = UserDefaults.standard.data(forKey: key),
           let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {

            hasCustomOverrides = true

            // Restore provider from override
            if let customProviderId = overrides.customProviderId,
               let customProvider = settingsViewModel.settings.customProviders.first(where: { $0.id == customProviderId }) {
                selectedProvider = .custom(customProvider)
            } else if let builtInProvider = AIProvider(rawValue: overrides.builtInProvider ?? "") {
                selectedProvider = .builtIn(builtInProvider)
            }

            // Restore model from override
            if let provider = selectedProvider {
                let providerIndex = settingsViewModel.settings.customProviders.firstIndex(where: {
                    if case .custom(let config) = provider {
                        return $0.id == config.id
                    }
                    return false
                }) ?? 0
                let availableModels = provider.availableModels(customProviderIndex: providerIndex + 1)

                if let customModelId = overrides.customModelId {
                    selectedModel = availableModels.first(where: {
                        if case .custom(let config, _, _, _) = $0 {
                            return config.id == customModelId
                        }
                        return false
                    })
                } else if let builtInModel = overrides.builtInModel {
                    selectedModel = availableModels.first(where: {
                        if case .builtIn(let model) = $0 {
                            return model.id == builtInModel
                        }
                        return false
                    })
                }
            }

            // Restore Live settings
            selectedLiveProvider = overrides.liveProvider
            selectedLiveModel = overrides.liveModel
            selectedLiveVoice = overrides.liveVoice
        } else {
            // No overrides exist - initialize from global defaults
            hasCustomOverrides = false
            selectedProvider = settingsViewModel.currentUnifiedProvider()
            selectedModel = settingsViewModel.currentUnifiedModel()
            selectedLiveProvider = nil
            selectedLiveModel = nil
            selectedLiveVoice = nil
        }
    }

    private func saveConversationOverrides() {
        var overrides = ConversationOverrides()

        // Save provider
        if let provider = selectedProvider {
            switch provider {
            case .builtIn(let aiProvider):
                overrides.builtInProvider = aiProvider.rawValue
            case .custom(let config):
                overrides.customProviderId = config.id
            }
        }

        // Save provider display name for downstream UI (icons, labels)
        if let provider = selectedProvider {
            overrides.providerDisplayName = provider.displayName
        }

        // Save model
        if let model = selectedModel {
            switch model {
            case .builtIn(let aiModel):
                overrides.builtInModel = aiModel.id
            case .custom(let config, _, _, _):
                overrides.customModelId = config.id
            }
        }

        // Save model display name for downstream UI (icons, labels)
        if let model = selectedModel {
            overrides.modelDisplayName = model.name
        }

        // Save Live settings
        overrides.liveProvider = selectedLiveProvider
        overrides.liveModel = selectedLiveModel
        overrides.liveVoice = selectedLiveVoice

        // Persist to UserDefaults
        let key = "conversation_overrides_\(conversation.id)"
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Conversation Overrides Model

struct ConversationOverrides: Codable, Equatable {
    // Provider/Model Identifiers
    var builtInProvider: String?
    var customProviderId: UUID?
    var builtInModel: String?
    var customModelId: UUID?
    var model: String?

    // Realtime Live Session Overrides
    var liveProvider: String?
    var liveModel: String?
    var liveVoice: String?

    // Human-friendly metadata (optional)
    var providerDisplayName: String?
    var modelDisplayName: String?

    // Per-conversation tool settings
    // When nil, use global defaults. When set, these override for this conversation only.
    var enabledToolIds: Set<String>?
}

// MARK: - Chat Info Section Component

struct ChatInfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.headlineSmall())
                .foregroundColor(AppColors.textPrimary)

            content
        }
    }
}

// MARK: - Chat Info Tool Category Section (collapsible category)

struct ChatInfoToolCategorySection: View {
    let title: String
    let icon: String
    let tools: [ToolId]
    let enabledTools: Set<String>
    let onToggle: (ToolId, Bool) -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        if !tools.isEmpty {
            VStack(spacing: 0) {
                // Category Header (tappable to expand)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 24)

                        Text(title)
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        // Show count of enabled tools
                        let enabledCount = tools.filter { enabledTools.contains($0.rawValue) }.count
                        Text("\(enabledCount)/\(tools.count)")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(isExpanded ? 8 : 8)
                }
                .buttonStyle(.plain)

                // Expanded Tool List
                if isExpanded {
                    VStack(spacing: 1) {
                        ForEach(tools) { tool in
                            ChatInfoToolToggleRow(
                                tool: tool,
                                isEnabled: enabledTools.contains(tool.rawValue),
                                onToggle: { enabled in onToggle(tool, enabled) }
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Chat Info Tool Toggle Row (compact variant)

struct ChatInfoToolToggleRow: View {
    let tool: ToolId
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.system(size: 16))
                .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(tool.description)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(AppColors.signalMercury)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    ChatInfoSettingsView(conversation: Conversation(
        userId: "user1",
        title: "Test Conversation",
        projectId: "default", messageCount: 10
    ))
}
