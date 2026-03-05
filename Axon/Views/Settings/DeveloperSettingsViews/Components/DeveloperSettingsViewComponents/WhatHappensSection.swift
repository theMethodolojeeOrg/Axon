//
//  WhatHappensSection.swift
//  Axon
//
//  Lists what gets reset and preserved during demo mode.
//

import SwiftUI

struct WhatHappensSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsFeatureRow(icon: "checkmark.circle.fill", text: "Onboarding shown again", iconColor: AppColors.accentSuccess)
            SettingsFeatureRow(icon: "checkmark.circle.fill", text: "Conversations cleared locally", iconColor: AppColors.accentSuccess)
            SettingsFeatureRow(icon: "checkmark.circle.fill", text: "Memories cleared locally", iconColor: AppColors.accentSuccess)
            SettingsFeatureRow(icon: "checkmark.circle.fill", text: "Settings reset to defaults", iconColor: AppColors.accentSuccess)

            Divider()
                .background(AppColors.divider)
                .padding(.vertical, 4)

            SettingsFeatureRow(icon: "lock.shield.fill", text: "API keys preserved", iconColor: AppColors.signalMercury)
            SettingsFeatureRow(icon: "lock.shield.fill", text: "Account stays signed in", iconColor: AppColors.signalMercury)
            SettingsFeatureRow(icon: "lock.shield.fill", text: "Server data untouched", iconColor: AppColors.signalMercury)
        }
        .padding()
    }
}

#Preview {
    SettingsSection(title: "What Happens") {
        WhatHappensSection()
    }
    .background(AppColors.substratePrimary)
}
