//
//  SubconsciousMemoryLoggingDetailView.swift
//  Axon
//
//  Fine-grained configuration for background subconscious memory logging.
//

import SwiftUI

struct SubconsciousMemoryLoggingDetailView: View {
    @ObservedObject var viewModel: SettingsViewModel

    private struct ProviderChoice: Identifiable {
        let id: String
        let title: String
        let builtIn: AIProvider?
        let custom: CustomProviderConfig?
    }

    private struct ModelChoice: Identifiable {
        let id: String
        let title: String
        let contextWindow: Int
        let builtInModelId: String?
        let customModelId: UUID?
    }

    private var subsystemSettings: SubconsciousMemoryLoggingSettings {
        viewModel.settings.resolvedSubconsciousMemoryLogging
    }

    private var providerChoices: [ProviderChoice] {
        let builtIns = AIProvider.allCases.map { provider in
            ProviderChoice(
                id: "builtin:\(provider.rawValue)",
                title: provider.displayName,
                builtIn: provider,
                custom: nil
            )
        }
        let customs = viewModel.settings.customProviders.map { custom in
            ProviderChoice(
                id: "custom:\(custom.id.uuidString)",
                title: custom.providerName,
                builtIn: nil,
                custom: custom
            )
        }
        return builtIns + customs
    }

    private var selectedProviderChoice: ProviderChoice {
        if let customProviderId = subsystemSettings.customProviderId,
           let choice = providerChoices.first(where: { $0.custom?.id == customProviderId }) {
            return choice
        }

        if let builtInRaw = subsystemSettings.builtInProvider,
           let choice = providerChoices.first(where: { $0.builtIn?.rawValue == builtInRaw }) {
            return choice
        }

        if let fallback = providerChoices.first(where: { $0.builtIn == viewModel.settings.defaultProvider }) {
            return fallback
        }

        return providerChoices.first ?? ProviderChoice(
            id: "builtin:\(AIProvider.appleFoundation.rawValue)",
            title: AIProvider.appleFoundation.displayName,
            builtIn: .appleFoundation,
            custom: nil
        )
    }

    private var modelChoices: [ModelChoice] {
        if let builtInProvider = selectedProviderChoice.builtIn {
            let models = builtInModels(for: builtInProvider)
            return models.map { model in
                ModelChoice(
                    id: "builtin:\(model.id)",
                    title: model.name,
                    contextWindow: model.contextWindow,
                    builtInModelId: model.id,
                    customModelId: nil
                )
            }
        }

        if let customProvider = selectedProviderChoice.custom {
            return customProvider.models.map { model in
                ModelChoice(
                    id: "custom:\(model.id.uuidString)",
                    title: model.friendlyName ?? model.modelCode,
                    contextWindow: model.contextWindow,
                    builtInModelId: nil,
                    customModelId: model.id
                )
            }
        }

        return []
    }

    private var selectedModelChoice: ModelChoice? {
        if let customProvider = selectedProviderChoice.custom {
            if let selectedCustomModelId = subsystemSettings.customModelId,
               let choice = modelChoices.first(where: { $0.customModelId == selectedCustomModelId }) {
                return choice
            }
            if let first = customProvider.models.first {
                return modelChoices.first(where: { $0.customModelId == first.id })
            }
            return nil
        }

        if let selectedBuiltInModel = subsystemSettings.builtInModel,
           let choice = modelChoices.first(where: { $0.builtInModelId == selectedBuiltInModel }) {
            return choice
        }

        if let builtInProvider = selectedProviderChoice.builtIn,
           builtInProvider == viewModel.settings.defaultProvider,
           let choice = modelChoices.first(where: { $0.builtInModelId == viewModel.settings.defaultModel }) {
            return choice
        }

        return modelChoices.first
    }

    private var selectedContextWindow: Int {
        selectedModelChoice?.contextWindow ?? 128_000
    }

    private var rollingPercent: Double {
        max(0.01, min(1.0, subsystemSettings.rollingContextPercent))
    }

    private var rollingTokenPreview: Int {
        Int(Double(selectedContextWindow) * rollingPercent)
    }

