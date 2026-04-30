//
//  ModelInfoRow.swift
//  Axon
//
//  Model information display row
//

import SwiftUI

struct ModelInfoRow: View {
    let model: CustomModelConfig
    let providerIndex: Int
    let modelIndex: Int
    let providerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.displayName(providerName: providerName))
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)

            Text(model.modelCode)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)

            Text(model.displayDescription(providerIndex: providerIndex, modelIndex: modelIndex))
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(
                    String(format: "%.0fK context", Double(model.contextWindow) / 1000),
                    systemImage: "brain.head.profile"
                )
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)

                if let pricing = model.pricing {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                    Text(pricing.formattedPricing())
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(AppSurfaces.color(.contentBackground))
        .cornerRadius(6)
    }
}
