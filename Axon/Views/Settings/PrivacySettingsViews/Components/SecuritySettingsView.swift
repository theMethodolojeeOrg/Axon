//
//  SecuritySettingsView.swift
//  Axon
//
//  Security and authentication settings
//

import SwiftUI

struct SecuritySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var biometricService = BiometricAuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // App Lock Section
            SettingsSection(title: "App Lock") {
                VStack(spacing: 16) {
                    // Enable App Lock Toggle
                    Toggle(isOn: Binding(
                        get: { viewModel.settings.appLockEnabled },
                        set: { newValue in
                            Task {
                                await viewModel.updateSetting(\.appLockEnabled, newValue)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Require Authentication")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Lock Axon when you leave the app")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .tint(AppColors.signalMercury)

                    if viewModel.settings.appLockEnabled {
                        Divider()
                            .background(AppColors.divider)

                        // Biometric Toggle
                        if biometricService.isAvailable {
                            Toggle(isOn: Binding(
                                get: { viewModel.settings.biometricEnabled },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateSetting(\.biometricEnabled, newValue)
                                    }
                                }
                            )) {
                                HStack(spacing: 12) {
                                    Image(systemName: biometricService.biometricType.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(AppColors.signalMercury)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Use \(biometricService.biometricType.displayName)")
                                            .font(AppTypography.bodyMedium(.medium))
                                            .foregroundColor(AppColors.textPrimary)

                                        Text("Quick unlock with \(biometricService.biometricType.displayName)")
                                            .font(AppTypography.bodySmall())
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                }
                            }
                            .tint(AppColors.signalMercury)

                            Divider()
                                .background(AppColors.divider)
                        }

                        // Passcode Fallback Toggle
                        Toggle(isOn: Binding(
                            get: { viewModel.settings.passcodeEnabled },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.passcodeEnabled, newValue)
                                }
                            }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppColors.signalMercury)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Passcode Fallback")
                                        .font(AppTypography.bodyMedium(.medium))
                                        .foregroundColor(AppColors.textPrimary)

                                    Text("Allow device passcode as backup")
                                        .font(AppTypography.bodySmall())
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                        }
                        .tint(AppColors.signalMercury)

                        Divider()
                            .background(AppColors.divider)

                        // Lock Timeout
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Require Authentication")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Picker("Timeout", selection: Binding(
                                get: { viewModel.settings.lockTimeout },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateSetting(\.lockTimeout, newValue)
                                    }
                                }
                            )) {
                                ForEach(LockTimeout.allCases, id: \.self) { timeout in
                                    Text(timeout.displayName).tag(timeout)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }

            // Privacy Section
            SettingsSection(title: "Privacy") {
                VStack(spacing: 16) {
                    // Hide in App Switcher
                    Toggle(isOn: Binding(
                        get: { viewModel.settings.hideContentInAppSwitcher },
                        set: { newValue in
                            Task {
                                await viewModel.updateSetting(\.hideContentInAppSwitcher, newValue)
                            }
                        }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.on.rectangle.slash")
                                .font(.system(size: 20))
                                .foregroundColor(AppColors.signalMercury)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hide in App Switcher")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Blur content when switching apps")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }
                    .tint(AppColors.signalMercury)
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }

            // Device Identity Section
            SettingsSection(title: "Device Identity") {
                VStack(spacing: 16) {
                    if let deviceInfo = DeviceIdentity.shared.getDeviceInfo() {
                        // Device ID
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Device ID")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                                Text(deviceInfo.shortId)
                                    .font(AppTypography.displayMedium())
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            Spacer()
                            Button(action: {
                                AppClipboard.copy(deviceInfo.deviceId)
                                viewModel.showSuccessMessage("Device ID copied")
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.signalMercury)
                            }
                        }

                        Divider()
                            .background(AppColors.divider)

                        // Device Model
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Device Model")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                                Text(deviceInfo.deviceModel)
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            Spacer()
                        }

                        Divider()
                            .background(AppColors.divider)

                        // System Info
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("System")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                                Text("\(deviceInfo.systemName) \(deviceInfo.systemVersion)")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            Spacer()
                        }

                        Divider()
                            .background(AppColors.divider)

                        // Created Date
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Identity Created")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                                Text(deviceInfo.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }

            // Biometric Status
            if !biometricService.isAvailable {
                SettingsSection(title: "Biometric Status") {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalHematite)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Biometrics Unavailable")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text(biometricService.authError?.localizedDescription ?? "Set up Face ID or Touch ID in device Settings")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        SecuritySettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppSurfaces.color(.contentBackground))
}