    private var selectedProviderId: Binding<String> {
        Binding(
            get: { selectedProviderChoice.id },
            set: { newId in
                guard let providerChoice = providerChoices.first(where: { $0.id == newId }) else { return }
                mutateSubconsciousSettings { updated in
                    if let builtIn = providerChoice.builtIn {
                        updated.builtInProvider = builtIn.rawValue
                        updated.customProviderId = nil
                        updated.customModelId = nil
                        let builtInSelection = builtInModels(for: builtIn)
                        if builtIn == viewModel.settings.defaultProvider,
                           builtInSelection.contains(where: { $0.id == viewModel.settings.defaultModel }) {
                            updated.builtInModel = viewModel.settings.defaultModel
                        } else {
                            updated.builtInModel = builtInSelection.first?.id
                        }
                    } else if let custom = providerChoice.custom {
                        updated.customProviderId = custom.id
                        updated.customModelId = custom.models.first?.id
                        updated.builtInProvider = nil
                        updated.builtInModel = nil
                    }
                }
            }
        )
    }

    private var selectedModelId: Binding<String> {
        Binding(
            get: { selectedModelChoice?.id ?? modelChoices.first?.id ?? "" },
            set: { newId in
                guard let modelChoice = modelChoices.first(where: { $0.id == newId }) else { return }
                mutateSubconsciousSettings { updated in
                    if let modelId = modelChoice.builtInModelId {
                        updated.builtInModel = modelId
                        updated.customModelId = nil
                    } else if let customModelId = modelChoice.customModelId {
                        updated.customModelId = customModelId
                        updated.builtInModel = nil
                    }
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: "Model") {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Subconscious Provider")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Picker("Subconscious Provider", selection: selectedProviderId) {
                                ForEach(providerChoices) { choice in
                                    Text(choice.title).tag(choice.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColors.signalMercury)
                        }

                        if !modelChoices.isEmpty {
                            Divider()
                                .background(AppColors.divider)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Subconscious Model")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)

                                Picker("Subconscious Model", selection: selectedModelId) {
                                    ForEach(modelChoices) { choice in
                                        Text(choice.title).tag(choice.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppColors.signalMercury)
                            }
                        }

                        if let provider = selectedProviderChoice.builtIn,
                           provider == .appleFoundation || provider == .localMLX {
                            Divider()
                                .background(AppColors.divider)

                            Text("This provider currently cannot run subconscious background logging. If selected, the chat thread will show an availability warning when a logging pass runs.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentWarning)
                        }
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }

                SettingsSection(title: "Rolling Context Window") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Rolling Context Percent")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("\(Int(rollingPercent * 100))%")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { rollingPercent },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.rollingContextPercent = max(0.01, min(1.0, newValue))
                                    }
                                }
                            ),
                            in: 0.01...1.0,
                            step: 0.01
                        )
                        .tint(AppColors.signalMercury)

                        Text("Feeds the latest ~\(formatNumber(rollingTokenPreview)) tokens out of \(formatNumber(selectedContextWindow)) total model context tokens into the subconscious pass.")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }

                SettingsSection(title: "Salience & Epistemic Controls") {
                    VStack(alignment: .leading, spacing: 20) {
                        numericSliderRow(
                            title: "Max Memories",
                            valueText: "\(subsystemSettings.maxMemories)",
                            value: Binding(
                                get: { Double(subsystemSettings.maxMemories) },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.maxMemories = Int(newValue)
                                    }
                                }
                            ),
                            range: 1...50,
                            step: 1,
                            description: "Upper bound for injected salient memories in the background pass."
                        )

                        Divider()
                            .background(AppColors.divider)

