//
//  UnifiedModelRow.swift
//  Axon
//
//  Unified model row that handles both built-in and custom models
//

import SwiftUI

struct UnifiedModelRow: View {
    let model: UnifiedModel
    let isSelected: Bool
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

                    // Pricing
                    if let customPricing = model.pricing {
                        HStack(spacing: 8) {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(AppColors.textTertiary)
                            Text(customPricing.formattedPricing())
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(1)
                        }
                    } else if case .builtIn(let aiModel) = model {
                        // Use PricingRegistry for built-in models
                        if let pricingText = builtInPricingText(for: aiModel) {
                            HStack(spacing: 8) {
                                Image(systemName: "dollarsign.circle")
                                    .foregroundColor(AppColors.textTertiary)
                                Text(pricingText)
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
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

    private func builtInPricingText(for model: AIModel) -> String? {
        if let key = PricingKeyResolver.canonicalKey(for: model.id) ?? PricingKeyResolver.canonicalKey(for: model.name) {
            let pricing = PricingRegistry.price(for: key)
            var parts: [String] = []
            parts.append(String(format: "$%.2f in / $%.2f out per 1M tokens", pricing.inputPerMTokUSD, pricing.outputPerMTokUSD))
            if let cached = pricing.cachedInputPerMTokUSD {
                parts.append(String(format: "cached: $%.2f", cached))
            }
            return parts.joined(separator: " · ")
        }
        return nil
    }
}
