//
//  GeneralSettingsView.swift
//  Axon
//
//  General settings for theme, AI provider, and model selection
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @ObservedObject var temporalService = TemporalContextService.shared
    @Environment(\.colorScheme) var systemColorScheme

    @State private var showingNegotiationSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: - Theme Section

            GeneralSettingsSection(title: "Theme") {
                VStack(spacing: 12) {
                    ForEach(Theme.allCases) { theme in
                        SettingsOptionRow(
                            title: theme.displayName,
                            icon: themeIcon(theme),
                            isSelected: viewModel.settings.theme == theme
                        ) {
                            Task {
                                await viewModel.updateSetting(\.theme, theme)
                            }
                        }
                    }

                    if viewModel.settings.theme == .auto {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(AppColors.textTertiary)
                            Text("Following system: \(systemColorScheme == .dark ? "Dark" : "Light")")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding()
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(8)
                    }
                }
            }

            // MARK: - AI Provider Section

            GeneralSettingsSection(title: "AI Provider") {
                let allProviders = viewModel.selectableUnifiedProviders()
                let currentProvider = viewModel.currentUnifiedProvider().flatMap { provider in
                    // If current provider isn't selectable anymore (e.g. key removed), fallback.
                    if allProviders.contains(where: { $0.id == provider.id }) {
                        return provider
                    }
                    return viewModel.fallbackUnifiedProvider()
                } ?? viewModel.fallbackUnifiedProvider()
                let isProviderChangeAllowed = sovereigntyService.isProviderChangeAllowed()
                let providerRestrictionReason = sovereigntyService.providerChangeRestrictionReason()

                // Show restriction banner if provider changes are restricted
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
                            if let selectedProvider = allProviders.first(where: { $0.id == newProviderId }) {
                                Task {
                                    await viewModel.selectUnifiedProvider(selectedProvider)
                                }
                            }
                        }
                    )
                ) {
                    #if os(macOS)
                    Section("Built-in Providers") {
                        ForEach(AIProvider.allCases.filter { viewModel.isBuiltInProviderSelectable($0) }) { provider in
                            MenuButtonItem(
                                id: "builtin_\(provider.rawValue)",
                                label: provider.displayName,
                                isSelected: currentProvider?.id == "builtin_\(provider.rawValue)"
                            ) {
                                if let selected = allProviders.first(where: { $0.id == "builtin_\(provider.rawValue)" }) {
                                    Task { await viewModel.selectUnifiedProvider(selected) }
                                }
                            }
                        }
                    }

                    let selectableCustomProviders = viewModel.settings.customProviders.filter { viewModel.isCustomProviderSelectable($0.id) }
                    if !selectableCustomProviders.isEmpty {
                        Section("Custom Providers") {
                            ForEach(selectableCustomProviders) { provider in
                                MenuButtonItem(
                                    id: "custom_\(provider.id.uuidString)",
                                    label: provider.providerName,
                                    isSelected: currentProvider?.id == "custom_\(provider.id.uuidString)"
                                ) {
                                    if let selected = allProviders.first(where: { $0.id == "custom_\(provider.id.uuidString)" }) {
                                        Task { await viewModel.selectUnifiedProvider(selected) }
                                    }
                                }
                            }
                        }
                    }
                    #else
                    Section("Built-in Providers") {
                        ForEach(AIProvider.allCases.filter { viewModel.isBuiltInProviderSelectable($0) }) { provider in
                            Text(provider.displayName).tag("builtin_\(provider.rawValue)")
                        }
                    }

                    let selectableCustomProviders = viewModel.settings.customProviders.filter { viewModel.isCustomProviderSelectable($0.id) }
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

            GeneralSettingsSection(title: "Model") {
                let currentProvider = viewModel.currentUnifiedProvider()
                let currentModel = viewModel.currentUnifiedModel()
                let providerIndex = viewModel.settings.customProviders.firstIndex(where: { $0.id == viewModel.settings.selectedCustomProviderId }) ?? 0

                if let provider = currentProvider {
                    // Check if this is the MLX provider
                    if provider.id == "builtin_localMLX" {
                        // MLX uses a unified picker + manage link pattern
                        let mlxModels = viewModel.allMLXModels()
                        let selectedId = viewModel.selectedMLXModelId()
                        let selectedModel = mlxModels.first { $0.id == selectedId }

                        VStack(spacing: 12) {
                            // Model picker dropdown
                            StyledMenuPicker(
                                icon: selectedModel?.modalities.contains("vision") == true ? "eye.circle" : "cpu",
                                title: selectedModel?.name ?? LocalMLXModel.defaultModel.displayName,
                                selection: Binding(
                                    get: { selectedId },
                                    set: { newModelId in
                                        Task {
                                            await viewModel.selectMLXModel(repoId: newModelId)
                                        }
                                    }
                                )
                            ) {
                                #if os(macOS)
                                ForEach(mlxModels) { model in
                                    MenuButtonItem(
                                        id: model.id,
                                        label: model.name,
                                        isSelected: selectedId == model.id
                                    ) {
                                        Task { await viewModel.selectMLXModel(repoId: model.id) }
                                    }
                                }
                                #else
                                ForEach(mlxModels) { model in
                                    Text(model.name).tag(model.id)
                                }
                                #endif
                            }

                            // Selected model info card
                            if let model = selectedModel {
                                MLXSelectedModelCard(model: model)
                            }

                            // Manage Models link
                            NavigationLink {
                                SettingsSubviewContainer {
                                    ScrollView {
                                        MLXModelManagementView(viewModel: viewModel)
                                            .padding()
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 16))
                                        .foregroundColor(AppColors.signalMercury)

                                    Text("Manage Models")
                                        .font(AppTypography.bodyMedium())
                                        .foregroundColor(AppColors.textPrimary)

                                    Spacer()

                                    Text("\(viewModel.settings.userMLXModels.count + LocalMLXModel.allCases.count) available")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.textTertiary)
                                }
                                .padding()
                                .background(AppColors.substrateSecondary)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        // Show standard model picker for other providers
                        let availableModels = provider.availableModels(customProviderIndex: providerIndex + 1)

                        StyledMenuPicker(
                            icon: "brain.head.profile",
                            title: currentModel?.name ?? "Select a model",
                            selection: Binding(
                                get: { currentModel?.id ?? "" },
                                set: { newModelId in
                                    if let selectedModel = availableModels.first(where: { $0.id == newModelId }) {
                                        Task {
                                            await viewModel.selectUnifiedModel(selectedModel)
                                        }
                                    }
                                }
                            )
                        ) {
                            #if os(macOS)
                            ForEach(availableModels) { model in
                                MenuButtonItem(
                                    id: model.id,
                                    label: model.name,
                                    isSelected: currentModel?.id == model.id
                                ) {
                                    Task { await viewModel.selectUnifiedModel(model) }
                                }
                            }
                            #else
                            ForEach(availableModels) { model in
                                Text(model.name).tag(model.id)
                            }
                            #endif
                        }

                        if let selectedModel = currentModel {
                            // Selected Model Card (read-only)
                            UnifiedModelRow(
                                model: selectedModel,
                                isSelected: true,
                                action: {}
                            )
                            .disabled(true)
                        }
                    }
                }
            }

            // MARK: - Display Options

            GeneralSettingsSection(title: "Display") {
                VStack(spacing: 12) {
                    SettingsToggleRow(
                        title: "Show Artifacts by Default",
                        icon: "doc.text.fill",
                        isOn: Binding(
                            get: { viewModel.settings.showArtifactsByDefault },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.showArtifactsByDefault, newValue)
                                }
                            }
                        )
                    )

                    SettingsToggleRow(
                        title: "Enable Keyboard Shortcuts",
                        icon: "command",
                        isOn: Binding(
                            get: { viewModel.settings.enableKeyboardShortcuts },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.enableKeyboardShortcuts, newValue)
                                }
                            }
                        )
                    )
                }
            }

            // MARK: - Temporal Awareness

            GeneralSettingsSection(title: "Temporal Awareness") {
                VStack(spacing: 12) {
                    // Mode selector (Sync / Drift)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mode")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)

                        HStack(spacing: 8) {
                            ForEach(TemporalMode.allCases) { mode in
                                TemporalModeButton(
                                    mode: mode,
                                    isSelected: viewModel.settings.temporalSettings.mode == mode
                                ) {
                                    Task {
                                        await viewModel.updateSetting(\.temporalSettings.mode, mode)
                                        // Also update the service
                                        if mode == .sync {
                                            TemporalContextService.shared.enableSync()
                                        } else {
                                            TemporalContextService.shared.enableDrift()
                                        }
                                    }
                                }
                            }
                        }

                        Text(viewModel.settings.temporalSettings.mode.description)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textTertiary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.substrateSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.glassBorder, lineWidth: 1)
                            )
                    )

                    // Turn count display (live from Core Data)
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lifetime Turns")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Text("\(temporalService.lifetimeTurnCount) turns together")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.substrateSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.glassBorder, lineWidth: 1)
                            )
                    )

                    // Show status bar toggle
                    SettingsToggleRow(
                        title: "Show Status Bar",
                        icon: "chart.bar.fill",
                        isOn: Binding(
                            get: { viewModel.settings.temporalSettings.showStatusBar },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.temporalSettings.showStatusBar, newValue)
                                }
                            }
                        )
                    )

                    // Philosophy note
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(AppColors.signalSaturn.opacity(0.7))
                        Text("Temporal symmetry: Provide Axon with temporal grounding and recieve turn-based temporal grounding in return.")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.signalSaturn.opacity(0.1))
                    )
                }
            }

            // MARK: - Text-to-Speech

            GeneralSettingsSection(title: "Text-to-Speech") {
                NavigationLink {
                    SettingsSubviewContainer {
                        TTSSettingsView(viewModel: viewModel)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Voice Settings")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Text(ttsSummary)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.substrateSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.glassBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // MARK: - Data Management

            GeneralSettingsSection(title: "Data Management") {
                NavigationLink {
                    DataManagementView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Customize Data Distribution")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Text(dataManagementSummary)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.substrateSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.glassBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .sheet(isPresented: $showingNegotiationSheet) {
            CovenantNegotiationView(preselectedCategory: .providerChange)
                #if os(macOS)
                .frame(minWidth: 550, idealWidth: 650, minHeight: 600, idealHeight: 800)
                #endif
        }
    }

    private var ttsSummary: String {
        let tts = viewModel.settings.ttsSettings
        return "\(tts.provider.displayName) · \(tts.qualityTier.displayName)"
    }

    private var dataManagementSummary: String {
        let config = viewModel.settings.deviceModeConfig
        return "\(config.cloudSyncProvider.displayName) · \(config.dataStorage.displayName) · \(config.aiProcessing.displayName) AI"
    }

    private func themeIcon(_ theme: Theme) -> String {
        switch theme {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .auto: return "circle.lefthalf.filled"
        }
    }

    private var supportedProviders: [AIProvider] {
        // Show all supported providers, including Gemini (which uses 2.5 models)
        return AIProvider.allCases
    }

    private func pricingText(for model: AIModel, provider: AIProvider) -> String? {
        // Resolve pricing via canonical registry to stay in sync with CostService
        if let key = PricingKeyResolver.canonicalKey(for: model.id) ?? PricingKeyResolver.canonicalKey(for: model.name) {
            let pricing = PricingRegistry.price(for: key)
            var parts: [String] = []
            parts.append(String(format: "$%.2f in / $%.2f out per 1M tokens", pricing.inputPerMTokUSD, pricing.outputPerMTokUSD))
            if let cached = pricing.cachedInputPerMTokUSD {
                parts.append(String(format: "cached: $%.2f", cached))
            }
            if let notes = pricing.notes, !notes.isEmpty {
                parts.append(notes)
            }
            return parts.joined(separator: " · ")
        }
        return nil
    }

    // Choose a sensible default model per provider based on highest version of specific families
    private func preferredDefaultModelId(for provider: AIProvider) -> String? {
        let models = provider.availableModels
        switch provider {
        case .gemini:
            // Prefer highest-version Flash (e.g., Gemini 2.5 Flash)
            let candidates = models.filter { containsCaseInsensitive($0.name, "flash") || containsCaseInsensitive($0.id, "flash") }
            return candidates.max(by: { versionScore($0) < versionScore($1) })?.id
        case .openai:
            // Prefer highest-version Mini (e.g., GPT-5 Mini over 4.1 Mini)
            let candidates = models.filter { containsCaseInsensitive($0.name, "mini") || containsCaseInsensitive($0.id, "mini") }
            return candidates.max(by: { versionScore($0) < versionScore($1) })?.id
        case .anthropic:
            // Prefer highest-version Haiku (e.g., Claude Haiku 4.5)
            let candidates = models.filter { containsCaseInsensitive($0.name, "haiku") || containsCaseInsensitive($0.id, "haiku") }
            return candidates.max(by: { versionScore($0) < versionScore($1) })?.id
        case .xai:
            // Prefer Grok 4 Fast Reasoning as default
            let candidates = models.filter { containsCaseInsensitive($0.name, "fast") || containsCaseInsensitive($0.id, "fast") }
            return candidates.max(by: { versionScore($0) < versionScore($1) })?.id
        case .perplexity:
            // Prefer Sonar (cheapest) as default
            let candidates = models.filter { $0.id == "sonar" }
            return candidates.first?.id ?? models.first?.id
        case .deepseek:
            // Prefer DeepSeek Chat (cheaper) as default
            let candidates = models.filter { containsCaseInsensitive($0.id, "chat") }
            return candidates.first?.id ?? models.first?.id
        case .zai:
            // Prefer GLM-4.5-Air (balanced) as default
            let candidates = models.filter { containsCaseInsensitive($0.id, "air") }
            return candidates.first?.id ?? models.first?.id
        case .minimax:
            // Prefer MiniMax-M2 as default
            let candidates = models.filter { $0.id == "MiniMax-M2" }
            return candidates.first?.id ?? models.first?.id
        case .mistral:
            // Prefer Codestral (cheapest) as default
            let candidates = models.filter { containsCaseInsensitive($0.id, "codestral") }
            return candidates.first?.id ?? models.first?.id
        case .appleFoundation:
            // Only one model available - the default system model
            return models.first?.id
        case .localMLX:
            // Default to SmolLM2 (first in list)
            return models.first?.id
        }
    }

    // Extract a comparable version score from model name/id (e.g., 5, 4.1, 2.5)
    private func versionScore(_ model: AIModel) -> Double {
        func extractVersion(from text: String) -> Double? {
            // Find the first occurrence of a number with optional decimal (e.g., 5, 4.1, 2.5)
            let pattern = #"(\d+(?:\.\d+)?)"#
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                return Double(match)
            }
            return nil
        }
        // Prefer version in name, fallback to id
        return extractVersion(from: model.name) ?? extractVersion(from: model.id) ?? 0
    }

    private func containsCaseInsensitive(_ text: String, _ needle: String) -> Bool {
        text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // MARK: - Model Grouping Helpers

    private func currentModels(for provider: AIProvider) -> [AIModel] {
        let models = provider.availableModels
        // Group by family and take the highest version from each family
        let grouped = Dictionary(grouping: models, by: familyKey(for:))
        let picks = grouped.values.compactMap { familyModels in
            familyModels.max(by: { versionScore($0) < versionScore($1) })
        }
        // Sort by descending version score for nicer ordering
        return picks.sorted { versionScore($0) > versionScore($1) }
    }

    private struct SeriesGroup: Identifiable {
        let series: String
        let models: [AIModel]
        var id: String { series }
    }

    private func seriesGroupedModels(for provider: AIProvider) -> [SeriesGroup] {
        let models = provider.availableModels
        // Exclude those already in Current
        let currentSet = Set(currentModels(for: provider).map { $0.id })
        let remaining = models.filter { !currentSet.contains($0.id) }
        let grouped = Dictionary(grouping: remaining, by: seriesKey(for:))
        // Sort models within each series by descending version
        let seriesGroups: [SeriesGroup] = grouped.map { (key: String, value: [AIModel]) in
            SeriesGroup(series: key, models: value.sorted { versionScore($0) > versionScore($1) })
        }
        // Sort series by a numeric score extracted from the label (e.g., GPT-5 before GPT-4)
        return seriesGroups.sorted { seriesSortKey($0.series) > seriesSortKey($1.series) }
    }

    private func familyKey(for model: AIModel) -> String {
        let id = model.id.lowercased()
        let name = model.name.lowercased()
        switch model.provider {
        case .openai:
            if name.contains("mini") || id.contains("mini") { return "Mini" }
            if id.contains("nano") { return "Nano" }
            if id == "o3" || id.contains("o3-") { return "o3" }
            if id.contains("o4-mini") { return "o4-mini" }
            if id == "o1" || id.contains("o1-") { return "o1" }
            if id.contains("gpt-5") { return "GPT-5" }
            if id.contains("gpt-4.1") { return "GPT-4.1" }
            if id.contains("gpt-4o") { return "GPT-4o" }
            return "OpenAI Other"
        case .anthropic:
            if name.contains("haiku") || id.contains("haiku") { return "Haiku" }
            if name.contains("sonnet") || id.contains("sonnet") { return "Sonnet" }
            if name.contains("opus") || id.contains("opus") { return "Opus" }
            return "Claude Other"
        case .gemini:
            if name.contains("flash") || id.contains("flash") { return "Flash" }
            if name.contains("pro") || id.contains("pro") { return "Pro" }
            return "Gemini Other"
        case .xai:
            if name.contains("fast") || id.contains("fast") { return "Fast" }
            if name.contains("code") || id.contains("code") { return "Code" }
            if name.contains("mini") || id.contains("mini") { return "Mini" }
            if id.contains("grok-4") { return "Grok 4" }
            if id.contains("grok-3") { return "Grok 3" }
            return "Grok Other"
        case .perplexity:
            if name.contains("reasoning") || id.contains("reasoning") { return "Reasoning" }
            if name.contains("pro") || id.contains("pro") { return "Pro" }
            return "Sonar"
        case .deepseek:
            if name.contains("reasoner") || id.contains("reasoner") { return "Reasoner" }
            return "Chat"
        case .zai:
            if name.contains("4.6") || id.contains("4.6") { return "GLM-4.6" }
            if name.contains("4.5") || id.contains("4.5") { return "GLM-4.5" }
            return "GLM"
        case .minimax:
            if name.contains("stable") || id.contains("stable") { return "Stable" }
            return "M2"
        case .mistral:
            if name.contains("pixtral") || id.contains("pixtral") { return "Pixtral" }
            if name.contains("codestral") || id.contains("codestral") { return "Codestral" }
            return "Large"
        case .appleFoundation:
            return "Apple Intelligence"
        case .localMLX:
            // Show model name from the HuggingFace ID
            if id.contains("smollm") { return "SmolLM2" }
            if id.contains("llama") { return "Llama" }
            if id.contains("qwen") { return "Qwen3" }
            if id.contains("phi") { return "Phi-4" }
            return "MLX Model"
        }
    }

    private func seriesKey(for model: AIModel) -> String {
        let id = model.id.lowercased()
        let name = model.name.lowercased()
        switch model.provider {
        case .openai:
            if id.contains("gpt-5") || name.contains("gpt-5") { return "GPT-5 Series" }
            if id.contains("gpt-4.1") || name.contains("gpt-4.1") || id.contains("gpt-4o") || name.contains("gpt-4o") || id.contains("gpt-4") || name.contains("gpt-4") { return "GPT-4 Series" }
            if id.contains("o3") || name.contains("o3") { return "o3 Series" }
            if id.contains("o1") || name.contains("o1") { return "o1 Series" }
            return "Other OpenAI"
        case .anthropic:
            // Use the highest granular label available
            if name.contains("4.5") || id.contains("4.5") { return "Claude 4.5 Series" }
            if name.contains("4.1") || id.contains("4.1") { return "Claude 4.1 Series" }
            if name.contains("4") || id.contains("4") { return "Claude 4 Series" }
            return "Other Claude"
        case .gemini:
            if name.contains("2.5") || id.contains("2.5") { return "Gemini 2.5 Series" }
            return "Other Gemini"
        case .xai:
            if id.contains("grok-4") || name.contains("grok-4") || name.contains("grok 4") { return "Grok 4 Series" }
            if id.contains("grok-3") || name.contains("grok-3") || name.contains("grok 3") { return "Grok 3 Series" }
            return "Other Grok"
        case .perplexity:
            if name.contains("reasoning") || id.contains("reasoning") { return "Reasoning Series" }
            return "Sonar Series"
        case .deepseek:
            return "DeepSeek Series"
        case .zai:
            if name.contains("4.6") || id.contains("4.6") { return "GLM-4.6 Series" }
            return "GLM-4.5 Series"
        case .minimax:
            return "MiniMax M2 Series"
        case .mistral:
            if name.contains("pixtral") || id.contains("pixtral") { return "Pixtral Series" }
            if name.contains("codestral") || id.contains("codestral") { return "Codestral Series" }
            return "Mistral Large Series"
        case .appleFoundation:
            return "Apple Intelligence"
        case .localMLX:
            return "On-Device (MLX)"
        }
    }

    private func seriesSortKey(_ series: String) -> Double {
        // Extract the first number in the series label for sorting; default to 0
        let pattern = #"(\d+(?:\.\d+)?)"#
        if let range = series.range(of: pattern, options: .regularExpression) {
            return Double(series[range]) ?? 0
        }
        // Prefer known order for non-numeric series
        if series.lowercased().contains("o3") { return 3.0 }
        if series.lowercased().contains("o1") { return 1.0 }
        return 0
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: AIModel
    let isSelected: Bool
    let footerText: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(model.description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)

                    if let footerText = footerText {
                        HStack(spacing: 8) {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(AppColors.textTertiary)
                            Text(footerText)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 8) {
                        Label(
                            String(format: "%.0fK context", Double(model.contextWindow) / 1000),
                            systemImage: "brain.head.profile"
                        )
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.signalMercury)
                        .font(.system(size: 20))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppColors.signalMercury : AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Reusable Components

struct GeneralSettingsSection<Content: View>: View {
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

struct SettingsOptionRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                    .frame(width: 32)

                Text(title)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.signalMercury)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppColors.signalMercury : AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// SettingsToggleRow moved to SharedUIElements.swift

// MARK: - MLX Selected Model Card

struct MLXSelectedModelCard: View {
    let model: AIModel

    private var isBundled: Bool {
        model.id == LocalMLXModel.defaultModel.rawValue
    }

    private var isVision: Bool {
        model.modalities.contains("vision")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isVision ? "eye.circle.fill" : "cpu")
                .font(.system(size: 24))
                .foregroundColor(AppColors.signalMercury)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    if isBundled {
                        Text("Bundled")
                            .font(AppTypography.labelSmall())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.signalMercury.opacity(0.2))
                            .foregroundColor(AppColors.signalMercury)
                            .cornerRadius(4)
                    }

                    if isVision {
                        Text("Vision")
                            .font(AppTypography.labelSmall())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.signalLichen.opacity(0.2))
                            .foregroundColor(AppColors.signalLichen)
                            .cornerRadius(4)
                    }
                }

                Text(model.description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(model.contextWindow / 1000)K context", systemImage: "brain.head.profile")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Label("Private & Free", systemImage: "lock.shield")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Temporal Mode Button

struct TemporalModeButton: View {
    let mode: TemporalMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16))
                Text(mode.displayName)
                    .font(AppTypography.bodyMedium(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury : AppColors.substrateSecondary)
            )
            .foregroundColor(isSelected ? .white : AppColors.textPrimary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        GeneralSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
