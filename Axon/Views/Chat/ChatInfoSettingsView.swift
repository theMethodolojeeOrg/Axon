//
//  ChatInfoSettingsView.swift
//  Axon
//
//  Per-conversation info and settings view
//

import SwiftUI

struct ChatInfoSettingsView: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var costService = CostService.shared

    // Per-conversation overrides (stored locally)
    @State private var selectedProvider: UnifiedProvider?
    @State private var selectedModel: UnifiedModel?
    @State private var estimatedTokens: Int = 0

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
            await estimateTokenCount()
        }
    }
    #endif

    @ViewBuilder
    private var mainContent: some View {
        // MARK: - Provider Selection
        ChatInfoSection(title: "AI Provider") {
            let allProviders = settingsViewModel.allUnifiedProviders()
            let currentProvider = selectedProvider ?? settingsViewModel.currentUnifiedProvider()

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
                    ForEach(AIProvider.allCases) { provider in
                        MenuButtonItem(
                            id: "builtin_\(provider.rawValue)",
                            label: provider.displayName,
                            isSelected: currentProvider?.id == "builtin_\(provider.rawValue)"
                        ) {
                            selectProvider(allProviders.first(where: { $0.id == "builtin_\(provider.rawValue)" }))
                        }
                    }
                }

                if !settingsViewModel.settings.customProviders.isEmpty {
                    Section("Custom Providers") {
                        ForEach(settingsViewModel.settings.customProviders) { provider in
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
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag("builtin_\(provider.rawValue)")
                    }
                }

                if !settingsViewModel.settings.customProviders.isEmpty {
                    Section("Custom Providers") {
                        ForEach(settingsViewModel.settings.customProviders) { provider in
                            Text(provider.providerName).tag("custom_\(provider.id.uuidString)")
                        }
                    }
                }
                #endif
            }
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

                    Text("\(Int(progressPercentage * 100))% of context window used")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
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
    }

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

    private func estimateTokenCount() async {
        // Rough estimation: 4 characters per token
        // Get all messages for this conversation
        let messages = conversationService.messages
        let totalCharacters = messages.reduce(0) { $0 + $1.content.count }
        estimatedTokens = max(1, totalCharacters / 4)
    }

    private func loadConversationOverrides() {
        // Load per-conversation overrides from UserDefaults
        let key = "conversation_overrides_\(conversation.id)"
        if let data = UserDefaults.standard.data(forKey: key),
           let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {

            // Restore provider
            if let customProviderId = overrides.customProviderId,
               let customProvider = settingsViewModel.settings.customProviders.first(where: { $0.id == customProviderId }) {
                selectedProvider = .custom(customProvider)
            } else if let builtInProvider = AIProvider(rawValue: overrides.builtInProvider ?? "") {
                selectedProvider = .builtIn(builtInProvider)
            }

            // Restore model
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

        // Persist to UserDefaults
        let key = "conversation_overrides_\(conversation.id)"
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Conversation Overrides Model

struct ConversationOverrides: Codable {
    // Identifiers
    var builtInProvider: String?
    var customProviderId: UUID?
    var builtInModel: String?
    var customModelId: UUID?

    // Human-friendly metadata (optional)
    var providerDisplayName: String?
    var modelDisplayName: String?
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

// MARK: - Preview

#Preview {
    ChatInfoSettingsView(conversation: Conversation(
        userId: "user1",
        title: "Test Conversation",
        projectId: "default", messageCount: 10
    ))
}
