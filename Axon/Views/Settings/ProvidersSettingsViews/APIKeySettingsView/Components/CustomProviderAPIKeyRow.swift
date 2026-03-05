//
//  CustomProviderAPIKeyRow.swift
//  Axon
//
//  API key row component for custom providers
//

import SwiftUI

struct CustomProviderAPIKeyRow: View {
    let provider: CustomProviderConfig
    let isConfigured: Bool
    let onEdit: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "server.rack")
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.providerName)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(provider.apiEndpoint)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)

                ConfigurationStatusBadge(isConfigured: isConfigured)
            }

            Spacer()

            Menu {
                Button(action: onEdit) {
                    Label(isConfigured ? "Edit Key" : "Add Key", systemImage: "pencil")
                }

                if isConfigured {
                    Button(role: .destructive, action: onClear) {
                        Label("Remove Key", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .foregroundColor(AppColors.textSecondary)
                    .font(.system(size: 24))
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}
