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
    @StateObject private var cloudKitService = CloudKitSyncService.shared

    @State private var localConfig: DeviceModeConfig
    @State private var showSyncDisabledWarning: Bool = false

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

                    // Sync Disabled Warning Banner
                    if localConfig.cloudSyncProvider == .none && cloudKitService.isCloudKitAvailable {
                        SyncDisabledWarningBanner {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                localConfig.cloudSyncProvider = .iCloud
                            }
                        }
                    }

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
                                    value: $localConfig.settingsSyncIntervalSeconds,
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
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        // Clamp to a safe range even if UI constraints change
        localConfig.settingsSyncIntervalSeconds = min(3600, max(15, localConfig.settingsSyncIntervalSeconds))

        Task {
            await viewModel.updateSetting(\.deviceModeConfig, localConfig)
            dismiss()
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
    @StateObject private var backendConfig = BackendConfig.shared

    private var isFirestoreAvailable: Bool {
        backendConfig.isBackendConfigured
    }

    var body: some View {
        ConfigSection(title: "Cross-Device Sync", icon: "icloud.fill") {
            VStack(spacing: 12) {
                ForEach(CloudSyncProvider.allCases) { provider in
                    let available = switch provider {
                    case .iCloud: cloudKitService.isCloudKitAvailable
                    case .firestore: isFirestoreAvailable
                    case .none: true
                    }

                    CloudSyncProviderCard(
                        provider: provider,
                        isSelected: localConfig.cloudSyncProvider == provider,
                        isAvailable: available
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
            .opacity(!isAvailable ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isAvailable)
    }
}

// MARK: - Sync Status Card

private struct SyncStatusCard: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var cloudKitSync = CloudKitSyncService.shared
    
    // Check if backend is configured
    private var isBackendConfigured: Bool {
        APIClient.shared.isBackendConfigured
    }
    
    // Check if using iCloud sync
    private var isUsingiCloudSync: Bool {
        viewModel.settings.deviceModeConfig.cloudSyncProvider == .iCloud
    }
    
    // Only show if there's something relevant to display
    private var shouldShow: Bool {
        // Show if syncing
        if conversationService.isSyncing || cloudKitSync.isSyncing {
            return true
        }
        // Show if there are pending operations AND a backend is configured
        if conversationService.pendingOperationsCount > 0 && isBackendConfigured {
            return true
        }
        // Show CloudKit errors if using iCloud
        if isUsingiCloudSync && cloudKitSync.syncError != nil {
            return true
        }
        return false
    }

    var body: some View {
        if shouldShow {
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

                    // Sync button - context-aware
                    if showSyncButton {
                        Button(action: {
                            Task {
                                if isBackendConfigured {
                                    // Backend mode: sync pending operations to API
                                    await conversationService.syncPendingOperations()
                                } else if isUsingiCloudSync {
                                    // iCloud-only mode: trigger CloudKit sync
                                    await AutoSyncOrchestrator.shared.pullNow()
                                    // Clear any stale pending operations
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
        
        // Show sync button if there are pending operations with backend
        if conversationService.pendingOperationsCount > 0 && isBackendConfigured {
            return true
        }
        // Show sync button for iCloud errors
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
    DeviceModeConfigSheet(viewModel: SettingsViewModel.shared)
}
