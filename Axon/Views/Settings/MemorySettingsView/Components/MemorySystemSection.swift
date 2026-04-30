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

                    Divider()
                        .background(AppColors.divider)

                    SettingsToggleRow(
                        title: "Subconscious Memory Logging",
                        description: "Run a background memory worker after each assistant reply",
                        isOn: Binding(
                            get: { viewModel.settings.resolvedSubconsciousMemoryLogging.enabled },
                            set: { newValue in
                                var updated = viewModel.settings.resolvedSubconsciousMemoryLogging
                                updated.enabled = newValue
                                Task {
                                    await viewModel.updateSetting(\.subconsciousMemoryLogging, .some(updated))
                                }
                            }
                        )
                    )

                    Divider()
                        .background(AppColors.divider)

                    NavigationLink(destination: SubconsciousMemoryLoggingDetailView(viewModel: viewModel)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Subconscious Logging Settings")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Select model, rolling context window, and memory salience controls")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()

                            Text(viewModel.settings.resolvedSubconsciousMemoryLogging.enabled ? "On" : "Off")
                                .font(AppTypography.labelSmall(.medium))
                                .foregroundColor(
                                    viewModel.settings.resolvedSubconsciousMemoryLogging.enabled
                                    ? AppColors.signalMercury
                                    : AppColors.textTertiary
                                )

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(8)
        }
    }
}
