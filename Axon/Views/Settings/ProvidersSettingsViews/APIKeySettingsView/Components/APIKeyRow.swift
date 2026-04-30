//
//  APIKeyRow.swift
//  Axon
//
//  API key row component for built-in providers
//

import SwiftUI

struct APIKeyRow: View {
    let provider: APIProvider
    let isConfigured: Bool
    var isAdminKey: Bool = false
    let onEdit: () -> Void
    let onClear: () -> Void
    let onGetKey: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "key.fill")
                .foregroundColor(isAdminKey ? AppColors.signalCopper : AppColors.signalMercury)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.displayName)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(provider.description)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)

                ConfigurationStatusBadge(isConfigured: isConfigured, isRequired: isAdminKey)
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

                Divider()

                Button(action: onGetKey) {
                    Label("Get API Key", systemImage: "link")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .foregroundColor(AppColors.textSecondary)
                    .font(.system(size: 24))
            }
        }
        .padding()
        .background(isAdminKey ? AppColors.signalCopper.opacity(0.05) : AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isAdminKey ? AppColors.signalCopper.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}
