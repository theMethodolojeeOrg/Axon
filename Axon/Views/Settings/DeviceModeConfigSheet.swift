//
//  DeviceModeConfigSheet.swift
//  Axon
//
//  Configuration sheet for On-Device mode settings
//  Allows granular control over data storage, AI processing, and sync behavior
//

import SwiftUI

struct DeviceModeConfigSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var localConfig: DeviceModeConfig

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self._localConfig = State(initialValue: viewModel.settings.deviceModeConfig)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "gearshape.2.fill")
                                .font(.system(size: 28))
                                .foregroundColor(AppColors.signalMercury)

                            Text("On-Device Configuration")
                                .font(AppTypography.headlineMedium())
                                .foregroundColor(AppColors.textPrimary)
                        }

                        Text("Configure how Axon handles data, AI processing, and synchronization when in On-Device mode.")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.bottom, 8)

                    // Data Storage Section
                    ConfigSection(title: "Data Storage", icon: "externaldrive.fill") {
                        ForEach(DataStorageMode.allCases) { mode in
                            ConfigOptionCard(
                                title: mode.displayName,
                                description: mode.description,
                                icon: mode.icon,
                                isSelected: localConfig.dataStorage == mode
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    localConfig.dataStorage = mode
                                }
                            }
                        }
                    }

                    // AI Processing Section
                    ConfigSection(title: "AI Processing", icon: "cpu.fill") {
                        ForEach(AIProcessingMode.allCases) { mode in
                            ConfigOptionCard(
                                title: mode.displayName,
                                description: mode.description,
                                icon: mode.icon,
                                isSelected: localConfig.aiProcessing == mode
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    localConfig.aiProcessing = mode
                                }
                            }
                        }
                    }

                    // Memory & Learning Section
                    ConfigSection(title: "Memory & Learning", icon: "brain.head.profile") {
                        ForEach(MemoryStorageMode.allCases) { mode in
                            ConfigOptionCard(
                                title: mode.displayName,
                                description: mode.description,
                                icon: mode.icon,
                                isSelected: localConfig.memoryStorage == mode
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    localConfig.memoryStorage = mode
                                }
                            }
                        }
                    }

                    // Cloud Sync Provider Section
                    CloudSyncSection(localConfig: $localConfig)

                    // Sync Options Section
                    ConfigSection(title: "Sync Options", icon: "arrow.triangle.2.circlepath") {
                        VStack(spacing: 12) {
                            ConfigToggleRow(
                                title: "Show Sync Status",
                                description: "Display sync indicators in the UI",
                                icon: "eye.fill",
                                isOn: $localConfig.showSyncStatus
                            )

                            ConfigToggleRow(
                                title: "Auto-Sync on Connect",
                                description: "Automatically sync when network available",
                                icon: "wifi",
                                isOn: $localConfig.autoSyncOnConnect
                            )
                        }
                    }

                    // Sync Status (if pending operations)
                    SyncStatusCard(viewModel: viewModel)

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(AppColors.substratePrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveConfiguration()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.signalMercury)
                }
            }
        }
    }

    private func saveConfiguration() {
        Task {
            await viewModel.updateSetting(\.deviceModeConfig, localConfig)
            dismiss()
        }
    }
}

// MARK: - Config Section

private struct ConfigSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.signalMercury)

                Text(title.uppercased())
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            content
        }
    }
}

// MARK: - Config Option Card

private struct ConfigOptionCard: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? AppColors.signalMercury.opacity(0.2) : AppColors.substrateSecondary)
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppColors.signalMercury)
                } else {
                    Circle()
                        .stroke(AppColors.glassBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.08) : AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppColors.signalMercury.opacity(0.3) : AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Config Toggle Row

private struct ConfigToggleRow: View {
    let title: String
    let description: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(AppColors.substrateSecondary)
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.signalMercury)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)

                Text(description)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Toggle
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColors.signalMercury)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.substrateSecondary)
        )
    }
}

// MARK: - Cloud Sync Section

private struct CloudSyncSection: View {
    @Binding var localConfig: DeviceModeConfig
    @StateObject private var cloudKitService = CloudKitSyncService.shared
    @StateObject private var iCloudKVSync = iCloudKeyValueSync.shared

