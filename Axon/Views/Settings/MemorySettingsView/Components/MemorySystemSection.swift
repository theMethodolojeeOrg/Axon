//
//  MemorySystemSection.swift
//  Axon
//
//  Memory system enable/disable settings section
//

import SwiftUI

struct MemorySystemSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Memory System") {
            VStack(spacing: 16) {
                SettingsToggleRow(
                    title: "Enable Memory",
                    description: "Allow the Axon to remember facts about you and learn about itself in your context across conversations",
                    isOn: Binding(
                        get: { viewModel.settings.memoryEnabled },
                        set: { newValue in
                            Task {
                                await viewModel.updateSetting(\.memoryEnabled, newValue)
                            }
                        }
                    )
                )

                if viewModel.settings.memoryEnabled {
                    Divider()
                        .background(AppColors.divider)

                    SettingsToggleRow(
                        title: "Auto-Inject Memories",
                        description: "Automatically include relevant memories in conversations",
                        isOn: Binding(
                            get: { viewModel.settings.memoryAutoInject },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.memoryAutoInject, newValue)
                                }
                            }
                        )
                    )
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }
}
