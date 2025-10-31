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

    // Additional keys for conversation management
    private let displayNameOverridesKey = "conversation.displayNameOverrides"
    private let archivedConversationsKey = "conversation.archived"

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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            print("[SettingsStorage] Error decoding settings: \(error.localizedDescription)")
            return nil
        }
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

    // MARK: - Clear

    func clearSettings() {
        defaults.removeObject(forKey: displayNameOverridesKey)
        defaults.removeObject(forKey: archivedConversationsKey)
        defaults.removeObject(forKey: settingsKey)
    }
}

// MARK: - API Keys Storage (Keychain)

class APIKeysStorage {
    static let shared = APIKeysStorage()

    private init() {}

    // MARK: - Save API Key

    func saveAPIKey(_ key: String, for provider: APIProvider) throws {
        try SecureTokenStorage.shared.save(key, forKey: keychainKey(for: provider))
    }

    // MARK: - Get API Key

    func getAPIKey(for provider: APIProvider) throws -> String? {
        try SecureTokenStorage.shared.retrieve(forKey: keychainKey(for: provider))
    }

    // MARK: - Clear API Key

    func clearAPIKey(for provider: APIProvider) throws {
        try SecureTokenStorage.shared.delete(forKey: keychainKey(for: provider))
    }

    // MARK: - Check if Configured

    func isConfigured(_ provider: APIProvider) -> Bool {
        guard let key = try? getAPIKey(for: provider) else { return false }
        return !key.isEmpty
    }

    // MARK: - Custom Provider API Keys

    func saveCustomProviderAPIKey(_ key: String, providerId: UUID) throws {
        try SecureTokenStorage.shared.save(key, forKey: customProviderKeychainKey(for: providerId))
    }

    func getCustomProviderAPIKey(providerId: UUID) throws -> String? {
        try SecureTokenStorage.shared.retrieve(forKey: customProviderKeychainKey(for: providerId))
    }

    func clearCustomProviderAPIKey(providerId: UUID) throws {
        try SecureTokenStorage.shared.delete(forKey: customProviderKeychainKey(for: providerId))
    }

    func isCustomProviderConfigured(providerId: UUID) -> Bool {
        guard let key = try? getCustomProviderAPIKey(providerId: providerId) else { return false }
        return !key.isEmpty
    }

    // MARK: - Private Helpers

    private func keychainKey(for provider: APIProvider) -> String {
        return "api_key_\(provider.rawValue)"
    }

    private func customProviderKeychainKey(for providerId: UUID) -> String {
        return "custom_provider_api_key_\(providerId.uuidString)"
    }
}

