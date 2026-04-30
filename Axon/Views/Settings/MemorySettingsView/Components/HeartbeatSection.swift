//
//  HeartbeatSection.swift
//  Axon
//
//  Heartbeat settings section
//

import SwiftUI

struct HeartbeatSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Heartbeat") {
            VStack(spacing: 16) {
                SettingsToggleRow(
                    title: "Enable Heartbeat",
                    description: "Run periodic internal check-ins and update the internal thread",
                    isOn: Binding(
                        get: { viewModel.settings.heartbeatSettings.enabled },
                        set: { newValue in
                            Task {
                                var heartbeat = viewModel.settings.heartbeatSettings
                                heartbeat.enabled = newValue
                                await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                            }
                        }
                    )
                )

                if viewModel.settings.heartbeatSettings.enabled {
                    Divider()
                        .background(AppColors.divider)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Interval")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text(intervalLabel(seconds: viewModel.settings.heartbeatSettings.intervalSeconds))
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.heartbeatSettings.intervalSeconds) },
                                set: { newValue in
                                    Task {
                                        var heartbeat = viewModel.settings.heartbeatSettings
                                        heartbeat.intervalSeconds = Int(newValue)
                                        await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                                    }
                                }
                            ),
                            in: 300...86400,
                            step: 300
                        )
                        .tint(AppColors.signalMercury)
                    }

                    Divider()
                        .background(AppColors.divider)

                    HStack {
                        Text("Delivery Profile")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Picker("", selection: Binding(
                            get: { viewModel.settings.heartbeatSettings.deliveryProfileId },
                            set: { newValue in
                                Task {
                                    var heartbeat = viewModel.settings.heartbeatSettings
                                    heartbeat.deliveryProfileId = newValue
                                    await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                                }
                            }
                        )) {
                            ForEach(viewModel.settings.heartbeatSettings.deliveryProfiles, id: \.id) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider()
                        .background(AppColors.divider)

                    SettingsToggleRowSimple(
                        title: "Allow Heartbeat Notifications",
                        isOn: Binding(
                            get: { viewModel.settings.heartbeatSettings.allowNotifications },
                            set: { newValue in
                                Task {
                                    var heartbeat = viewModel.settings.heartbeatSettings
                                    heartbeat.allowNotifications = newValue
                                    await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                                }
                            }
                        )
                    )

                    SettingsToggleRowSimple(
                        title: "Allow Background Heartbeat",
                        isOn: Binding(
                            get: { viewModel.settings.heartbeatSettings.allowBackground },
                            set: { newValue in
                                Task {
                                    var heartbeat = viewModel.settings.heartbeatSettings
                                    heartbeat.allowBackground = newValue
                                    await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                                }
                            }
                        )
                    )
                }
            }
            .padding()
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(8)
        }
    }

    private func intervalLabel(seconds: Int) -> String {
        if seconds < 3600 {
            return "\(max(1, seconds / 60))m"
        }
        let hours = Double(seconds) / 3600.0
        return hours < 24 ? String(format: "%.1fh", hours) : String(format: "%.0fh", hours)
    }
}
