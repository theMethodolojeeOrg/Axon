//
//  TTSSettingsViewModel.swift
//  Axon
//
//  Text-to-Speech settings management
//

import SwiftUI
import Combine

/// View model for TTS (Text-to-Speech) settings
@MainActor
class TTSSettingsViewModel: ObservableObject {
    @Published var availableVoices: [ElevenLabsService.ELVoice] = []
    @Published var availableTTSModels: [ElevenLabsService.ELTTSModel] = []
    
    private weak var core: SettingsViewModelCoreProtocol?
    
    init(core: SettingsViewModelCoreProtocol) {
        self.core = core
    }
    
    // MARK: - TTS Setting Updates
    
    func updateTTSSetting<T: Encodable & Equatable>(
        _ keyPath: WritableKeyPath<TTSSettings, T>,
        _ value: T
    ) async {
        guard let core = core else { return }
        
        var updated = core.settings.ttsSettings
        guard updated[keyPath: keyPath] != value else { return }
        
        updated[keyPath: keyPath] = value
        await core.updateSetting(\.ttsSettings, updated)
    }
    
    // MARK: - ElevenLabs Catalog
    
    func refreshElevenLabsCatalog() async {
        guard isTTSConfigured else { return }
        guard let core = core else { return }
        
        do {
            let voices = try await ElevenLabsService.shared.fetchVoices()
            let models = try await ElevenLabsService.shared.fetchTTSModels()
            self.availableVoices = voices
            self.availableTTSModels = models
            
            // Persist to Core Data cache (CloudKit syncable)
            await ElevenLabsVoiceCacheService.shared.upsertVoices(voices)
            
            // Keep legacy settings cache too (cheap + useful fallback)
            core.settings.ttsSettings.cachedVoices = voices
            try? core.storageService.saveSettings(core.settings)
            
            // Ensure selection is valid
            await ensureValidSelectedElevenLabsVoice(voices: voices)
        } catch {
            // Direct-to-ElevenLabs mode uses the local API key, so missing auth should be surfaced
            // as "key missing" (not Firebase auth errors).
            if let e = error as? ElevenLabsService.ElevenLabsError, case .apiKeyMissing = e {
                core.error = e.localizedDescription
                return
            }
            
            // For other errors, show the actual error
            core.error = "Failed to load ElevenLabs catalog: \(error.localizedDescription)"
        }
    }
    
    func updateSelectedVoice(id: String?, name: String?) async {
        guard let core = core else { return }
        
        print("[TTSSettingsViewModel] Updating selected voice to: \(name ?? "nil") (ID: \(id ?? "nil"))")
        var updated = core.settings.ttsSettings
        updated.selectedVoiceId = id
        updated.selectedVoiceName = name
        await core.updateSetting(\.ttsSettings, updated)
        print("[TTSSettingsViewModel] Voice selection saved. Current settings - Voice ID: \(core.settings.ttsSettings.selectedVoiceId ?? "nil"), Voice Name: \(core.settings.ttsSettings.selectedVoiceName ?? "nil")")
    }
    
    // MARK: - Voice Cache
    
    func hydrateElevenLabsVoicesFromCache() async {
        guard let core = core else { return }
        
        // 1) Load Core Data voice cache
        let cached = await ElevenLabsVoiceCacheService.shared.loadCachedVoices()
        if !cached.isEmpty {
            self.availableVoices = cached
            
            // Keep legacy settings cache in sync for fallback paths
            core.settings.ttsSettings.cachedVoices = cached
            try? core.storageService.saveSettings(core.settings)
            
            await ensureValidSelectedElevenLabsVoice(voices: cached)
            print("[TTSSettingsViewModel] Hydrated \(cached.count) ElevenLabs voices from Core Data cache")
        }
        
        // 2) If still empty, do nothing (user can tap refresh). We intentionally don't auto-fetch
        // to avoid surprising network calls. You can add TTL-based auto refresh later.
    }
    
    private func ensureValidSelectedElevenLabsVoice(voices: [ElevenLabsService.ELVoice]) async {
        guard let core = core else { return }
        guard !voices.isEmpty else { return }
        
        if let selectedId = core.settings.ttsSettings.selectedVoiceId,
           voices.contains(where: { $0.id == selectedId }) {
            // Selection is valid
            return
        }
        
        // Otherwise default to first voice
        let first = voices[0]
        print("[TTSSettingsViewModel] Selected voice missing; defaulting to first voice: \(first.name) (ID: \(first.id))")
        await updateSelectedVoice(id: first.id, name: first.name)
    }
    
    // MARK: - TTS API Key Helpers
    
    func saveTTSAPIKey(_ key: String, using apiKeys: APIKeysSettingsViewModel) async {
        await apiKeys.saveAPIKey(key, for: .elevenlabs)
        // After successful sync, refresh the catalog to verify it works
        await refreshElevenLabsCatalog()
    }
    
    func clearTTSAPIKey(using apiKeys: APIKeysSettingsViewModel) async {
        await apiKeys.clearAPIKey(.elevenlabs)
    }
    
    // MARK: - Computed Properties
    
    var isTTSConfigured: Bool {
        core?.apiKeysStorage.isConfigured(.elevenlabs) ?? false
    }
    
    var isGeminiTTSConfigured: Bool {
        core?.apiKeysStorage.isConfigured(.gemini) ?? false
    }
    
    var isOpenAITTSConfigured: Bool {
        core?.apiKeysStorage.isConfigured(.openai) ?? false
    }
    
    var isKokoroTTSConfigured: Bool {
        KokoroTTSService.shared.isModelAvailable
    }
}
