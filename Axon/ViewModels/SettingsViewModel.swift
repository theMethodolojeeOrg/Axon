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
    @Published var availableVoices: [ElevenLabsService.ELVoice] = []
    @Published var availableTTSModels: [ElevenLabsService.ELTTSModel] = []

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
    
    func refreshElevenLabsCatalog() async {
        guard isTTSConfigured else { return }
        do {
            let voices = try await ElevenLabsService.shared.fetchVoices()
            let models = try await ElevenLabsService.shared.fetchTTSModels()
            self.availableVoices = voices
            self.availableTTSModels = models
            // If no voice selected yet, pick the first one
            if settings.ttsSettings.selectedVoiceId == nil, let first = voices.first {
                settings.ttsSettings.selectedVoiceId = first.id
                settings.ttsSettings.selectedVoiceName = first.name
                try? storageService.saveSettings(settings)
            }
        } catch {
            self.error = "Failed to load ElevenLabs catalog: \(error.localizedDescription)"
        }
    }
    
    func updateSelectedVoice(id: String?, name: String?) async {
        settings.ttsSettings.selectedVoiceId = id
        settings.ttsSettings.selectedVoiceName = name
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

    // MARK: - Custom Providers

    func addCustomProvider(_ config: CustomProviderConfig) async {
        settings.customProviders.append(config)
        settings.lastUpdated = Date()

        do {
            try storageService.saveSettings(settings)
            showSuccessMessage("Custom provider '\(config.providerName)' added successfully")
        } catch {
            self.error = "Failed to save custom provider: \(error.localizedDescription)"
        }
    }

    func updateCustomProvider(_ config: CustomProviderConfig) async {
        guard let index = settings.customProviders.firstIndex(where: { $0.id == config.id }) else {
            self.error = "Custom provider not found"
            return
        }

        settings.customProviders[index] = config
        settings.lastUpdated = Date()

        do {
            try storageService.saveSettings(settings)
            showSuccessMessage("Custom provider '\(config.providerName)' updated successfully")
        } catch {
            self.error = "Failed to update custom provider: \(error.localizedDescription)"
        }
    }

    func deleteCustomProvider(id: UUID) async {
        settings.customProviders.removeAll { $0.id == id }
        settings.lastUpdated = Date()

        do {
            try storageService.saveSettings(settings)
            // Also clear the API key for this provider
            try? apiKeysStorage.clearCustomProviderAPIKey(providerId: id)
            showSuccessMessage("Custom provider deleted successfully")
        } catch {
            self.error = "Failed to delete custom provider: \(error.localizedDescription)"
        }
    }

    func getCustomProvider(id: UUID) -> CustomProviderConfig? {
        settings.customProviders.first { $0.id == id }
    }

    // MARK: - Custom Provider API Keys

    func isCustomProviderConfigured(_ providerId: UUID) -> Bool {
        apiKeysStorage.isCustomProviderConfigured(providerId: providerId)
    }

    func getCustomProviderAPIKey(providerId: UUID) -> String? {
        try? apiKeysStorage.getCustomProviderAPIKey(providerId: providerId)
    }

    func saveCustomProviderAPIKey(_ key: String, providerId: UUID, providerName: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try apiKeysStorage.saveCustomProviderAPIKey(key, providerId: providerId)
            showSuccessMessage("\(providerName) API key saved securely")
        } catch {
            self.error = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    func clearCustomProviderAPIKey(providerId: UUID, providerName: String) async {
        do {
            try apiKeysStorage.clearCustomProviderAPIKey(providerId: providerId)
            showSuccessMessage("\(providerName) API key removed")
        } catch {
            self.error = "Failed to clear API key: \(error.localizedDescription)"
        }
    }

    // MARK: - Messages

    func showSuccessMessage(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.successMessage = nil
        }
    }
}

