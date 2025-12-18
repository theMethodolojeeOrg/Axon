//
//  DataManagementView.swift
//  Axon
//
//  Unified view for all data management settings.
//  This is the single source of truth for data storage, sync, and AI processing configuration.
//

import SwiftUI

struct DataManagementView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var cloudKitService = CloudKitSyncService.shared
    @StateObject private var iCloudKVSync = iCloudKeyValueSync.shared
    @StateObject private var conversationService = ConversationService.shared

    @State private var localConfig: DeviceModeConfig

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self._localConfig = State(initialValue: viewModel.settings.deviceModeConfig)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Sync Disabled Warning
                if localConfig.cloudSyncProvider == .none && cloudKitService.isCloudKitAvailable {
                    SyncDisabledWarningBanner {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            localConfig.cloudSyncProvider = .iCloud
                            saveConfiguration()
                        }
                    }
                }

                // MARK: - Where Data Syncs
                DataManagementSection(title: "Cross-Device Sync", icon: "icloud.fill") {
                    VStack(spacing: 12) {
                        ForEach(CloudSyncProvider.allCases) { provider in
                            let available = providerAvailable(provider)

                            DataManagementOptionCard(
                                title: provider.displayName,
                                description: provider.description,
                                icon: provider.icon,
                                isSelected: localConfig.cloudSyncProvider == provider,
                                isAvailable: available
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    localConfig.cloudSyncProvider = provider
                                    saveConfiguration()
                                }
                            }
                        }

                        // iCloud status message
                        if localConfig.cloudSyncProvider == .iCloud {
                            iCloudStatusView
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

                // MARK: - Where Data Lives
                DataManagementSection(title: "Data Storage", icon: "externaldrive.fill") {
                    ForEach(DataStorageMode.allCases) { mode in
                        DataManagementOptionCard(
                            title: mode.displayName,
                            description: mode.description,
                            icon: mode.icon,
                            isSelected: localConfig.dataStorage == mode
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                localConfig.dataStorage = mode
                                saveConfiguration()
                            }
                        }
                    }
                }

                // MARK: - AI Processing
                DataManagementSection(title: "AI Processing", icon: "cpu.fill") {
                    ForEach(AIProcessingMode.allCases) { mode in
                        DataManagementOptionCard(
                            title: mode.displayName,
                            description: mode.description,
                            icon: mode.icon,
                            isSelected: localConfig.aiProcessing == mode
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                localConfig.aiProcessing = mode
                                saveConfiguration()
                            }
                        }
                    }
                }

                // MARK: - Memory & Learning
                DataManagementSection(title: "Memory & Learning", icon: "brain.head.profile") {
                    ForEach(MemoryStorageMode.allCases) { mode in
                        DataManagementOptionCard(
                            title: mode.displayName,
                            description: mode.description,
                            icon: mode.icon,
                            isSelected: localConfig.memoryStorage == mode
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                localConfig.memoryStorage = mode
                                saveConfiguration()
                            }
                        }
                    }
                }

                // MARK: - Sync Options
                DataManagementSection(title: "Sync Options", icon: "arrow.triangle.2.circlepath") {
                    VStack(spacing: 12) {
                        // Settings sync interval
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.substrateSecondary)
                                    .frame(width: 40, height: 40)

                                Image(systemName: "timer")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppColors.signalMercury)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Settings Sync Interval")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)

                                Text("How often Axon syncs settings in the background")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()

                            Stepper(
                                "",
                                value: Binding(
                                    get: { localConfig.settingsSyncIntervalSeconds },
                                    set: { newValue in
                                        localConfig.settingsSyncIntervalSeconds = newValue
                                        saveConfiguration()
                                    }
                                ),
                                in: 15...3600,
                                step: 15
                            )
                            .labelsHidden()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppColors.substrateSecondary)
                        )

                        HStack {
                            Spacer()
                            Text(intervalLabel(seconds: localConfig.settingsSyncIntervalSeconds))
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        DataManagementToggleRow(
                            title: "Show Sync Status",
                            description: "Display sync indicators in the UI",
                            icon: "eye.fill",
                            isOn: Binding(
                                get: { localConfig.showSyncStatus },
                                set: { newValue in
                                    localConfig.showSyncStatus = newValue
                                    saveConfiguration()
                                }
                            )
                        )

                        DataManagementToggleRow(
                            title: "Auto-Sync on Connect",
                            description: "Automatically sync when network available",
                            icon: "wifi",
                            isOn: Binding(
                                get: { localConfig.autoSyncOnConnect },
                                set: { newValue in
                                    localConfig.autoSyncOnConnect = newValue
                                    saveConfiguration()
                                }
                            )
                        )
                    }
                }

                // MARK: - Sync Status
                DataManagementSyncStatus(viewModel: viewModel)

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(AppColors.substratePrimary)
        .navigationTitle("Data Management")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configure how Axon handles your data across devices.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)

            // Current configuration summary
            HStack(spacing: 8) {
                ConfigBadge(
                    icon: localConfig.cloudSyncProvider.icon,
                    text: localConfig.cloudSyncProvider.displayName
                )
                ConfigBadge(
                    icon: localConfig.dataStorage.icon,
                    text: localConfig.dataStorage.displayName
                )
                ConfigBadge(
                    icon: localConfig.aiProcessing.icon,
                    text: localConfig.aiProcessing.displayName + " AI"
                )
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - iCloud Status View

    private var iCloudStatusView: some View {
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

    // MARK: - Helpers

    private func providerAvailable(_ provider: CloudSyncProvider) -> Bool {
        switch provider {
        case .iCloud: return cloudKitService.isCloudKitAvailable
        case .firestore: return BackendConfig.shared.isBackendConfigured
        case .none: return true
        }
    }

    private func saveConfiguration() {
        // Clamp to a safe range
        localConfig.settingsSyncIntervalSeconds = min(3600, max(15, localConfig.settingsSyncIntervalSeconds))

        Task {
            await viewModel.updateSetting(\.deviceModeConfig, localConfig)
        }
    }

    private func intervalLabel(seconds: Int) -> String {
        let s = max(15, seconds)
        if s < 60 {
            return "Every \(s)s"
        }
        if s % 60 == 0 {
            return "Every \(s / 60) min"
        }
        let minutes = s / 60
        let remainder = s % 60
        return "Every \(minutes)m \(remainder)s"
    }
}

// MARK: - Config Badge

private struct ConfigBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(AppTypography.labelSmall())
        }
        .foregroundColor(AppColors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.substrateSecondary)
        )
    }
}

