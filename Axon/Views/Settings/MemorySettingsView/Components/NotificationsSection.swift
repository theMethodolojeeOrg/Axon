//
//  NotificationsSection.swift
//  Axon
//
//  Notifications settings section
//

import SwiftUI

struct NotificationsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Notifications") {
            SettingsToggleRow(
                title: "Enable Notifications",
                description: "Allow the agent to send local notifications",
                isOn: Binding(
                    get: { viewModel.settings.notificationsEnabled },
                    set: { newValue in
                        Task {
                            await viewModel.updateSetting(\.notificationsEnabled, newValue)
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
