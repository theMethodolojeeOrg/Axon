//
//  ModelTuningProviderAccordion.swift
//  Axon
//
//  Expandable accordion for a provider's models.
//

import SwiftUI

struct ModelTuningProviderAccordion: View {
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
