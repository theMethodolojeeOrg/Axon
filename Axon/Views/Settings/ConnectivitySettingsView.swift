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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Devices
            NavigationLink {
                DevicesSettingsView(viewModel: viewModel)
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
                ServerSettingsView(viewModel: viewModel)
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
                BackendSettingsView(viewModel: viewModel)
            } label: {
                SettingsCategoryRow(
                    icon: "server.rack",
                    iconColor: AppColors.signalCopper,
                    title: "Backend",
                    subtitle: backendSubtitle
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
