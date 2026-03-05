//
//  SettingsViewModel.swift
//  Axon
//
//  Composed settings view model managing all settings sub-modules
//

import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    static let shared = SettingsViewModel()

    // MARK: - Core State (Published for backward compatibility)
    
    @Published var settings: AppSettings = AppSettings()
    @Published var isLoading = false
    @Published var error: String?
    @Published var successMessage: String?
    
    // MARK: - Composed Modules
    
    private(set) lazy var iCloudSyncVM: iCloudSyncSettingsViewModel = {
        iCloudSyncSettingsViewModel(core: self)
    }()
    
    private(set) lazy var apiKeysVM: APIKeysSettingsViewModel = {
        APIKeysSettingsViewModel(core: self)
    }()
    
    private(set) lazy var ttsVM: TTSSettingsViewModel = {
        TTSSettingsViewModel(core: self)
    }()
    
    private(set) lazy var customProvidersVM: CustomProvidersViewModel = {
        CustomProvidersViewModel(core: self)
    }()
    
    private(set) lazy var localServerVM: LocalServerSettingsViewModel = {
        LocalServerSettingsViewModel(core: self)
    }()
    
    private(set) lazy var mlxModelsVM: MLXModelsSettingsViewModel = {
        MLXModelsSettingsViewModel(core: self)
    }()
    
    private(set) lazy var backendVM: BackendSettingsViewModel = {
        BackendSettingsViewModel(core: self)
    }()
    
    // MARK: - Dependencies
    
    let storageService = SettingsStorage.shared
    let apiKeysStorage = APIKeysStorage.shared
    private let iCloudSync = iCloudKeyValueSync.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Exposed Module State
    
    var availableVoices: [ElevenLabsService.ELVoice] {
        ttsVM.availableVoices
    }
    
    var availableTTSModels: [ElevenLabsService.ELTTSModel] {
        ttsVM.availableTTSModels
    }
    
    var isServerRunning: Bool {
        localServerVM.isServerRunning
    }
    
    var serverError: String? {
        localServerVM.serverError
    }
    
    var serverLocalURL: String {
        localServerVM.serverLocalURL
    }
    
    var serverNetworkURL: String {
        localServerVM.serverNetworkURL
    }
    
    var iCloudSyncEnabled: Bool {
        iCloudSyncVM.iCloudSyncEnabled
    }
    
    // MARK: - Initialization
    
    init() {
        loadSettings()
        setupiCloudSync()
        SettingsSyncCoordinator.shared.start()
        
        // Hydrate ElevenLabs voices from Core Data cache ASAP so the user doesn't
        // need to tap "Refresh Voices" every launch.
        Task { await ttsVM.hydrateElevenLabsVoicesFromCache() }
    }
    
    // MARK: - Load Settings
    
    func loadSettings() {
        // Load from local storage
        if let localSettings = storageService.loadSettings() {
            self.settings = localSettings
        }
        
        // One-time defaulting: if user hasn't explicitly chosen a consent provider,
        // default it to the current main provider from General Settings.
        if !settings.sovereigntySettings.consentProviderHasBeenSetByUser {
            settings.sovereigntySettings.consentProvider = settings.defaultProvider
            settings.sovereigntySettings.consentModel = "" // reset to provider default
            
            // Persist this migration immediately so it is stable across launches.
            do {
                try storageService.saveSettings(settings)
            } catch {
                print("[SettingsViewModel] Failed to persist default consent provider: \(error.localizedDescription)")
            }
        }
        
        // If iCloud is the selected sync provider, attempt to import any roaming API keys
        // from iCloud Keychain into local SecureVault (one-way import).
        apiKeysVM.importAPIKeysFromiCloudKeychainIfNeeded()
    }
    
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
    }
    
    // MARK: - Current Model
    
    var currentModel: AIModel? {
        settings.defaultProvider.availableModels.first { $0.id == settings.defaultModel }
    }
}

// MARK: - SettingsViewModelCoreProtocol Conformance

extension SettingsViewModel: SettingsViewModelCoreProtocol {
    
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
            
            // Unified sync (debounced + scheduled) based on DeviceModeConfig
            SettingsSyncCoordinator.shared.markDirty()
        } catch {
            self.error = "Failed to save settings: \(error.localizedDescription)"
        }
    }
    
    func syncToiCloudIfEnabled() {
        // Only sync if user has iCloud sync enabled in device mode config
        guard settings.deviceModeConfig.cloudSyncProvider == .iCloud ||
              settings.deviceMode == .cloud else {
            return
        }
        
        iCloudSync.saveSettingsToCloud(settings)
    }
    
    func showSuccessMessage(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.successMessage = nil
        }
    }
}

// MARK: - Backward Compatibility API

extension SettingsViewModel {
    
    // MARK: - iCloud Sync
    
    func forceiCloudSync() {
        iCloudSyncVM.forceiCloudSync()
    }
    
    // MARK: - API Keys
    
    func isAPIKeyConfigured(_ provider: APIProvider) -> Bool {
        apiKeysVM.isAPIKeyConfigured(provider)
    }
    
