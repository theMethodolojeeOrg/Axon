//
//  PrivacySettingsView.swift
//  Axon
//
//  Category view for privacy-related settings: Consent (Sovereignty) and Security
//

import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var sovereigntyService = SovereigntyService.shared

    // MARK: - Dynamic Subtitles

    private var consentSubtitle: String {
        if sovereigntyService.activeCovenant != nil {
            return "Active covenant"
        } else {
            return "No covenant established"
        }
    }

    private var securitySubtitle: String {
        if viewModel.settings.appLockEnabled {
            if viewModel.settings.biometricEnabled {
                return "App Lock with biometrics"
            }
            return "App Lock enabled"
        }
        return "App Lock disabled"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Consent (Sovereignty)
            NavigationLink {
                SovereigntySettingsView(viewModel: viewModel)
            } label: {
                SettingsCategoryRow(
                    icon: "shield.checkered",
                    iconColor: AppColors.signalMercury,
                    title: "Consent",
                    subtitle: consentSubtitle
                )
            }
            .buttonStyle(.plain)

            // Security
            NavigationLink {
                SecuritySettingsView(viewModel: viewModel)
            } label: {
                SettingsCategoryRow(
                    icon: "lock.shield.fill",
                    iconColor: AppColors.signalLichen,
                    title: "Security",
                    subtitle: securitySubtitle
                )
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Privacy")
    }
}

#Preview {
    NavigationStack {
        PrivacySettingsView(viewModel: SettingsViewModel.shared)
    }
}
