//
//  ModelSyncHeaderSection.swift
//  Axon
//
//  Header section with description and status badge for model sync settings.
//

import SwiftUI

struct ModelSyncHeaderSection: View {
    let configService: ModelConfigurationService
    let syncService: PerplexityModelSyncService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .foregroundColor(AppColors.signalMercury)

            Text("Manage AI model definitions and pricing. Optionally sync model data via Perplexity.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            configStatusBadge
        }
        .padding()
        .background(AppColors.signalMercury.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var configStatusBadge: some View {
        if configService.isSyncing {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing...")
                    .font(AppTypography.labelSmall())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.accentWarning.opacity(0.2))
            .cornerRadius(8)
        } else if configService.hasPendingDraft {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.clock")
                Text("Draft Available")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.accentWarning)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.accentWarning.opacity(0.2))
            .cornerRadius(8)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Up to Date")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.accentSuccess)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.accentSuccess.opacity(0.2))
            .cornerRadius(8)
        }
    }
}
