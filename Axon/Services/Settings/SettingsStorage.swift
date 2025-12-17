//
//  SettingsStorage.swift
//  Axon
//
//  Settings persistence using UserDefaults
//

import Foundation
import Combine

class SettingsStorage {
    static let shared = SettingsStorage()

    private let defaults = UserDefaults.standard
    private let settingsKey = "app.settings"
    private let corruptBackupKey = "app.settings.corrupt.backup"

    // Additional keys for conversation management
    private let displayNameOverridesKey = "conversation.displayNameOverrides"
    private let archivedConversationsKey = "conversation.archived"

    // Migration keys
    private let iCloudSyncMigrationKey = "migration.iCloudSyncDefault.v1"

    // Throttle decode error logging (only log once per launch)
    private var hasLoggedDecodeError = false

    // Helper type for archiving entries
    struct ArchivedEntry: Codable, Equatable {
        let id: String
        let archivedAt: Date
    }

    private init() {}

    // MARK: - Save & Load

    func saveSettings(_ settings: AppSettings) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: settingsKey)
    }

    func loadSettings() -> AppSettings? {
        guard let data = defaults.data(forKey: settingsKey) else { return nil }

        // Detect zero-length data (corruption indicator)
        if data.count == 0 {
            print("[SettingsStorage] ⚠️ Detected zero-length settings data. Removing corrupt entry.")
            defaults.removeObject(forKey: settingsKey)
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            var settings = try decoder.decode(AppSettings.self, from: data)

            // Run migrations
            settings = migrateSettingsIfNeeded(settings)

            return settings
        } catch {
            // Only log the first decode error per launch to avoid spam
            if !hasLoggedDecodeError {
                print("[SettingsStorage] ⚠️ Error decoding settings: \(error.localizedDescription)")
                print("[SettingsStorage] Backing up corrupt data and resetting to defaults.")
                hasLoggedDecodeError = true
            }

            // Backup the corrupt data for debugging
            defaults.set(data, forKey: corruptBackupKey)

            // Remove the corrupt settings so next load returns nil (falls back to defaults)
            defaults.removeObject(forKey: settingsKey)

            return nil
        }
    }

    /// Load settings with automatic fallback to defaults
    func loadSettingsOrDefault() -> AppSettings {
        return loadSettings() ?? AppSettings()
    }

    // MARK: - Conversation Display Name Overrides

    func setDisplayName(_ name: String?, for conversationId: String) {
        var map = (try? loadDisplayNameOverrides()) ?? [:]
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            map[conversationId] = name
        } else {
            map.removeValue(forKey: conversationId)
        }
        saveDisplayNameOverrides(map)
    }

    func displayName(for conversationId: String) -> String? {
        let map = (try? loadDisplayNameOverrides()) ?? [:]
        return map[conversationId]
    }

    private func loadDisplayNameOverrides() throws -> [String: String] {
        guard let data = defaults.data(forKey: displayNameOverridesKey) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func saveDisplayNameOverrides(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: displayNameOverridesKey)
        }
    }

    // MARK: - Conversation Archiving

    func archiveConversation(id: String, date: Date = Date()) {
        var entries = loadArchivedEntries()
        // Replace if already present
        entries.removeAll { $0.id == id }
        entries.append(ArchivedEntry(id: id, archivedAt: date))
        saveArchivedEntries(entries)
    }

    func unarchiveConversation(id: String) {
        var entries = loadArchivedEntries()
        entries.removeAll { $0.id == id }
        saveArchivedEntries(entries)
    }

    func isConversationArchived(_ id: String) -> Bool {
        loadArchivedEntries().contains { $0.id == id }
    }

    func archivedConversationIds() -> [String] {
        loadArchivedEntries().map { $0.id }
    }

    func archivedEntries() -> [ArchivedEntry] {
        loadArchivedEntries()
    }

    func purgeExpiredArchived(retentionDays: Int) {
        guard retentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        let entries = loadArchivedEntries().filter { $0.archivedAt > cutoff }
        saveArchivedEntries(entries)
    }

    private func loadArchivedEntries() -> [ArchivedEntry] {
        guard let data = defaults.data(forKey: archivedConversationsKey) else { return [] }
        if let entries = try? JSONDecoder().decode([ArchivedEntry].self, from: data) {
            return entries
        }
        return []
    }

    private func saveArchivedEntries(_ entries: [ArchivedEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: archivedConversationsKey)
        }
    }

    // MARK: - Migrations

    /// Run any necessary migrations on loaded settings
    private func migrateSettingsIfNeeded(_ settings: AppSettings) -> AppSettings {
        var migrated = settings

        // Migration: iCloud sync default change (Dec 2025)
        // Existing users who had cloudSyncProvider = .none but had been using the app
        // should be migrated to .iCloud to restore cross-device sync functionality.
        // This only runs once per device.
        if !defaults.bool(forKey: iCloudSyncMigrationKey) {
            if migrated.deviceModeConfig.cloudSyncProvider == .none {
                // Check if this is an existing user (has completed onboarding or has conversations)
                // If so, they likely had sync working before the default was changed to .none
                if migrated.hasCompletedOnboarding {
                    print("[SettingsStorage] 🔄 Migration: Restoring iCloud sync for existing user")
                    migrated.deviceModeConfig.cloudSyncProvider = .iCloud

                    // Save the migrated settings
                    do {
                        try saveSettings(migrated)
                        print("[SettingsStorage] ✅ Migration: iCloud sync restored and saved")
                    } catch {
                        print("[SettingsStorage] ⚠️ Migration: Failed to save migrated settings: \(error)")
                    }
                }
            }
            defaults.set(true, forKey: iCloudSyncMigrationKey)
        }

        return migrated
    }

    // MARK: - Clear

    func clearSettings() {
        defaults.removeObject(forKey: displayNameOverridesKey)
        defaults.removeObject(forKey: archivedConversationsKey)
        defaults.removeObject(forKey: settingsKey)
        defaults.removeObject(forKey: corruptBackupKey)
    }

    // MARK: - Corruption Recovery

    /// Check if there's a backed-up corrupt settings blob
    func hasCorruptBackup() -> Bool {
        return defaults.data(forKey: corruptBackupKey) != nil
    }

    /// Clear the corrupt backup (useful after successful recovery)
    func clearCorruptBackup() {
        defaults.removeObject(forKey: corruptBackupKey)
    }
}

