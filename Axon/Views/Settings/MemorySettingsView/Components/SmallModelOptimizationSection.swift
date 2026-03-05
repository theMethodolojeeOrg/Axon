//
//  SmallModelOptimizationSection.swift
//  Axon
//
//  Small model optimization settings section
//

import SwiftUI

struct SmallModelOptimizationSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Small Model Optimization") {
            VStack(spacing: 16) {
                SettingsToggleRow(
                    title: "Auto-Detect Small Models",
                    description: "Automatically optimize context for small/quantized models (1B-3B, 4bit)",
                    isOn: Binding(
                        get: { viewModel.settings.heuristicsSettings.smallModelOptimization.enabled },
                        set: { newValue in
                            Task {
                                var heuristics = viewModel.settings.heuristicsSettings
                                heuristics.smallModelOptimization.enabled = newValue
                                await viewModel.updateSetting(\.heuristicsSettings, heuristics)
                            }
                        }
                    )
                )

                if viewModel.settings.heuristicsSettings.smallModelOptimization.enabled {
                    Divider()
                        .background(AppColors.divider)

                    SettingsToggleRow(
                        title: "Use Heuristics Only",
                        description: "Inject compressed heuristics instead of raw memories for small models",
                        isOn: Binding(
                            get: { viewModel.settings.heuristicsSettings.smallModelOptimization.useHeuristicsOnly },
                            set: { newValue in
                                Task {
                                    var heuristics = viewModel.settings.heuristicsSettings
                                    heuristics.smallModelOptimization.useHeuristicsOnly = newValue
                                    await viewModel.updateSetting(\.heuristicsSettings, heuristics)
                                }
                            }
                        )
                    )

                    Divider()
                        .background(AppColors.divider)

                    SettingsToggleRow(
                        title: "Skip Conversation Summary",
                        description: "Don't inject recent conversation summaries for small models",
                        isOn: Binding(
                            get: { viewModel.settings.heuristicsSettings.smallModelOptimization.skipConversationSummary },
                            set: { newValue in
                                Task {
                                    var heuristics = viewModel.settings.heuristicsSettings
                                    heuristics.smallModelOptimization.skipConversationSummary = newValue
                                    await viewModel.updateSetting(\.heuristicsSettings, heuristics)
                                }
                            }
                        )
                    )

                    Divider()
                        .background(AppColors.divider)

                    // Token budget slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Context Token Budget")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("\(viewModel.settings.heuristicsSettings.smallModelOptimization.smallModelTokenBudget) tokens")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.heuristicsSettings.smallModelOptimization.smallModelTokenBudget) },
                                set: { newValue in
                                    Task {
                                        var heuristics = viewModel.settings.heuristicsSettings
                                        heuristics.smallModelOptimization.smallModelTokenBudget = Int(newValue)
                                        await viewModel.updateSetting(\.heuristicsSettings, heuristics)
                                    }
                                }
                            ),
                            in: 200...1500,
                            step: 100
                        )
                        .tint(AppColors.signalMercury)

                        Text("Maximum tokens reserved for context injection in small models")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }
}
