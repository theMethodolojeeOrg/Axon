//
//  ModelTuningView.swift
//  Axon
//
//  Per-model generation parameter overrides.
//  Organized by provider with expandable accordions for each model.
//

import SwiftUI

// MARK: - Model Tuning View

struct ModelTuningView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var searchQuery = ""
    @State private var expandedProviders: Set<String> = []
    @State private var showingModelDetail: ModelOverrideContext?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Search
                ModelTuningSearchBar(text: $searchQuery, placeholder: "Search models...")

                // Stats
                overrideStatsBanner

                // Provider accordions
                providerAccordions

                // Global defaults link
                globalDefaultsSection
            }
            .padding()
        }
        .background(AppColors.substratePrimary)
        .navigationTitle("Model Tuning")
        .sheet(item: $showingModelDetail) { context in
            ModelOverrideSheet(
                context: context,
                viewModel: viewModel
            )
            #if os(iOS)
            // Encourage a usable default size on iPhone/iPad.
            .presentationDetents([.medium, .large])
            #endif
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-Model Overrides")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)

            Text("Fine-tune generation parameters for specific models. Overrides take precedence over global defaults.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Stats Banner

    private var overrideStatsBanner: some View {
        let totalModels = allModels.count
        let overriddenCount = viewModel.settings.modelOverrides.values.filter { $0.enabled }.count

        return HStack(spacing: 24) {
            ModelTuningStatItem(value: "\(totalModels)", label: "Models")
            ModelTuningStatItem(value: "\(overriddenCount)", label: "Overridden")
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }

    // MARK: - Provider Accordions

    private var providerAccordions: some View {
        VStack(spacing: 12) {
            ForEach(filteredProviders, id: \.self) { provider in
                ModelTuningProviderAccordion(
                    provider: provider,
                    models: modelsForProvider(provider),
                    overrides: viewModel.settings.modelOverrides,
                    isExpanded: expandedProviders.contains(provider.rawValue),
                    onToggleExpand: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedProviders.contains(provider.rawValue) {
                                expandedProviders.remove(provider.rawValue)
                            } else {
                                expandedProviders.insert(provider.rawValue)
                            }
                        }
                    },
                    onSelectModel: { model in
                        showingModelDetail = ModelOverrideContext(
                            modelId: model.id,
                            modelName: model.name,
                            provider: provider
                        )
                    },
                    onToggleOverride: { modelId, enabled in
                        toggleOverride(modelId: modelId, enabled: enabled)
                    }
                )
            }
        }
    }

    // MARK: - Global Defaults Section

    private var globalDefaultsSection: some View {
        NavigationLink(destination: ModelConfigurationView(viewModel: viewModel)) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Global Defaults")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text("Fallback settings when no override is active")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private var allModels: [AIModel] {
        AIProvider.allCases.flatMap { $0.availableModels }
    }

    private var filteredProviders: [AIProvider] {
        let providers = AIProvider.allCases.filter { provider in
            !modelsForProvider(provider).isEmpty
        }

        if searchQuery.isEmpty {
            return providers
        }

        return providers.filter { provider in
            !modelsForProvider(provider).isEmpty
        }
    }

    private func modelsForProvider(_ provider: AIProvider) -> [AIModel] {
        let models = provider.availableModels

        if searchQuery.isEmpty {
            return models
        }

        let query = searchQuery.lowercased()
        return models.filter { model in
            model.name.lowercased().contains(query) ||
            model.id.lowercased().contains(query)
        }
    }

    private func toggleOverride(modelId: String, enabled: Bool) {
        if enabled {
            // Create override if it doesn't exist
            if viewModel.settings.modelOverrides[modelId] == nil {
                viewModel.settings.modelOverrides[modelId] = ModelOverride(modelId: modelId)
            }
            viewModel.settings.modelOverrides[modelId]?.enabled = true
        } else {
            viewModel.settings.modelOverrides[modelId]?.enabled = false
        }
    }
}

// MARK: - Model Override Context

struct ModelOverrideContext: Identifiable {
    let modelId: String
    let modelName: String
    let provider: AIProvider

    var id: String { modelId }
}

// MARK: - Provider Accordion

private struct ModelTuningProviderAccordion: View {
    let provider: AIProvider
    let models: [AIModel]
    let overrides: [String: ModelOverride]
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onSelectModel: (AIModel) -> Void
    let onToggleOverride: (String, Bool) -> Void