    func getAPIKey(_ provider: APIProvider) -> String? {
        apiKeysVM.getAPIKey(provider)
    }
    
    func saveAPIKey(_ key: String, for provider: APIProvider) async {
        await apiKeysVM.saveAPIKey(key, for: provider)
        
        // For ElevenLabs, refresh catalog after saving
        if provider == .elevenlabs {
            await ttsVM.refreshElevenLabsCatalog()
        }
    }
    
    func clearAPIKey(_ provider: APIProvider) async {
        await apiKeysVM.clearAPIKey(provider)
    }
    
    // MARK: - TTS Settings
    
    func updateTTSSetting<T: Encodable & Equatable>(
        _ keyPath: WritableKeyPath<TTSSettings, T>,
        _ value: T
    ) async {
        await ttsVM.updateTTSSetting(keyPath, value)
    }
    
    func refreshElevenLabsCatalog() async {
        await ttsVM.refreshElevenLabsCatalog()
    }
    
    func updateSelectedVoice(id: String?, name: String?) async {
        await ttsVM.updateSelectedVoice(id: id, name: name)
    }
    
    func saveTTSAPIKey(_ key: String) async {
        await ttsVM.saveTTSAPIKey(key, using: apiKeysVM)
    }
    
    func clearTTSAPIKey() async {
        await ttsVM.clearTTSAPIKey(using: apiKeysVM)
    }
    
    var isTTSConfigured: Bool {
        ttsVM.isTTSConfigured
    }
    
    var isGeminiTTSConfigured: Bool {
        ttsVM.isGeminiTTSConfigured
    }
    
    var isOpenAITTSConfigured: Bool {
        ttsVM.isOpenAITTSConfigured
    }
    
    var isKokoroTTSConfigured: Bool {
        ttsVM.isKokoroTTSConfigured
    }
    
    // MARK: - Custom Providers
    
    func addCustomProvider(_ config: CustomProviderConfig) async {
        await customProvidersVM.addCustomProvider(config)
    }
    
    func updateCustomProvider(_ config: CustomProviderConfig) async {
        await customProvidersVM.updateCustomProvider(config)
    }
    
    func deleteCustomProvider(id: UUID) async {
        await customProvidersVM.deleteCustomProvider(id: id)
    }
    
    func getCustomProvider(id: UUID) -> CustomProviderConfig? {
        customProvidersVM.getCustomProvider(id: id)
    }
    
    func isCustomProviderConfigured(_ providerId: UUID) -> Bool {
        customProvidersVM.isCustomProviderConfigured(providerId)
    }
    
    func getCustomProviderAPIKey(providerId: UUID) -> String? {
        customProvidersVM.getCustomProviderAPIKey(providerId: providerId)
    }
    
    func saveCustomProviderAPIKey(_ key: String, providerId: UUID, providerName: String) async {
        await customProvidersVM.saveCustomProviderAPIKey(key, providerId: providerId, providerName: providerName)
    }
    
    func clearCustomProviderAPIKey(providerId: UUID, providerName: String) async {
        await customProvidersVM.clearCustomProviderAPIKey(providerId: providerId, providerName: providerName)
    }
    
    // MARK: - Local API Server
    
    func startServer() async {
        await localServerVM.startServer()
    }
    
    func stopServer() async {
        await localServerVM.stopServer()
    }
    
    func updateServerPort(_ port: Int) async {
        await localServerVM.updateServerPort(port)
    }
    
    func updateServerPassword(_ password: String?) async {
        await localServerVM.updateServerPassword(password)
    }
    
    func updateServerAllowExternal(_ allow: Bool) async {
        await localServerVM.updateServerAllowExternal(allow)
    }
    
    func generateServerPassword() async {
        await localServerVM.generateServerPassword()
    }
    
    // MARK: - Backend Settings
    
    func updateBackendURL(_ url: String?) async {
        await backendVM.updateBackendURL(url)
    }
    
    func updateBackendAuthToken(_ token: String?) async {
        await backendVM.updateBackendAuthToken(token)
    }
    
    // MARK: - User MLX Models
    
    func addUserMLXModel(_ model: UserMLXModel) async {
        await mlxModelsVM.addUserMLXModel(model)
    }
    
    func removeUserMLXModel(repoId: String) async {
        await mlxModelsVM.removeUserMLXModel(repoId: repoId)
    }
    
    func updateUserMLXModelStatus(repoId: String, status: UserMLXModel.DownloadStatus, sizeBytes: Int64? = nil) async {
        await mlxModelsVM.updateUserMLXModelStatus(repoId: repoId, status: status, sizeBytes: sizeBytes)
    }
    
    func selectMLXModel(repoId: String) async {
        await mlxModelsVM.selectMLXModel(repoId: repoId)
    }
    
    func allMLXModels() -> [AIModel] {
        mlxModelsVM.allMLXModels()
    }
    
    func selectedMLXModelId() -> String {
        mlxModelsVM.selectedMLXModelId()
    }
}