// MARK: - API Keys Storage (SecureVault - CryptoKit Encrypted)

/// API Keys are now stored using SecureVault which provides:
/// - CryptoKit ChaCha20-Poly1305 encryption
/// - Device-bound keys that never leave the device
/// - Automatic migration from legacy Keychain storage
class APIKeysStorage {
    static let shared = APIKeysStorage()

    private let vault = SecureVault.shared
    private let legacyStorage = SecureTokenStorage.shared
    private let migrationKey = "APIKeysStorage.migrated.v1"

    private init() {
        // Migrate legacy keys on first access
        migrateFromLegacyIfNeeded()
    }

    // MARK: - Save API Key

    func saveAPIKey(_ key: String, for provider: APIProvider) throws {
        try vault.storeAPIKey(key, provider: provider.rawValue)
        print("[APIKeysStorage] Saved API key for \(provider.rawValue) to SecureVault")
    }

    // MARK: - Get API Key

    func getAPIKey(for provider: APIProvider) throws -> String? {
        return try vault.retrieveAPIKey(provider: provider.rawValue)
    }

    // MARK: - Clear API Key

    func clearAPIKey(for provider: APIProvider) throws {
        try vault.deleteAPIKey(provider: provider.rawValue)
        print("[APIKeysStorage] Cleared API key for \(provider.rawValue)")
    }

    // MARK: - Check if Configured

    func isConfigured(_ provider: APIProvider) -> Bool {
        guard let key = try? getAPIKey(for: provider) else { return false }
        return !key.isEmpty
    }

    // MARK: - Custom Provider API Keys

    func saveCustomProviderAPIKey(_ key: String, providerId: UUID) throws {
        try vault.store(key, forKey: customProviderVaultKey(for: providerId))
        print("[APIKeysStorage] Saved custom provider API key to SecureVault")
    }

    func getCustomProviderAPIKey(providerId: UUID) throws -> String? {
        return try vault.retrieveString(forKey: customProviderVaultKey(for: providerId))
    }

    func clearCustomProviderAPIKey(providerId: UUID) throws {
        try vault.delete(forKey: customProviderVaultKey(for: providerId))
        print("[APIKeysStorage] Cleared custom provider API key")
    }

    func isCustomProviderConfigured(providerId: UUID) -> Bool {
        guard let key = try? getCustomProviderAPIKey(providerId: providerId) else { return false }
        return !key.isEmpty
    }

    // MARK: - Migration from Legacy Keychain

    private func migrateFromLegacyIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        print("[APIKeysStorage] Checking for legacy API keys to migrate...")

        var migratedCount = 0

        // Migrate built-in provider keys
        for provider in APIProvider.allCases {
            let legacyKey = "api_key_\(provider.rawValue)"
            if let legacyValue = try? legacyStorage.retrieve(forKey: legacyKey), !legacyValue.isEmpty {
                do {
                    try vault.storeAPIKey(legacyValue, provider: provider.rawValue)
                    // Clear from legacy storage after successful migration
                    try? legacyStorage.delete(forKey: legacyKey)
                    migratedCount += 1
                    print("[APIKeysStorage] Migrated \(provider.rawValue) API key to SecureVault")
                } catch {
                    print("[APIKeysStorage] Failed to migrate \(provider.rawValue): \(error)")
                }
            }
        }

        // Mark migration as complete
        defaults.set(true, forKey: migrationKey)

        if migratedCount > 0 {
            print("[APIKeysStorage] Migration complete. Migrated \(migratedCount) API keys to SecureVault")
        } else {
            print("[APIKeysStorage] No legacy API keys found to migrate")
        }
    }

    // MARK: - Private Helpers

    private func customProviderVaultKey(for providerId: UUID) -> String {
        return "custom_provider_api_key_\(providerId.uuidString)"
    }

    // MARK: - Debug / Export (for backup purposes)

    /// List all stored API key providers (not the keys themselves)
    func listStoredProviders() -> [String] {
        do {
            let allKeys = try vault.listKeys()
            return allKeys.filter { $0.hasPrefix("apikey.") }
                .map { String($0.dropFirst("apikey.".count)) }
        } catch {
            return []
        }
    }
}
