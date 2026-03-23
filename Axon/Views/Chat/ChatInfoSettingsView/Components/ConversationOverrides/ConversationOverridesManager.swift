//
//  ConversationOverridesManager.swift
//  Axon
//
//  Manages loading and saving per-conversation overrides
//

import Foundation
import SwiftUI

/// Manages per-conversation overrides stored in UserDefaults
class ConversationOverridesManager {
    
    // MARK: - Singleton
    
    static let shared = ConversationOverridesManager()
    private init() {}
    
    // MARK: - Keys
    
    private func overridesKey(for conversationId: String) -> String {
        "conversation_overrides_\(conversationId)"
    }
    
    // MARK: - Load/Save
    
    /// Load overrides for a specific conversation
    func loadOverrides(for conversationId: String) -> ConversationOverrides? {
        let key = overridesKey(for: conversationId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) else {
            return nil
        }
        return overrides
    }
    
    /// Save overrides for a specific conversation
    func saveOverrides(_ overrides: ConversationOverrides, for conversationId: String) {
        let key = overridesKey(for: conversationId)
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    /// Delete overrides for a specific conversation
    func deleteOverrides(for conversationId: String) {
        let key = overridesKey(for: conversationId)
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    // MARK: - Provider/Model Loading
    
    /// Load provider and model selections from overrides
    func loadProviderAndModel(
        for conversationId: String,
        settingsViewModel: SettingsViewModel
    ) -> (provider: UnifiedProvider?, model: UnifiedModel?, hasOverrides: Bool) {
        guard let overrides = loadOverrides(for: conversationId) else {
            // No overrides - use global defaults
            return (
                settingsViewModel.currentUnifiedProvider(),
                settingsViewModel.currentUnifiedModel(),
                false
            )
        }
        
        var selectedProvider: UnifiedProvider?
        var selectedModel: UnifiedModel?
        
        // Restore provider from override
        if let customProviderId = overrides.customProviderId,
           let customProvider = settingsViewModel.settings.customProviders.first(where: { $0.id == customProviderId }) {
            selectedProvider = .custom(customProvider)
        } else if let builtInProvider = AIProvider(rawValue: overrides.builtInProvider ?? "") {
            selectedProvider = .builtIn(builtInProvider)
        }
        
        // Restore model from override
        if let provider = selectedProvider {
            let providerIndex = settingsViewModel.settings.customProviders.firstIndex(where: {
                if case .custom(let config) = provider {
                    return $0.id == config.id
                }
                return false
            }) ?? 0
            let availableModels = provider.availableModels(customProviderIndex: providerIndex + 1)
            
            if let customModelId = overrides.customModelId {
                selectedModel = availableModels.first(where: {
                    if case .custom(let config, _, _, _) = $0 {
                        return config.id == customModelId
                    }
                    return false
                })
            } else if let builtInModel = overrides.builtInModel {
                selectedModel = availableModels.first(where: {
                    if case .builtIn(let model) = $0 {
                        return model.id == builtInModel
                    }
                    return false
                })
            }
        }
        
        return (selectedProvider, selectedModel, true)
    }
    
    /// Save provider and model selections to overrides
    func saveProviderAndModel(
        provider: UnifiedProvider?,
        model: UnifiedModel?,
        for conversationId: String
    ) {
        var overrides = loadOverrides(for: conversationId) ?? ConversationOverrides()
        
        // Save provider
        if let provider = provider {
            switch provider {
            case .builtIn(let aiProvider):
                overrides.builtInProvider = aiProvider.rawValue
                overrides.customProviderId = nil
            case .custom(let config):
                overrides.customProviderId = config.id
                overrides.builtInProvider = nil
            }
            overrides.providerDisplayName = provider.displayName
        }
        
        // Save model
        if let model = model {
            switch model {
            case .builtIn(let aiModel):
                overrides.builtInModel = aiModel.id
                overrides.customModelId = nil
            case .custom(let config, _, _, _):
                overrides.customModelId = config.id
                overrides.builtInModel = nil
            }
            overrides.modelDisplayName = model.name
        }
        
        saveOverrides(overrides, for: conversationId)
    }
    
    // MARK: - Live Settings Loading
    
    /// Load live provider, model, and voice settings from overrides
    func loadLiveSettings(for conversationId: String) -> (provider: String?, model: String?, voice: String?) {
        guard let overrides = loadOverrides(for: conversationId) else {
            return (nil, nil, nil)
        }
        return (overrides.liveProvider, overrides.liveModel, overrides.liveVoice)
    }
    
    /// Save live provider, model, and voice settings to overrides
    func saveLiveSettings(
        provider: String?,
        model: String?,
        voice: String?,
        for conversationId: String
    ) {
        var overrides = loadOverrides(for: conversationId) ?? ConversationOverrides()
        overrides.liveProvider = provider
        overrides.liveModel = model
        overrides.liveVoice = voice
        saveOverrides(overrides, for: conversationId)
    }
    
    // MARK: - Tool Settings Loading
    
    /// Load enabled tool IDs from overrides, falling back to global defaults
    func loadEnabledTools(
        for conversationId: String,
        settingsViewModel: SettingsViewModel
    ) -> (tools: Set<String>, hasCustomOverrides: Bool) {
        if let overrides = loadOverrides(for: conversationId),
           let toolOverrides = overrides.enabledToolIds {
            return (toolOverrides, true)
        }
        
        // Fall back to global defaults based on active tool system
        if ToolsV2Toggle.shared.isV2Active {
            return (ToolPluginLoader.shared.enabledToolIds, false)
        } else {
            return (settingsViewModel.settings.toolSettings.enabledToolIds, false)
        }
    }
    
    /// Save enabled tool IDs to overrides
    func saveEnabledTools(_ tools: Set<String>, for conversationId: String) {
        var overrides = loadOverrides(for: conversationId) ?? ConversationOverrides()
        overrides.enabledToolIds = tools
        saveOverrides(overrides, for: conversationId)
    }

    // MARK: - Subconscious Memory Logging

    /// Returns true if subconscious logging is disabled for this conversation.
    func isSubconsciousLoggingDisabled(for conversationId: String) -> Bool {
        loadOverrides(for: conversationId)?.subconsciousLoggingDisabled == true
    }

    /// Persist thread-level subconscious logging disable state.
    func setSubconsciousLoggingDisabled(_ disabled: Bool, for conversationId: String) {
        var overrides = loadOverrides(for: conversationId) ?? ConversationOverrides()
        overrides.subconsciousLoggingDisabled = disabled ? true : nil
        saveOverrides(overrides, for: conversationId)
    }
}
