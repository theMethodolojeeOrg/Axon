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

    // MARK: - Clear

    func clearSettings() {
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

    // MARK: - Private Helpers

    private func keychainKey(for provider: APIProvider) -> String {
        return "api_key_\(provider.rawValue)"
    }
}
