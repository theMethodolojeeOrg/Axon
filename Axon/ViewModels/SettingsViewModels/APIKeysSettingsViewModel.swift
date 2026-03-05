//
//  APIKeysSettingsViewModel.swift
//  Axon
//
//  API key management for providers
//

import SwiftUI
import Combine

/// View model for managing API keys across providers
@MainActor
class APIKeysSettingsViewModel: ObservableObject {
    private weak var core: SettingsViewModelCoreProtocol?
    private let iCloudSync = iCloudKeyValueSync.shared
    
    init(core: SettingsViewModelCoreProtocol) {
        self.core = core
    }
    
    // MARK: - API Key Management
    
    func isAPIKeyConfigured(_ provider: APIProvider) -> Bool {
        core?.apiKeysStorage.isConfigured(provider) ?? false
    }
    
    func getAPIKey(_ provider: APIProvider) -> String? {
        try? core?.apiKeysStorage.getAPIKey(for: provider)
    }
    
    func saveAPIKey(_ key: String, for provider: APIProvider) async {
        guard let core = core else { return }
        
        core.isLoading = true
        defer { core.isLoading = false }
        
        do {
            // 1) Always save locally (SecureVault)
            try core.apiKeysStorage.saveAPIKey(key, for: provider)
            
            // 2) If user selected iCloud sync, also save to iCloud Keychain so it roams across devices.
            if core.settings.deviceModeConfig.cloudSyncProvider == .iCloud {
                do {
                    try iCloudKeychainService.shared.saveAPIKey(key, for: provider)
                } catch {
                    // Non-fatal: local save succeeded.
                    print("[APIKeysSettingsViewModel] Warning: Key saved locally but failed to sync to iCloud Keychain: \(error.localizedDescription)")
                }
            }
            
            // 3) Firestore sync only when explicitly enabled.
            if core.settings.deviceModeConfig.cloudSyncProvider == .firestore,
               provider == .elevenlabs,
               BackendConfig.shared.isBackendConfigured {
                do {
                    try await EncryptionService.shared.encryptAndSyncElevenLabsKey(key)
                } catch {
                    // Log the sync error but don't fail the entire save operation
                    print("[APIKeysSettingsViewModel] Warning: Key saved locally but sync to Firestore failed: \(error.localizedDescription)")
                    core.error = "API key saved locally, but cloud sync failed. Error: \(error.localizedDescription)"
                    return
                }
            }
            
            core.showSuccessMessage("\(provider.displayName) API key saved securely")
        } catch {
            core.error = "Failed to save API key: \(error.localizedDescription)"
        }
    }
    
    func clearAPIKey(_ provider: APIProvider) async {
        guard let core = core else { return }
        
        do {
            try core.apiKeysStorage.clearAPIKey(for: provider)
            
            // Best-effort delete from iCloud Keychain too.
            try? iCloudKeychainService.shared.deleteAPIKey(for: provider)
            
            core.showSuccessMessage("\(provider.displayName) API key removed")
        } catch {
            core.error = "Failed to clear API key: \(error.localizedDescription)"
        }
    }
    
    // MARK: - iCloud Keychain Import
    
    func importAPIKeysFromiCloudKeychainIfNeeded() {
        guard let core = core else { return }
        guard core.settings.deviceModeConfig.cloudSyncProvider == .iCloud else { return }
        
        // Only attempt if iCloud Keychain is generally available.
        guard iCloudSync.isAvailable else {
            print("[APIKeysSettingsViewModel] iCloud Keychain not available; skipping API key import")
            return
        }
        
        for provider in APIProvider.allCases {
            // Don't overwrite existing local key.
            if core.apiKeysStorage.isConfigured(provider) {
                print("[APIKeysSettingsViewModel] API key already configured locally: \(provider.rawValue)")
                continue
            }
            
            do {
                let key = try iCloudKeychainService.shared.getAPIKey(for: provider)
                if let key, !key.isEmpty {
                    try core.apiKeysStorage.saveAPIKey(key, for: provider)
                    print("[APIKeysSettingsViewModel] ✅ Imported \(provider.rawValue) API key from iCloud Keychain")
                } else {
                    print("[APIKeysSettingsViewModel] No iCloud Keychain key found for: \(provider.rawValue)")
                }
            } catch {
                print("[APIKeysSettingsViewModel] ❌ Failed to read/import \(provider.rawValue) from iCloud Keychain: \(error.localizedDescription)")
            }
        }
    }
}
