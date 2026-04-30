//
//  ModelOverrideSheet.swift
//  Axon
//
//  Sheet for editing per-model generation parameter overrides.
//

import SwiftUI

struct ModelOverrideSheet: View {
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
            AppSurfaces.color(.contentBackground)
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
                .font(AppTypography.codeSmall())
                .foregroundColor(AppColors.textTertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurfaces.color(.cardBackground))
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
        .background(AppSurfaces.color(.cardBackground))
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
