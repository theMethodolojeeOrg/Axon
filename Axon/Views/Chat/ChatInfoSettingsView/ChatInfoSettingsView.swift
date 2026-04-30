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
    
    // Per-conversation overrides (stored locally)
    @State private var selectedProvider: UnifiedProvider?
    @State private var selectedModel: UnifiedModel?
    @State private var estimatedTokens: Int = 0
    
    // Negotiation sheet
    @State private var showingNegotiationSheet = false
    @State private var showingBridgeManager = false
    
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
        .background(AppSurfaces.color(.contentBackground))
        .frame(minWidth: 480, idealWidth: 520, minHeight: 500, idealHeight: 600)
        .task {
            loadConversationOverrides()
            loadEnabledTools()
            await estimateTokenCount()
        }
        .sheet(isPresented: $showingBridgeManager) {
            bridgeManagerSheet
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
            .background(AppSurfaces.color(.contentBackground))
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
        }
        .sheet(isPresented: $showingBridgeManager) {
            bridgeManagerSheet
        }
    }
    #endif
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        // MARK: - Provider Selection
        ChatProviderSelectionSection(
            settingsViewModel: settingsViewModel,
            selectedProvider: $selectedProvider,
            showingNegotiationSheet: $showingNegotiationSheet,
            onProviderSelected: { provider in
                selectProvider(provider)
            }
        )
        
        // MARK: - Model Selection
        ChatModelSelectionSection(
            settingsViewModel: settingsViewModel,
            provider: selectedProvider,
            selectedModel: $selectedModel,
            estimatedTokens: estimatedTokens,
            onModelSelected: { model in
                selectModel(model)
            }
        )
        
        // MARK: - Context Usage
        ContextUsageSection(
            model: selectedModel ?? settingsViewModel.currentUnifiedModel(),
            estimatedTokens: estimatedTokens
        )
        
        // MARK: - Realtime Voice
        RealtimeVoiceSection(
            settingsViewModel: settingsViewModel,
            selectedLiveProvider: $selectedLiveProvider,
            selectedLiveVoice: $selectedLiveVoice,
            onSave: saveConversationOverrides
        )
        
        // MARK: - Costs
        CostInfoSection()
        
        // MARK: - Export
        ExportSection(conversation: conversation)
        
        // MARK: - Tools
        ToolsSection(
            settingsViewModel: settingsViewModel,
            localEnabledTools: $localEnabledTools,
            onToggleTool: { tool, enabled in
                toggleTool(tool, enabled: enabled)
            }
        )
        
        ChatBridgeQuickCard(
            onManage: {
                showingBridgeManager = true
            }
        )
        
        // MARK: - Developer Console Quick Access
        DeveloperConsoleQuickAccess()
        
        // MARK: - Info Note
        infoNote
            .sheet(isPresented: $showingNegotiationSheet) {
                CovenantNegotiationView(preselectedCategory: .providerChange)
                    #if os(macOS)
                    .frame(minWidth: 550, idealWidth: 650, minHeight: 600, idealHeight: 800)
                    #endif
            }
    }
    
    // MARK: - Info Note
    
    private var infoNote: some View {
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
    }

    private var bridgeManagerSheet: some View {
        NavigationStack {
            SettingsSubviewContainer {
                AxonBridgeSettingsView()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingBridgeManager = false
                    }
                }
            }
        }
    }
    
    // MARK: - Provider/Model Selection
    
    private func selectProvider(_ provider: UnifiedProvider?) {
        guard let provider = provider else { return }
        selectedProvider = provider
        
        // Auto-select first model from new provider
        selectedModel = ProviderModelHelpers.selectProvider(provider, settingsViewModel: settingsViewModel)
        
        saveConversationOverrides()
    }
    
    private func selectModel(_ model: UnifiedModel) {
        selectedModel = model
        saveConversationOverrides()
    }
    
    // MARK: - Token Estimation
    
    private func estimateTokenCount() async {
        // Rough estimation: 4 characters per token
        if let messages = try? await conversationService.getMessages(conversationId: conversation.id, limit: 10_000) {
            let totalCharacters = messages.reduce(0) { $0 + $1.content.count }
            estimatedTokens = max(1, totalCharacters / 4)
        } else {
            estimatedTokens = 0
        }
    }
    
    // MARK: - Tool Management
    
    private func loadEnabledTools() {
        let (tools, hasOverrides) = ConversationOverridesManager.shared.loadEnabledTools(
            for: conversation.id,
            settingsViewModel: settingsViewModel
        )
        localEnabledTools = tools
        hasCustomToolOverrides = hasOverrides
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
        
        // Save as per-conversation override
        ConversationOverridesManager.shared.saveEnabledTools(localEnabledTools, for: conversation.id)
    }
    
    // MARK: - Conversation Overrides
    
    private func loadConversationOverrides() {
        let (provider, model, hasOverrides) = ConversationOverridesManager.shared.loadProviderAndModel(
            for: conversation.id,
            settingsViewModel: settingsViewModel
        )
        
        selectedProvider = provider
        selectedModel = model
        hasCustomOverrides = hasOverrides
        
        // Load live settings
        let (liveProvider, liveModel, liveVoice) = ConversationOverridesManager.shared.loadLiveSettings(
            for: conversation.id
        )
        selectedLiveProvider = liveProvider
        selectedLiveModel = liveModel
        selectedLiveVoice = liveVoice
    }
    
    private func saveConversationOverrides() {
        // Save provider and model
        ConversationOverridesManager.shared.saveProviderAndModel(
            provider: selectedProvider,
            model: selectedModel,
            for: conversation.id
        )
        
        // Save live settings
        ConversationOverridesManager.shared.saveLiveSettings(
            provider: selectedLiveProvider,
            model: selectedLiveModel,
            voice: selectedLiveVoice,
            for: conversation.id
        )
    }
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
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
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
        .background(AppSurfaces.color(.cardBackground))
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