    private var overriddenCount: Int {
        models.filter { model in
            overrides[model.id]?.enabled == true
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    Image(systemName: providerIcon)
                        .font(.system(size: 18))
                        .foregroundColor(overriddenCount > 0 ? AppColors.signalMercury : AppColors.textTertiary)
                        .frame(width: 24)

                    Text(provider.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    if overriddenCount > 0 {
                        Text("\(overriddenCount) override\(overriddenCount == 1 ? "" : "s")")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalMercury)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppColors.signalMercury.opacity(0.15))
                            .cornerRadius(4)
                    }

                    Spacer()

                    Text("\(models.count)")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Models list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(models) { model in
                        ModelTuningModelRow(
                            model: model,
                            override: overrides[model.id],
                            onSelect: { onSelectModel(model) },
                            onToggle: { enabled in onToggleOverride(model.id, enabled) }
                        )

                        if model.id != models.last?.id {
                            Divider()
                                .background(AppColors.divider)
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(AppColors.substrateTertiary.opacity(0.5))
                .cornerRadius(8)
                .padding(.top, 4)
            }
        }
    }

    private var providerIcon: String {
        switch provider {
        case .anthropic: return "brain"
        case .openai: return "cpu"
        case .gemini: return "sparkles"
        case .xai: return "bolt"
        case .perplexity: return "magnifyingglass"
        case .deepseek: return "waveform.path"
        case .zai: return "globe.asia.australia"
        case .minimax: return "m.circle"
        case .mistral: return "wind"
        case .appleFoundation: return "apple.logo"
        case .localMLX: return "desktopcomputer"
        }
    }
}

// MARK: - Model Row

private struct ModelTuningModelRow: View {
    let model: AIModel
    let override: ModelOverride?
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void

    private var isOverridden: Bool {
        override?.enabled == true
    }

    private var hasCustomValues: Bool {
        guard let override = override else { return false }
        return override.hasOverrides
    }

    var body: some View {
        HStack(spacing: 12) {
            // Override toggle
            Toggle("", isOn: Binding(
                get: { isOverridden },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    if isOverridden && hasCustomValues {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.signalMercury)
                    }
                }

                Text(model.id)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Override count badge
            if let override = override, override.enabled, override.overrideCount > 0 {
                Text("\(override.overrideCount)")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.signalMercury)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.signalMercury.opacity(0.15))
                    .cornerRadius(4)
            }

            // Detail button
            Button(action: onSelect) {
                Image(systemName: "info.circle")
                    .foregroundColor(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Model Override Sheet

private struct ModelOverrideSheet: View {
    let context: ModelOverrideContext
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var localOverride: ModelOverride

    init(context: ModelOverrideContext, viewModel: SettingsViewModel) {
        self.context = context
        self.viewModel = viewModel

        // Initialize with existing override or create new one
        let existing = viewModel.settings.modelOverrides[context.modelId]
        _localOverride = State(initialValue: existing ?? ModelOverride(modelId: context.modelId))
    }

    var body: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    modelHeader

                    // Enable toggle
                    enableToggle

                    if localOverride.enabled {
                        // Preset buttons
                        presetSection

                        // Override parameters
                        parameterSections
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Model Override")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveOverride()
                    dismiss()
                }
            }
        }
        #if os(macOS)
        // Prevent overly compact sheets on macOS.
        .frame(minWidth: 500, idealWidth: 620, minHeight: 520, idealHeight: 700)
        #endif
    }

    // MARK: - Model Header

