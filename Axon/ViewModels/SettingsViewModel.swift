//
//  SettingsViewModel.swift
//  Axon
//
//  Settings view model for managing app preferences
//

import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = AppSettings()
    @Published var isLoading = false
    @Published var error: String?
    @Published var successMessage: String?

    private let storageService = SettingsStorage.shared
    private let apiKeysStorage = APIKeysStorage.shared
    private let authService = AuthenticationService.shared

    init() {
        loadSettings()
    }

    // MARK: - Load Settings

    private func loadSettings() {
        // Load from local storage
        if let localSettings = storageService.loadSettings() {
            self.settings = localSettings
        }
    }

    // MARK: - Update Settings

    func updateSetting<T: Encodable & Equatable>(
        _ keyPath: WritableKeyPath<AppSettings, T>,
        _ newValue: T
    ) async {
        guard settings[keyPath: keyPath] != newValue else { return }

        settings[keyPath: keyPath] = newValue
        settings.lastUpdated = Date()

        // Persist to UserDefaults
        do {
            try storageService.saveSettings(settings)
        } catch {
            self.error = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    // MARK: - API Keys

    func isAPIKeyConfigured(_ provider: APIProvider) -> Bool {
        apiKeysStorage.isConfigured(provider)
    }

    func getAPIKey(_ provider: APIProvider) -> String? {
        try? apiKeysStorage.getAPIKey(for: provider)
    }

    func saveAPIKey(_ key: String, for provider: APIProvider) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try apiKeysStorage.saveAPIKey(key, for: provider)
            showSuccessMessage("\(provider.displayName) API key saved securely")
        } catch {
            self.error = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    func clearAPIKey(_ provider: APIProvider) async {
        do {
            try apiKeysStorage.clearAPIKey(for: provider)
            showSuccessMessage("\(provider.displayName) API key removed")
        } catch {
            self.error = "Failed to clear API key: \(error.localizedDescription)"
        }
    }

    // MARK: - TTS Settings

    func updateTTSSetting<T: Encodable & Equatable>(
        _ keyPath: WritableKeyPath<TTSSettings, T>,
        _ value: T
    ) async {
        guard settings.ttsSettings[keyPath: keyPath] != value else { return }

        settings.ttsSettings[keyPath: keyPath] = value
        await updateSetting(\.ttsSettings, settings.ttsSettings)
    }

    func saveTTSAPIKey(_ key: String) async {
        await saveAPIKey(key, for: .elevenlabs)
    }

    func clearTTSAPIKey() async {
        await clearAPIKey(.elevenlabs)
    }

    var isTTSConfigured: Bool {
        isAPIKeyConfigured(.elevenlabs)
    }

    // MARK: - Current Model

    var currentModel: AIModel? {
        settings.defaultProvider.availableModels.first { $0.id == settings.defaultModel }
    }

    // MARK: - Messages

    func showSuccessMessage(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.successMessage = nil
        }
    }
}