// MARK: - Data Management Section

private struct DataManagementSection<Content: View>: View {
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

// MARK: - Data Management Option Card

private struct DataManagementOptionCard: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    var isAvailable: Bool = true
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
                    HStack(spacing: 8) {
                        Text(title)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if !isAvailable {
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
            .opacity(!isAvailable ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isAvailable)
    }
}

// MARK: - Data Management Toggle Row

private struct DataManagementToggleRow: View {
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

// MARK: - Sync Status

private struct DataManagementSyncStatus: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var cloudKitSync = CloudKitSyncService.shared

    private var isBackendConfigured: Bool {
        APIClient.shared.isBackendConfigured
    }

    private var isUsingiCloudSync: Bool {
        viewModel.settings.deviceModeConfig.cloudSyncProvider == .iCloud
    }

    private var shouldShow: Bool {
        if conversationService.isSyncing || cloudKitSync.isSyncing {
            return true
        }
        if conversationService.pendingOperationsCount > 0 && isBackendConfigured {
            return true
        }
        if isUsingiCloudSync && cloudKitSync.syncError != nil {
            return true
        }
        return false
    }

    var body: some View {
        if shouldShow {
            DataManagementSection(title: "Sync Status", icon: "arrow.triangle.2.circlepath") {
                HStack(spacing: 16) {
                    // Status icon
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.2))
                            .frame(width: 44, height: 44)

                        if conversationService.isSyncing || cloudKitSync.isSyncing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: statusColor))
                        } else {
                            Image(systemName: statusIcon)
                                .font(.system(size: 18))
                                .foregroundColor(statusColor)
                        }
                    }

                    // Status text
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text(statusSubtitle)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    // Sync button
                    if showSyncButton {
                        Button(action: {
                            Task {
                                if isBackendConfigured {
                                    await conversationService.syncPendingOperations()
                                } else if isUsingiCloudSync {
                                    await AutoSyncOrchestrator.shared.pullNow()
                                    await conversationService.syncPendingOperations()
                                }
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

    private var showSyncButton: Bool {
        let isSyncing = conversationService.isSyncing || cloudKitSync.isSyncing
        if isSyncing { return false }

        if conversationService.pendingOperationsCount > 0 && isBackendConfigured {
            return true
        }
        if isUsingiCloudSync && cloudKitSync.syncError != nil {
            return true
        }
        return false
    }

    private var statusColor: Color {
        if conversationService.isSyncing || cloudKitSync.isSyncing {
            return AppColors.signalMercury
        } else if isUsingiCloudSync && cloudKitSync.syncError != nil {
            return AppColors.accentWarning
        } else if conversationService.pendingOperationsCount > 0 && isBackendConfigured {
            return AppColors.accentWarning
        }
        return AppColors.accentSuccess
    }

    private var statusIcon: String {
        if isUsingiCloudSync && cloudKitSync.syncError != nil {
            return "exclamationmark.icloud"
        } else if conversationService.pendingOperationsCount > 0 && isBackendConfigured {
            return "exclamationmark.arrow.triangle.2.circlepath"
        }
        return "checkmark.circle"
    }

    private var statusTitle: String {
        if conversationService.isSyncing || cloudKitSync.isSyncing {
            return "Syncing..."
        } else if isUsingiCloudSync && cloudKitSync.syncError != nil {
            return "iCloud Sync Issue"
        } else if conversationService.pendingOperationsCount > 0 && isBackendConfigured {
            return "Pending Operations"
        }
        return "Synced"
    }

    private var statusSubtitle: String {
        if conversationService.isSyncing {
            return "Uploading changes..."
        } else if cloudKitSync.isSyncing {
            return "Syncing with iCloud..."
        } else if isUsingiCloudSync, let error = cloudKitSync.syncError {
            return error
        } else if conversationService.pendingOperationsCount > 0 && isBackendConfigured {
            return "\(conversationService.pendingOperationsCount) operations waiting to sync"
        }
        return "All changes saved"
    }
}

// MARK: - Sync Disabled Warning Banner

private struct SyncDisabledWarningBanner: View {
    let onEnableSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.accentWarning)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cross-Device Sync Disabled")
                        .font(AppTypography.bodyMedium(.semibold))
                        .foregroundColor(AppColors.textPrimary)

                    Text("Your conversations and settings won't sync to other devices. Enable iCloud sync to keep everything in sync.")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Button(action: onEnableSync) {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 14))

                    Text("Enable iCloud Sync")
                        .font(AppTypography.labelMedium())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.signalMercury)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.accentWarning.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.accentWarning.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DataManagementView(viewModel: SettingsViewModel.shared)
    }
}
