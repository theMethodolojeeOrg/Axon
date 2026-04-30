//
//  ProviderSummaryRow.swift
//  Axon
//
//  Expandable row displaying AI provider details with model information.
//

import SwiftUI

struct ProviderSummaryRow: View {
    let provider: ProviderConfig

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                            .font(AppTypography.titleSmall())
                            .foregroundColor(AppColors.textPrimary)

                        Text("\(provider.models.count) models")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(12)
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(provider.models) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName)
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textPrimary)

                                HStack(spacing: 8) {
                                    Text(model.category.rawValue.capitalized)
                                        .font(AppTypography.labelSmall())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(categoryColor(model.category).opacity(0.2))
                                        .foregroundColor(categoryColor(model.category))
                                        .cornerRadius(4)

                                    Text("\(model.contextWindow / 1000)K context")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$\(model.pricing.inputPerMillion, specifier: "%.2f")/M in")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                                Text("$\(model.pricing.outputPerMillion, specifier: "%.2f")/M out")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 8)
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
        )
    }

    private func categoryColor(_ category: ModelCategory) -> Color {
        switch category {
        case .frontier: return AppColors.signalMercury
        case .reasoning: return AppColors.accentWarning
        case .fast: return AppColors.accentSuccess
        case .legacy: return AppColors.textTertiary
        }
    }
}
