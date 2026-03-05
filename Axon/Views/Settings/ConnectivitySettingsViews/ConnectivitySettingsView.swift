//
//  ConnectivitySettingsView.swift
//  Axon
//
//  Category view for connectivity-related settings: Devices, API Server, and Backend
//

import SwiftUI

struct ConnectivitySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var devicePresenceService = DevicePresenceService.shared
    @StateObject private var bridgeManager = BridgeConnectionManager.shared
    @StateObject private var bridgeSettings = BridgeSettingsStorage.shared

    // MARK: - Dynamic Subtitles

    private var devicesSubtitle: String {
        let deviceCount = devicePresenceService.allDevices.count
        if deviceCount == 0 {
            return "No devices synced"
        } else if deviceCount == 1 {
            return "1 device"
        } else {
            return "\(deviceCount) devices"
        }
    }

    private var serverSubtitle: String {
        if viewModel.isServerRunning {
            return "Running on port \(viewModel.settings.serverPort)"
        }
        return "Disabled"
    }

    private var backendSubtitle: String {
        if BackendConfig.shared.isBackendConfigured {
            return "Connected"
        }
        return "Local only"
    }

    private var axonBridgeSubtitle: String {
        let defaultProfile = bridgeSettings.defaultConnectionProfile()
        let defaultLabel = defaultProfile?.name ?? "No default profile"

        if bridgeManager.isConnected {
            return "Connected • \(defaultLabel)"
        }

        if bridgeManager.isConnecting {
            return "Connecting • \(defaultLabel)"
        }

        return "Disconnected • \(defaultLabel)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Devices
            NavigationLink {
                SettingsSubviewContainer {
                    DevicesSettingsView(viewModel: viewModel)
                }
            } label: {
                SettingsCategoryRow(
                    icon: "laptopcomputer.and.iphone",
                    iconColor: AppColors.signalMercury,
                    title: "Devices",
                    subtitle: devicesSubtitle
                )
            }
            .buttonStyle(.plain)

            // API Server
            NavigationLink {
                SettingsSubviewContainer {
                    ServerSettingsView(viewModel: viewModel)
                }
            } label: {
                SettingsCategoryRow(
                    icon: "network",
                    iconColor: AppColors.signalLichen,
                    title: "API Server",
                    subtitle: serverSubtitle
                )
            }
            .buttonStyle(.plain)

            // Backend
            NavigationLink {
                SettingsSubviewContainer {
                    BackendSettingsView(viewModel: viewModel)
                }
            } label: {
                SettingsCategoryRow(
                    icon: "server.rack",
                    iconColor: AppColors.signalCopper,
                    title: "Backend",
                    subtitle: backendSubtitle
                )
            }
            .buttonStyle(.plain)

            // Axon Bridge
            NavigationLink {
                SettingsSubviewContainer {
                    AxonBridgeSettingsView()
                }
            } label: {
                SettingsCategoryRow(
                    icon: "personalhotspot",
                    iconColor: AppColors.signalMercury,
                    title: "Axon Bridge",
                    subtitle: axonBridgeSubtitle
                )
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Connectivity")
    }
}

#Preview {
    NavigationStack {
        ConnectivitySettingsView(viewModel: SettingsViewModel.shared)
    }
}
