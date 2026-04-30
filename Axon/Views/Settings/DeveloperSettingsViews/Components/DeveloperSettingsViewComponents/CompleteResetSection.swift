//
//  CompleteResetSection.swift
//  Axon
//
//  Nuclear reset option that deletes all data from device and iCloud.
//

import SwiftUI
import CoreData

struct CompleteResetSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingCompleteResetConfirmation = false
    @State private var isPerformingCompleteReset = false
    @State private var completeResetResult: String?

    var body: some View {
        VStack(spacing: 0) {
            // Warning header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.accentError)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nuclear Reset")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.accentError)

                        Text("Permanently delete ALL data from Core Data AND iCloud")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()
                }

                Divider()
                    .background(AppColors.divider)

                // Warning description
                Text("This will permanently delete all conversations, messages, and memories from both your device AND iCloud. This action cannot be undone. Use this for a fresh start or before uninstalling.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()

            Divider()
                .background(AppColors.divider)

            // What will be deleted
            VStack(alignment: .leading, spacing: 8) {
                Text("Will be permanently deleted:")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)

                SettingsFeatureRow(icon: "trash.fill", text: "All conversations & messages", iconColor: AppColors.accentError)
                SettingsFeatureRow(icon: "trash.fill", text: "All memories", iconColor: AppColors.accentError)
                SettingsFeatureRow(icon: "trash.fill", text: "All creative items (images, artifacts)", iconColor: AppColors.accentError)
                SettingsFeatureRow(icon: "trash.fill", text: "All agent state & internal threads", iconColor: AppColors.accentError)
                SettingsFeatureRow(icon: "trash.fill", text: "All covenants & sovereignty history", iconColor: AppColors.accentError)
                SettingsFeatureRow(icon: "trash.fill", text: "All iCloud/CloudKit records", iconColor: AppColors.accentError)

                Divider()
                    .background(AppColors.divider)
                    .padding(.vertical, 4)

                Text("Will be preserved:")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)

                SettingsFeatureRow(icon: "lock.shield.fill", text: "API keys (stored in Keychain)", iconColor: AppColors.signalMercury)
                SettingsFeatureRow(icon: "lock.shield.fill", text: "Account login status", iconColor: AppColors.signalMercury)
            }
            .padding()

            Divider()
                .background(AppColors.divider)

            // Delete button
            Button(action: {
                showingCompleteResetConfirmation = true
            }) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(AppColors.accentError)
                        .frame(width: 32)

                    Text("Delete Everything")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.accentError)

                    Spacer()

                    if isPerformingCompleteReset {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
            }
            .disabled(isPerformingCompleteReset)
        }
        .cornerRadius(8)
        .alert("Delete Everything?", isPresented: $showingCompleteResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Task {
                    await performCompleteReset()
                }
            }
        } message: {
            Text("This will PERMANENTLY delete all conversations, messages, and memories from BOTH your device AND iCloud. This cannot be undone!")
        }
        // Result message
        .onChange(of: completeResetResult) { _, result in
            if let result = result {
                viewModel.showSuccessMessage(result)
            }
        }
    }

    // MARK: - Complete Reset (Nuclear Option)

    private func performCompleteReset() async {
        isPerformingCompleteReset = true
        completeResetResult = nil

        var cloudConversations = 0
        var cloudMessages = 0
        var cloudMemories = 0

        do {
            print("[CompleteResetSection] Starting complete reset (nuclear option)...")

            // 1. Delete all CloudKit data first (while we still have network)
            let cloudKitService = CloudKitSyncService.shared
            if cloudKitService.isCloudKitAvailable {
                print("[CompleteResetSection] Deleting CloudKit data...")
                let cloudResult = try await cloudKitService.deleteAllCloudKitData()
                cloudConversations = cloudResult.conversations
                cloudMessages = cloudResult.messages
                cloudMemories = cloudResult.memories
                print("[CompleteResetSection] CloudKit deletion complete")
            } else {
                print("[CompleteResetSection] CloudKit not available, skipping cloud deletion")
            }

            // 2. Clear all local Core Data
            print("[CompleteResetSection] Clearing local Core Data...")
            try await clearLocalCoreDataComplete()

            // 3. Clear all sync timestamps and caches
            clearSyncTimestamps()

            // 4. Clear additional caches
            clearAdditionalCaches()

            // 5. Reset sovereignty state (covenant, deadlock, comprehension)
            await SovereigntyService.shared.resetAll()

            // 6. Reset settings to defaults (but keep API keys)
            await resetSettingsForDemo()

            // Build result message
            var resultParts: [String] = []
            resultParts.append("Local data cleared")

            if cloudConversations > 0 || cloudMessages > 0 || cloudMemories > 0 {
                resultParts.append("\(cloudConversations) conversations, \(cloudMessages) messages, \(cloudMemories) memories deleted from iCloud")
            } else if cloudKitService.isCloudKitAvailable {
                resultParts.append("No iCloud data to delete")
            } else {
                resultParts.append("iCloud unavailable")
            }

            completeResetResult = resultParts.joined(separator: ". ") + ". Restart app for fresh start."
            print("[CompleteResetSection] Complete reset finished successfully")

        } catch {
            print("[CompleteResetSection] Error during complete reset: \(error)")
            viewModel.error = "Complete reset failed: \(error.localizedDescription)"
        }

        isPerformingCompleteReset = false
    }

    /// Clear all local Core Data entities
    private func clearLocalCoreDataComplete() async throws {
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

            // Delete all generated audio
            let audioFetch: NSFetchRequest<NSFetchRequestResult> = GeneratedAudioEntity.fetchRequest()
            let audioDelete = NSBatchDeleteRequest(fetchRequest: audioFetch)
            try context.execute(audioDelete)

            // Delete all creative items (images, artifacts, etc.)
            let creativeFetch: NSFetchRequest<NSFetchRequestResult> = CreativeItemEntity.fetchRequest()
            let creativeDelete = NSBatchDeleteRequest(fetchRequest: creativeFetch)
            try context.execute(creativeDelete)

            // Delete all internal thread entries (agent state)
            let threadFetch: NSFetchRequest<NSFetchRequestResult> = InternalThreadEntryEntity.fetchRequest()
            let threadDelete = NSBatchDeleteRequest(fetchRequest: threadFetch)
            try context.execute(threadDelete)

            // Delete all device presence records
            let presenceFetch: NSFetchRequest<NSFetchRequestResult> = DevicePresenceEntity.fetchRequest()
            let presenceDelete = NSBatchDeleteRequest(fetchRequest: presenceFetch)
            try context.execute(presenceDelete)

            // Delete all system state snapshots
            let snapshotFetch: NSFetchRequest<NSFetchRequestResult> = SystemStateSnapshotEntity.fetchRequest()
            let snapshotDelete = NSBatchDeleteRequest(fetchRequest: snapshotFetch)
            try context.execute(snapshotDelete)

            // Delete all remote tool approvals
            let approvalFetch: NSFetchRequest<NSFetchRequestResult> = RemoteToolApprovalEntity.fetchRequest()
            let approvalDelete = NSBatchDeleteRequest(fetchRequest: approvalFetch)
            try context.execute(approvalDelete)

            // Delete ElevenLabs voice cache
            let voiceFetch: NSFetchRequest<NSFetchRequestResult> = ElevenLabsVoiceEntity.fetchRequest()
            let voiceDelete = NSBatchDeleteRequest(fetchRequest: voiceFetch)
            try context.execute(voiceDelete)

            let voiceMetaFetch: NSFetchRequest<NSFetchRequestResult> = ElevenLabsVoiceCacheMetaEntity.fetchRequest()
            let voiceMetaDelete = NSBatchDeleteRequest(fetchRequest: voiceMetaFetch)
            try context.execute(voiceMetaDelete)

            try context.save()
        }

        print("[CompleteResetSection] Core Data completely cleared (all entities)")
    }

    /// Clear sync timestamps and standard caches
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

        print("[CompleteResetSection] Sync timestamps and caches cleared")
    }

    /// Clear additional caches beyond the standard sync timestamps
    private func clearAdditionalCaches() {
        // Clear demo mode backup (no longer needed after nuclear reset)
        UserDefaults.standard.removeObject(forKey: "developer.settingsBackup")

        // Clear any conversation caches
        UserDefaults.standard.removeObject(forKey: "last_conversation_summary")
        UserDefaults.standard.removeObject(forKey: "conversation.displayNameOverrides")
        UserDefaults.standard.removeObject(forKey: "conversation.archived")

        // Clear recently deleted tracking
        UserDefaults.standard.removeObject(forKey: "recentlyDeletedConversationIDs")

        // Clear onboarding state
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")

        // Reset demo mode flags
        UserDefaults.standard.removeObject(forKey: "developer.demoModeEnabled")
        UserDefaults.standard.removeObject(forKey: "developer.demoModeBackupExists")

        // Clear sovereignty/covenant data from iCloud KV store
        let kvStore = NSUbiquitousKeyValueStore.default
        kvStore.removeObject(forKey: "sovereignty.covenantStore")
        kvStore.synchronize()

        // Clear draft messages
        UserDefaults.standard.removeObject(forKey: "draftMessages")

        print("[CompleteResetSection] Additional caches cleared (including sovereignty data)")
    }

    /// Reset settings to defaults for demo mode (keeps API keys)
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

        print("[CompleteResetSection] Settings reset (onboarding will show)")
    }
}

#Preview {
    SettingsSection(title: "Complete Reset") {
        CompleteResetSection(viewModel: SettingsViewModel())
    }
    .background(AppSurfaces.color(.contentBackground))
}