                        numericSliderRow(
                            title: "Confidence Threshold",
                            valueText: "\(Int(subsystemSettings.confidenceThreshold * 100))%",
                            value: Binding(
                                get: { subsystemSettings.confidenceThreshold },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.confidenceThreshold = newValue
                                    }
                                }
                            ),
                            range: 0...1,
                            step: 0.05,
                            description: "Minimum confidence for memories eligible for subconscious injection."
                        )

                        Divider()
                            .background(AppColors.divider)

                        numericSliderRow(
                            title: "Min Salience Threshold",
                            valueText: "\(Int(subsystemSettings.minSalienceThreshold * 100))%",
                            value: Binding(
                                get: { subsystemSettings.minSalienceThreshold },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.minSalienceThreshold = newValue
                                    }
                                }
                            ),
                            range: 0...1,
                            step: 0.05,
                            description: "Suppresses low-salience memories during ranking."
                        )

                        Divider()
                            .background(AppColors.divider)

                        numericSliderRow(
                            title: "Relevance Weight",
                            valueText: String(format: "%.2f", subsystemSettings.relevanceWeight),
                            value: Binding(
                                get: { subsystemSettings.relevanceWeight },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.relevanceWeight = newValue
                                    }
                                }
                            ),
                            range: 0...2,
                            step: 0.05,
                            description: "Weight applied to semantic relevance while scoring memories."
                        )

                        Divider()
                            .background(AppColors.divider)

                        numericSliderRow(
                            title: "Confidence Weight",
                            valueText: String(format: "%.2f", subsystemSettings.confidenceWeight),
                            value: Binding(
                                get: { subsystemSettings.confidenceWeight },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.confidenceWeight = newValue
                                    }
                                }
                            ),
                            range: 0...2,
                            step: 0.05,
                            description: "Weight applied to memory confidence during ranking."
                        )

                        Divider()
                            .background(AppColors.divider)

                        numericSliderRow(
                            title: "Recency Weight",
                            valueText: String(format: "%.2f", subsystemSettings.recencyWeight),
                            value: Binding(
                                get: { subsystemSettings.recencyWeight },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.recencyWeight = newValue
                                    }
                                }
                            ),
                            range: 0...2,
                            step: 0.05,
                            description: "Weight applied to memory recency during ranking."
                        )

                        Divider()
                            .background(AppColors.divider)

                        SettingsToggleRowSimple(
                            title: "Include Epistemic Boundaries",
                            isOn: Binding(
                                get: { subsystemSettings.includeEpistemicBoundaries },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.includeEpistemicBoundaries = newValue
                                    }
                                }
                            )
                        )

                        Divider()
                            .background(AppColors.divider)

                        SettingsToggleRowSimple(
                            title: "Show Memory Confidence",
                            isOn: Binding(
                                get: { subsystemSettings.showConfidence },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.showConfidence = newValue
                                    }
                                }
                            )
                        )
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }

                SettingsSection(title: "Execution Guardrails") {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(
                            value: Binding(
                                get: { max(1, min(8, subsystemSettings.maxToolRounds)) },
                                set: { newValue in
                                    mutateSubconsciousSettings { updated in
                                        updated.maxToolRounds = max(1, min(8, newValue))
                                    }
                                }
                            ),
                            in: 1...8
                        ) {
                            HStack {
                                Text("Max Tool Rounds")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                Spacer()
                                Text("\(max(1, min(8, subsystemSettings.maxToolRounds)))")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.signalMercury)
                            }
                        }

                        Divider()
                            .background(AppColors.divider)

                        Text("Subconscious logging runs in the background after replies, injects salient memories, and may emit tool requests. Tool scope is restricted to `create_memory` only.")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
        .background(AppSurfaces.color(.contentBackground))
        .navigationTitle("Subconscious Logging")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func numericSliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text(valueText)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.signalMercury)
            }

            Slider(value: value, in: range, step: step)
                .tint(AppColors.signalMercury)

            Text(description)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
    }

    private func mutateSubconsciousSettings(_ mutate: (inout SubconsciousMemoryLoggingSettings) -> Void) {
        var updated = subsystemSettings
        mutate(&updated)
        Task {
            await viewModel.updateSetting(\.subconsciousMemoryLogging, .some(updated))
        }
    }

    private func builtInModels(for provider: AIProvider) -> [AIModel] {
        let registryModels = UnifiedModelRegistry.shared.chatModels(for: provider)
        return registryModels.isEmpty ? provider.availableModels : registryModels
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