    var body: some View {
        ConfigSection(title: "Cross-Device Sync", icon: "icloud.fill") {
            VStack(spacing: 12) {
                ForEach(CloudSyncProvider.allCases) { provider in
                    CloudSyncProviderCard(
                        provider: provider,
                        isSelected: localConfig.cloudSyncProvider == provider,
                        isAvailable: provider == .iCloud ? cloudKitService.isCloudKitAvailable : true
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            localConfig.cloudSyncProvider = provider
                        }
                    }
                }

                // iCloud status message
                if localConfig.cloudSyncProvider == .iCloud {
                    VStack(spacing: 8) {
                        // CloudKit status (for conversation sync)
                        HStack(spacing: 8) {
                            Image(systemName: cloudKitService.isCloudKitAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(cloudKitService.isCloudKitAvailable ? AppColors.accentSuccess : AppColors.accentWarning)

                            Text(cloudKitService.isCloudKitAvailable
                                 ? "Conversations: Ready to sync"
                                 : "Sign in to iCloud in Settings")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()
                        }

                        // Key-Value status (for settings sync)
                        HStack(spacing: 8) {
                            Image(systemName: iCloudKVSync.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(iCloudKVSync.isAvailable ? AppColors.accentSuccess : AppColors.accentWarning)

                            Text(iCloudKVSync.isAvailable
                                 ? "Settings: Syncing across devices"
                                 : "Settings sync unavailable")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill((cloudKitService.isCloudKitAvailable ? AppColors.accentSuccess : AppColors.accentWarning).opacity(0.1))
                    )
                }

                // Custom Server note
                if localConfig.cloudSyncProvider == .firestore {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(AppColors.signalMercury)

                        Text("Configure your server in the API Server settings tab")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)

                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.signalMercury.opacity(0.1))
                    )
                }
            }
        }
    }
}

// MARK: - Cloud Sync Provider Card

private struct CloudSyncProviderCard: View {
    let provider: CloudSyncProvider
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? AppColors.signalMercury.opacity(0.2) : AppColors.substrateSecondary)
                        .frame(width: 44, height: 44)

                    Image(systemName: provider.icon)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(provider.displayName)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if provider == .iCloud && !isAvailable {
                            Text("Unavailable")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentWarning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(AppColors.accentWarning.opacity(0.2))
                                )
                        }
                    }

                    Text(provider.description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppColors.signalMercury)
                } else {
                    Circle()
                        .stroke(AppColors.glassBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.08) : AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppColors.signalMercury.opacity(0.3) : AppColors.glassBorder, lineWidth: 1)
                    )
            )
            .opacity(provider == .iCloud && !isAvailable ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(provider == .iCloud && !isAvailable)
    }
}

// MARK: - Sync Status Card

private struct SyncStatusCard: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var conversationService = ConversationService.shared

    var body: some View {
        if conversationService.pendingOperationsCount > 0 || conversationService.isSyncing {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.signalMercury)

                    Text("SYNC STATUS")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                HStack(spacing: 16) {
                    // Status icon
                    ZStack {
                        Circle()
                            .fill(conversationService.isSyncing ? AppColors.signalMercury.opacity(0.2) : AppColors.accentWarning.opacity(0.2))
                            .frame(width: 44, height: 44)

                        if conversationService.isSyncing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                        } else {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                                .font(.system(size: 18))
                                .foregroundColor(AppColors.accentWarning)
                        }
                    }

                    // Status text
                    VStack(alignment: .leading, spacing: 4) {
                        Text(conversationService.isSyncing ? "Syncing..." : "Pending Operations")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("\(conversationService.pendingOperationsCount) operations waiting to sync")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    // Sync button
                    if !conversationService.isSyncing {
                        Button(action: {
                            Task {
                                await conversationService.syncPendingOperations()
                            }
                        }) {
                            Text("Sync Now")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(AppColors.signalMercury)
                                )
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.substrateSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.glassBorder, lineWidth: 1)
                        )
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DeviceModeConfigSheet(viewModel: SettingsViewModel.shared)
}
