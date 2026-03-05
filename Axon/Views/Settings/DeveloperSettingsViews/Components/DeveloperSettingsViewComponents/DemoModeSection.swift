//
//  DemoModeSection.swift
//  Axon
//
//  Demo mode for creating screenshots with generic content.
//

import SwiftUI
import CoreData

struct DemoModeSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var resetComplete: Bool

    @State private var showingResetConfirmation = false
    @State private var showingExitDemoConfirmation = false
    @State private var isResetting = false

    // Demo mode state
    @AppStorage("developer.demoModeEnabled") private var demoModeEnabled = false
    @AppStorage("developer.demoModeBackupExists") private var demoModeBackupExists = false

    var body: some View {
        VStack(spacing: 0) {
            // Demo Mode Toggle Info
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: demoModeEnabled ? "camera.fill" : "camera")
                        .foregroundColor(demoModeEnabled ? AppColors.accentSuccess : AppColors.textSecondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Demo Mode")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text(demoModeEnabled ? "Active - App reset for screenshots" : "Reset app for fresh screenshots")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(demoModeEnabled ? AppColors.accentSuccess : AppColors.textTertiary)
                    }

                    Spacer()

                    if demoModeEnabled {
                        Text("ON")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.accentSuccess)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.accentSuccess.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Divider()
                    .background(AppColors.divider)

                // Description
                Text(demoModeEnabled ?
                     "Your real data is safely backed up. Create generic content for screenshots, then exit demo mode to restore everything." :
                     "Temporarily reset the app to a fresh state. Perfect for creating screenshots with generic content. Your real data will be backed up and can be restored.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()

            Divider()
                .background(AppColors.divider)

            // Action Buttons
            if demoModeEnabled {
                // Exit Demo Mode Button
                Button(action: {
                    showingExitDemoConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        Text("Exit Demo Mode & Restore Data")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.signalMercury)

                        Spacer()

                        if isResetting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding()
                }
                .disabled(isResetting)

                Divider()
                    .background(AppColors.divider)

                // Re-reset Button (for multiple screenshot sessions)
                Button(action: {
                    showingResetConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .foregroundColor(AppColors.textSecondary)
                            .frame(width: 32)

                        Text("Reset Again (Fresh Start)")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textSecondary)

                        Spacer()
                    }
                    .padding()
                }
                .disabled(isResetting)
            } else {
                // Enter Demo Mode Button
                Button(action: {
                    showingResetConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        Text("Enter Demo Mode")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.signalMercury)

                        Spacer()

                        if isResetting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding()
                }
                .disabled(isResetting)
            }
        }
        .cornerRadius(8)
        .alert("Enter Demo Mode?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Enter Demo Mode", role: .destructive) {
                Task {
                    await enterDemoMode()
                }
            }
        } message: {
            Text("This will backup your data and reset the app for screenshots. You can restore everything when done.")
        }
        .alert("Exit Demo Mode?", isPresented: $showingExitDemoConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore My Data") {
                Task {
                    await exitDemoMode()
                }
            }
        } message: {
            Text("This will restore all your original data and exit demo mode.")
        }
        .onChange(of: resetComplete) { _, newValue in
            if newValue {
                viewModel.showSuccessMessage(demoModeEnabled ? "Demo mode active! Restart app to see onboarding." : "Data restored! Restart app to continue.")
            }
        }
    }

    // MARK: - Demo Mode Actions

    private func enterDemoMode() async {
        isResetting = true
        resetComplete = false

        do {
            // 1. Backup current settings if not already in demo mode
            if !demoModeEnabled {
                try backupCurrentData()
            }

            // 2. Clear local Core Data (conversations, messages, memories)
            try await clearLocalCoreData()

            // 3. Reset settings to defaults (but keep API keys)
            await resetSettingsForDemo()

            // 4. Clear UserDefaults sync timestamps
            clearSyncTimestamps()

            // 5. Mark demo mode as active
            demoModeEnabled = true
            demoModeBackupExists = true

            resetComplete = true
            print("[DemoModeSection] Demo mode activated successfully")
        } catch {
            print("[DemoModeSection] Error entering demo mode: \(error)")
            viewModel.error = "Failed to enter demo mode: \(error.localizedDescription)"
        }

        isResetting = false
    }

    private func exitDemoMode() async {
        isResetting = true
        resetComplete = false

        do {
            // 1. Restore backed up settings
            try restoreBackedUpData()

            // 2. Clear demo data from Core Data
            try await clearLocalCoreData()

            // 3. Clear sync timestamps to force re-sync
            clearSyncTimestamps()

            // 4. Mark demo mode as inactive
            demoModeEnabled = false

            resetComplete = true
            print("[DemoModeSection] Demo mode exited, data restored")
        } catch {
            print("[DemoModeSection] Error exiting demo mode: \(error)")
            viewModel.error = "Failed to exit demo mode: \(error.localizedDescription)"
        }

        isResetting = false
    }

    // MARK: - Backup & Restore

    private func backupCurrentData() throws {
        // Backup settings
        if let settings = SettingsStorage.shared.loadSettings() {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(settings)
            UserDefaults.standard.set(data, forKey: "developer.settingsBackup")
            print("[DemoModeSection] Settings backed up")
        }
    }

    private func restoreBackedUpData() throws {
        // Restore settings
        if let data = UserDefaults.standard.data(forKey: "developer.settingsBackup") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let settings = try decoder.decode(AppSettings.self, from: data)
            try SettingsStorage.shared.saveSettings(settings)

            // Refresh the view model
            Task { @MainActor in
                viewModel.loadSettings()
            }
            print("[DemoModeSection] Settings restored from backup")
        }
    }

    // MARK: - Data Clearing

    private func clearLocalCoreData() async throws {
        let persistence = PersistenceController.shared
        let context = persistence.newBackgroundContext()

        try await context.perform {
            // Delete all conversations
            let conversationFetch: NSFetchRequest<NSFetchRequestResult> = ConversationEntity.fetchRequest()
            let conversationDelete = NSBatchDeleteRequest(fetchRequest: conversationFetch)
            try context.execute(conversationDelete)

            // Delete all messages
            let messageFetch: NSFetchRequest<NSFetchRequestResult> = MessageEntity.fetchRequest()
            let messageDelete = NSBatchDeleteRequest(fetchRequest: messageFetch)
            try context.execute(messageDelete)

            // Delete all memories
            let memoryFetch: NSFetchRequest<NSFetchRequestResult> = MemoryEntity.fetchRequest()
            let memoryDelete = NSBatchDeleteRequest(fetchRequest: memoryFetch)
            try context.execute(memoryDelete)

            try context.save()
        }

        print("[DemoModeSection] Core Data cleared (conversations, messages, memories)")
    }

    private func resetSettingsForDemo() async {
        // Create fresh settings but preserve certain values
        var freshSettings = AppSettings()

        // Keep these from current settings (preserve user's preferences for API routing)
        if let current = SettingsStorage.shared.loadSettings() {
            freshSettings.defaultProvider = current.defaultProvider
            freshSettings.defaultModel = current.defaultModel
            freshSettings.deviceMode = current.deviceMode
            freshSettings.deviceModeConfig = current.deviceModeConfig
            // API keys are stored separately in SecureVault, not in settings
        }

        // Reset onboarding flag
        freshSettings.hasCompletedOnboarding = false

        // Save fresh settings
        try? SettingsStorage.shared.saveSettings(freshSettings)

        // Refresh view model
        viewModel.loadSettings()

        print("[DemoModeSection] Settings reset for demo (onboarding will show)")
    }

    private func clearSyncTimestamps() {
        // Clear conversation sync timestamp
        UserDefaults.standard.removeObject(forKey: "lastConversationSyncTimestamp")

        // Clear memory sync timestamp
        UserDefaults.standard.removeObject(forKey: "lastMemorySyncTimestamp")

        // Clear pending operations
        UserDefaults.standard.removeObject(forKey: "LocalConversationStore.pendingOperations")

        // Clear conversation summary cache
        UserDefaults.standard.removeObject(forKey: "last_conversation_summary")

        // Clear display name overrides and archived entries
        UserDefaults.standard.removeObject(forKey: "conversation.displayNameOverrides")
        UserDefaults.standard.removeObject(forKey: "conversation.archived")

        print("[DemoModeSection] Sync timestamps and caches cleared")
    }
}

#Preview {
    SettingsSection(title: "Screenshot Mode") {
        DemoModeSection(viewModel: SettingsViewModel(), resetComplete: .constant(false))
    }
    .background(AppColors.substratePrimary)
}
