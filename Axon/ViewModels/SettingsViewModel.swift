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
    static let shared = SettingsViewModel()

    @Published var settings: AppSettings = AppSettings()
    @Published var isLoading = false
    @Published var error: String?
    @Published var successMessage: String?
    @Published var availableVoices: [ElevenLabsService.ELVoice] = []
    @Published var availableTTSModels: [ElevenLabsService.ELTTSModel] = []

    // Server status
    @Published var isServerRunning = false
    @Published var serverError: String?
    @Published var serverLocalURL: String = ""
    @Published var serverNetworkURL: String = ""

    // iCloud Sync status
    @Published var iCloudSyncEnabled = false

    private let storageService = SettingsStorage.shared
    private let apiKeysStorage = APIKeysStorage.shared
    private let apiServer = APIServer.shared
    private let iCloudSync = iCloudKeyValueSync.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Cloud Sync (Manual)
    func pushSettingsToCloud() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await SettingsCloudSyncService.shared.pushSettings(settings)
            showSuccessMessage("Settings pushed to cloud")
        } catch {
            self.error = "Failed to push settings: \(error.localizedDescription)"
        }
    }

    func pullSettingsFromCloud() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let cloudSettings = try await SettingsCloudSyncService.shared.pullSettings()
            // Overwrite local settings with cloud copy
            self.settings = cloudSettings
            self.settings.lastUpdated = Date()
            try storageService.saveSettings(self.settings)
            showSuccessMessage("Settings pulled from cloud")
        } catch {
            self.error = "Failed to pull settings: \(error.localizedDescription)"
        }
    }

    init() {
        loadSettings()
        setupiCloudSync()
    }

    // MARK: - Load Settings

    func loadSettings() {
        // Load from local storage
        if let localSettings = storageService.loadSettings() {
            self.settings = localSettings
            // Populate available voices from cache
            self.availableVoices = localSettings.ttsSettings.cachedVoices
        }

        // Check iCloud sync availability
        iCloudSyncEnabled = iCloudSync.isAvailable
    }

    // MARK: - iCloud Key-Value Sync

    private func setupiCloudSync() {
        // Listen for settings changes from other devices
        iCloudSync.settingsChangedFromCloud
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cloudSettings in
                guard let self = self else { return }

                // Update local settings with cloud values
                self.settings = cloudSettings
                try? self.storageService.saveSettings(cloudSettings)

                // Show notification to user
                self.showSuccessMessage("Settings synced from another device")
            }
            .store(in: &cancellables)

        // Track availability changes
        iCloudSync.$isAvailable
            .receive(on: DispatchQueue.main)
            .assign(to: &$iCloudSyncEnabled)
    }

    /// Sync current settings to iCloud (called after updates)
    private func syncToiCloudIfEnabled() {
        // Only sync if user has iCloud sync enabled in device mode config
        guard settings.deviceModeConfig.cloudSyncProvider == .iCloud ||
              settings.deviceMode == .cloud else {
            return
        }

        iCloudSync.saveSettingsToCloud(settings)
    }

    /// Force sync settings to/from iCloud
    func forceiCloudSync() {
        iCloudSync.forceSync()
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

            // Sync to iCloud if enabled
            syncToiCloudIfEnabled()
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
            // 1. Save to local Keychain (always)
            try apiKeysStorage.saveAPIKey(key, for: provider)

            // 2. If ElevenLabs, also sync to Firestore (encrypted)
            if provider == .elevenlabs {
                do {
                    try await EncryptionService.shared.encryptAndSyncElevenLabsKey(key)
                    // After successful sync, refresh the catalog to verify it works
                    await refreshElevenLabsCatalog()
                } catch {
                    // Log the sync error but don't fail the entire save operation
                    print("[SettingsViewModel] Warning: Key saved locally but sync to Firestore failed: \(error.localizedDescription)")
                    self.error = "API key saved locally, but cloud sync failed. You may need to re-save it. Error: \(error.localizedDescription)"
                    return
                }
            }

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
        var updated = settings.ttsSettings
        guard updated[keyPath: keyPath] != value else { return }

        updated[keyPath: keyPath] = value
        await updateSetting(\.ttsSettings, updated)
    }
    
    func refreshElevenLabsCatalog() async {
        guard isTTSConfigured else { return }

        // Helper to perform the fetch
        func performFetch() async throws {
            let voices = try await ElevenLabsService.shared.fetchVoices()
            let models = try await ElevenLabsService.shared.fetchTTSModels()
            self.availableVoices = voices
            self.availableTTSModels = models
            
            // Cache the voices
            settings.ttsSettings.cachedVoices = voices
            try? storageService.saveSettings(settings)

            // If no voice selected yet, pick the first one
            if settings.ttsSettings.selectedVoiceId == nil, let first = voices.first {
                print("[SettingsViewModel] No voice selected, defaulting to first voice: \(first.name) (ID: \(first.id))")
                settings.ttsSettings.selectedVoiceId = first.id
                settings.ttsSettings.selectedVoiceName = first.name
                try? storageService.saveSettings(settings)
            } else {
                print("[SettingsViewModel] Voice already selected: \(settings.ttsSettings.selectedVoiceName ?? "nil") (ID: \(settings.ttsSettings.selectedVoiceId ?? "nil"))")
            }
        }

        do {
            try await performFetch()
        } catch {
            // Check if error is "ElevenLabs API key not configured" (401)
            let errorMsg = error.localizedDescription
            let errorCode = (error as NSError).code

            if errorCode == 401 && errorMsg.contains("ElevenLabs API key not configured") {
                // Attempt to re-sync key if we have it locally - but only once per session
                if let key = try? apiKeysStorage.getAPIKey(for: .elevenlabs), !key.isEmpty {
                    do {
                        try await EncryptionService.shared.encryptAndSyncElevenLabsKey(key)
                        // Retry fetch once
                        try await performFetch()
                        return
                    } catch let resyncError {
                        // Silent failure - key sync didn't work, likely server-side issue
                        // Don't spam logs or show error to user as this may be transient
                        print("[SettingsViewModel] Failed to re-sync ElevenLabs key (will retry on next catalog refresh): \(resyncError.localizedDescription)")
                        return // Don't show error to user for auto-retry failures
                    }
                } else {
                    // No local key available, user needs to configure it
                    self.error = "ElevenLabs API key not configured. Please set it in settings."
                    return
                }
            }

            // For other errors, show the actual error
            self.error = "Failed to load ElevenLabs catalog: \(error.localizedDescription)"
        }
    }
    
    func updateSelectedVoice(id: String?, name: String?) async {
        print("[SettingsViewModel] Updating selected voice to: \(name ?? "nil") (ID: \(id ?? "nil"))")
        var updated = settings.ttsSettings
        updated.selectedVoiceId = id
        updated.selectedVoiceName = name
        await updateSetting(\.ttsSettings, updated)
        print("[SettingsViewModel] Voice selection saved. Current settings - Voice ID: \(settings.ttsSettings.selectedVoiceId ?? "nil"), Voice Name: \(settings.ttsSettings.selectedVoiceName ?? "nil")")
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

    // MARK: - Local API Server

    func startServer() async {
        await apiServer.start(
            port: UInt16(settings.serverPort),
            password: settings.serverPassword,
            allowExternal: settings.serverAllowExternal
        )

        // Sync server state
        isServerRunning = apiServer.isRunning
        serverError = apiServer.error
        serverLocalURL = apiServer.localURL
        serverNetworkURL = apiServer.networkURL

        if isServerRunning {
            showSuccessMessage("Server started successfully")
        }
    }

    func stopServer() async {
        await apiServer.stop()

        // Sync server state
        isServerRunning = apiServer.isRunning
        serverError = apiServer.error
        serverLocalURL = apiServer.localURL
        serverNetworkURL = apiServer.networkURL

        showSuccessMessage("Server stopped")
    }

    func updateServerPort(_ port: Int) async {
        await updateSetting(\.serverPort, port)

        // Restart server if running
        if isServerRunning {
            await stopServer()
            await startServer()
        }
    }

    func updateServerPassword(_ password: String?) async {
        await updateSetting(\.serverPassword, password)

        // Restart server if running
        if isServerRunning {
            await stopServer()
            await startServer()
        }
    }

    func updateServerAllowExternal(_ allow: Bool) async {
        await updateSetting(\.serverAllowExternal, allow)

        // Restart server if running
        if isServerRunning {
            await stopServer()
            await startServer()
        }
    }

    func generateServerPassword() async {
        let password = generateRandomPassword()
        await updateServerPassword(password)
        showSuccessMessage("Password generated: \(password)")
    }

    private func generateRandomPassword(length: Int = 24) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }

    // MARK: - Backend Settings

    func updateBackendURL(_ url: String?) async {
        await updateSetting(\.backendAPIURL, url)
        if url != nil {
            showSuccessMessage("Backend URL saved")
        } else {
            showSuccessMessage("Backend URL cleared - running in local-only mode")
        }
    }

    func updateBackendAuthToken(_ token: String?) async {
        await updateSetting(\.backendAuthToken, token)
        showSuccessMessage("Auth token updated")
    }

    // MARK: - Messages

    func showSuccessMessage(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.successMessage = nil
        }
    }
}
