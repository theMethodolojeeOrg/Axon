//
//  ProviderModelHelpers.swift
//  Axon
//
//  Helper functions for provider and model selection in ChatInfoSettingsView
//

import Foundation

/// Helper functions for provider and model selection
enum ProviderModelHelpers {
    
    /// Select a provider and auto-select its first available model
    static func selectProvider(
        _ provider: UnifiedProvider?,
        settingsViewModel: SettingsViewModel
    ) -> UnifiedModel? {
        guard let provider = provider else { return nil }
        
        let providerIndex = settingsViewModel.settings.customProviders.firstIndex(where: {
            if case .custom(let config) = provider {
                return $0.id == config.id
            }
            return false
        }) ?? 0
        
        let models = provider.availableModels(customProviderIndex: providerIndex + 1)
        return models.first
    }
    
    /// Format a number for display (e.g., 1000 -> "1.0K", 1000000 -> "1.0M")
    static func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}
