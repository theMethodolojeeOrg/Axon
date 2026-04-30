//
//  CustomProviderCard.swift
//  Axon
//
//  Custom provider display card with expandable models
//

import SwiftUI

struct CustomProviderCard: View {
    let provider: CustomProviderConfig
    let providerIndex: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.providerName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(provider.apiEndpoint)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Model count badge
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                    Text("\(provider.models.count)")
                        .font(AppTypography.labelSmall())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.signalMercury.opacity(0.2))
                .cornerRadius(12)
                .foregroundColor(AppColors.signalMercury)

                // Actions menu
                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            // Expand/Collapse models
            if !provider.models.isEmpty {
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text(isExpanded ? "Hide Models" : "Show Models")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.signalMercury)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.signalMercury)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                if isExpanded {
                    VStack(spacing: 8) {
                        ForEach(Array(provider.models.enumerated()), id: \.element.id) { modelIndex, model in
                            ModelInfoRow(
                                model: model,
                                providerIndex: providerIndex,
                                modelIndex: modelIndex + 1,
                                providerName: provider.providerName
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppSurfaces.color(.cardBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
                )
        )
    }
}
