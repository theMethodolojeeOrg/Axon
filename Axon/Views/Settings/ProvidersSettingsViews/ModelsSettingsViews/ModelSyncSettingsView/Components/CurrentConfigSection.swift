//
//  CurrentConfigSection.swift
//  Axon
//
//  Section displaying the active model configuration.
//

import SwiftUI

struct CurrentConfigSection: View {
    let configService: ModelConfigurationService

    var body: some View {
        UnifiedSettingsSection(title: "Active Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                if let catalog = configService.activeCatalog {
                    SettingsCard(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Version \(catalog.version)")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Updated \(catalog.lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(catalog.providers.count) Providers")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)

                                let totalModels = catalog.providers.reduce(0) { $0 + $1.models.count }
                                Text("\(totalModels) Models")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }
                } else {
                    SettingsCard(padding: 12) {
                        Text("No configuration loaded")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 12))
                    Text("Source: AxonProviderKit")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.textTertiary)
            }
        }
    }
}
