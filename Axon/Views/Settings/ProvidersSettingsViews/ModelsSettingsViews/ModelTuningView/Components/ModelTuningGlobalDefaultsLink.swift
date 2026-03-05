//
//  ModelTuningGlobalDefaultsLink.swift
//  Axon
//
//  Navigation link to Global Defaults settings.
//

import SwiftUI

struct ModelTuningGlobalDefaultsLink: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        NavigationLink(destination: ModelConfigurationView(viewModel: viewModel)) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Global Defaults")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text("Fallback settings when no override is active")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