    private var modelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 40, height: 40)
                    .background(AppColors.signalMercury.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.modelName)
                        .font(AppTypography.titleSmall())
                        .foregroundColor(AppColors.textPrimary)

                    Text(context.provider.displayName)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            Text(context.modelId)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }

    // MARK: - Enable Toggle

    private var enableToggle: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $localOverride.enabled)
                .toggleStyle(.switch)
                .tint(AppColors.signalMercury)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text("Enable Override")
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Use custom parameters for this model")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }

    // MARK: - Preset Section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Presets")
                .font(AppTypography.labelMedium())
                .foregroundColor(AppColors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ModelOverridePreset.allCases) { preset in
                        ModelTuningPresetButton(preset: preset, action: {
                            applyPreset(preset)
                        })
                    }

                    // Clear button
                    Button {
                        localOverride.clearOverrides()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12))
                            Text("Clear All")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.accentWarning)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.accentWarning.opacity(0.1))
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Parameter Sections

    private var parameterSections: some View {
        VStack(spacing: 16) {
            // Temperature
            ModelTuningParameterSection(
                title: "Temperature",
                description: "Controls randomness (0.0-1.0)",
                value: $localOverride.temperature,
                range: 0...1,
                step: 0.1,
                format: "%.1f"
            )

            // Top-P
            ModelTuningParameterSection(
                title: "Top-P",
                description: "Nucleus sampling threshold (0.0-1.0)",
                value: $localOverride.topP,
                range: 0...1,
                step: 0.05,
                format: "%.2f"
            )

            // Top-K
            ModelTuningParameterSectionInt(
                title: "Top-K",
                description: "Limit token choices (1-100)",
                value: $localOverride.topK,
                range: 1...100
            )

            // Repetition Penalty (MLX only indicator)
            ModelTuningParameterSection(
                title: "Repetition Penalty",
                description: "Discourage repetition (1.0-2.0) • MLX Only",
                value: $localOverride.repetitionPenalty,
                range: 1...2,
                step: 0.1,
                format: "%.1f"
            )

            // Repetition Context Size
            ModelTuningParameterSectionInt(
                title: "Repetition Context",
                description: "Tokens to check for repetition (16-512) • MLX Only",
                value: $localOverride.repetitionContextSize,
                range: 16...512
            )

            // Max Response Tokens
            ModelTuningParameterSectionInt(
                title: "Max Response Tokens",
                description: "Limit response length (128-4096) • MLX Only",
                value: $localOverride.maxResponseTokens,
                range: 128...4096
            )
        }
    }

    // MARK: - Actions

    private func applyPreset(_ preset: ModelOverridePreset) {
        let presetOverride = preset.createOverride(for: context.modelId)
        localOverride.temperature = presetOverride.temperature
        localOverride.topP = presetOverride.topP
        localOverride.topK = presetOverride.topK
        localOverride.repetitionPenalty = presetOverride.repetitionPenalty
        localOverride.repetitionContextSize = presetOverride.repetitionContextSize
        localOverride.maxResponseTokens = presetOverride.maxResponseTokens
    }

    private func saveOverride() {
        viewModel.settings.modelOverrides[context.modelId] = localOverride
    }
}

// MARK: - Preset Button

private struct ModelTuningPresetButton: View {
    let preset: ModelOverridePreset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(preset.displayName)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.substrateTertiary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Parameter Section (Double)

private struct ModelTuningParameterSection: View {
    let title: String
    let description: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    private var isEnabled: Bool {
        value != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue && value == nil {
                            value = (range.lowerBound + range.upperBound) / 2
                        } else if !newValue {
                            value = nil
                        }
                    }
                ))
                .toggleStyle(.switch)
                .tint(AppColors.signalMercury)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(description)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                if let val = value {
                    Text(String(format: format, val))
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.signalMercury)
                        .monospacedDigit()
                }
            }

            if isEnabled, value != nil {
                Slider(
                    value: Binding(
                        get: { value ?? range.lowerBound },
                        set: { value = $0 }
                    ),
                    in: range,
                    step: step
                )
                .tint(AppColors.signalMercury)
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Parameter Section (Int)

private struct ModelTuningParameterSectionInt: View {
    let title: String
    let description: String
    @Binding var value: Int?
    let range: ClosedRange<Int>

    private var isEnabled: Bool {
        value != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue && value == nil {
                            value = (range.lowerBound + range.upperBound) / 2
                        } else if !newValue {
                            value = nil
                        }
                    }
                ))
                .toggleStyle(.switch)
                .tint(AppColors.signalMercury)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(description)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                if let val = value {
                    Text("\(val)")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.signalMercury)
                        .monospacedDigit()
                }
            }

            if isEnabled, value != nil {
                Slider(
                    value: Binding(
                        get: { Double(value ?? range.lowerBound) },
                        set: { value = Int($0) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .tint(AppColors.signalMercury)
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Search Bar

private struct ModelTuningSearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(AppColors.textPrimary)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Stat Item

private struct ModelTuningStatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.signalMercury)
            Text(label)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ModelTuningView(viewModel: SettingsViewModel.shared)
    }
}
