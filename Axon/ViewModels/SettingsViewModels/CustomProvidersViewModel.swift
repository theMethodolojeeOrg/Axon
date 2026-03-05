//
//  CustomProvidersViewModel.swift
//  Axon
//
//  Custom AI provider management
//

import SwiftUI
import Combine

/// View model for managing custom AI providers
@MainActor
class CustomProvidersViewModel: ObservableObject {
    private weak var core: SettingsViewModelCoreProtocol?
    
    init(core: SettingsViewModelCoreProtocol) {
        self.core = core
    }
    
    // MARK: - Custom Provider CRUD
    
    func addCustomProvider(_ config: CustomProviderConfig) async {
        guard let core = core else { return }
        
        core.settings.customProviders.append(config)
        core.settings.lastUpdated = Date()
        
        do {
            try core.storageService.saveSettings(core.settings)
            core.showSuccessMessage("Custom provider '\(config.providerName)' added successfully")
        } catch {
            core.error = "Failed to save custom provider: \(error.localizedDescription)"
        }
    }
    
    func updateCustomProvider(_ config: CustomProviderConfig) async {
        guard let core = core else { return }
        guard let index = core.settings.customProviders.firstIndex(where: { $0.id == config.id }) else {
            core.error = "Custom provider not found"
            return
        }
        
        core.settings.customProviders[index] = config
        core.settings.lastUpdated = Date()
        
        do {
            try core.storageService.saveSettings(core.settings)
            core.showSuccessMessage("Custom provider '\(config.providerName)' updated successfully")
        } catch {
            core.error = "Failed to update custom provider: \(error.localizedDescription)"
        }
    }
    
    func deleteCustomProvider(id: UUID) async {
        guard let core = core else { return }
        
        core.settings.customProviders.removeAll { $0.id == id }
        core.settings.lastUpdated = Date()
        
        do {
            try core.storageService.saveSettings(core.settings)
            // Also clear the API key for this provider
            try? core.apiKeysStorage.clearCustomProviderAPIKey(providerId: id)
            core.showSuccessMessage("Custom provider deleted successfully")
        } catch {
            core.error = "Failed to delete custom provider: \(error.localizedDescription)"
        }
    }
    
    func getCustomProvider(id: UUID) -> CustomProviderConfig? {
        core?.settings.customProviders.first { $0.id == id }
    }
    
    // MARK: - Custom Provider API Keys
    
    func isCustomProviderConfigured(_ providerId: UUID) -> Bool {
        core?.apiKeysStorage.isCustomProviderConfigured(providerId: providerId) ?? false
    }
    
    func getCustomProviderAPIKey(providerId: UUID) -> String? {
        try? core?.apiKeysStorage.getCustomProviderAPIKey(providerId: providerId)
    }
    
    func saveCustomProviderAPIKey(_ key: String, providerId: UUID, providerName: String) async {
        guard let core = core else { return }
        
        core.isLoading = true
        defer { core.isLoading = false }
        
        do {
            try core.apiKeysStorage.saveCustomProviderAPIKey(key, providerId: providerId)
            core.showSuccessMessage("\(providerName) API key saved securely")
        } catch {
            core.error = "Failed to save API key: \(error.localizedDescription)"
        }
    }
    
    func clearCustomProviderAPIKey(providerId: UUID, providerName: String) async {
        guard let core = core else { return }
        
        do {
            try core.apiKeysStorage.clearCustomProviderAPIKey(providerId: providerId)
            core.showSuccessMessage("\(providerName) API key removed")
        } catch {
            core.error = "Failed to clear API key: \(error.localizedDescription)"
        }
    }
}
