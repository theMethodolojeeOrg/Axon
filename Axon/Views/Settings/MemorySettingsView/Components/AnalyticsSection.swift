//
//  AnalyticsSection.swift
//  Axon
//
//  Analytics settings section
//

import SwiftUI

struct AnalyticsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Analytics") {
            SettingsToggleRow(
                title: "Enable Usage Analytics",
                description: "Help improve the app by sharing anonymous usage data",
                isOn: Binding(
                    get: { viewModel.settings.memoryAnalyticsEnabled },
                    set: { newValue in
                        Task {
                            await viewModel.updateSetting(\.memoryAnalyticsEnabled, newValue)
                        }
                    }
                )
            )
            .padding()
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(8)
        }
    }
}
