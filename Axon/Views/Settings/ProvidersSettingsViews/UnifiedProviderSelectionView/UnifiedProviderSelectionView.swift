//
//  UnifiedProviderSelectionView.swift
//  Axon
//
//  Unified provider and model selection supporting both built-in and custom providers
//

import SwiftUI

/// Extension to SettingsViewModel for unified provider/model handling
extension SettingsViewModel {
    // MARK: - Provider/Model availability (API key gating)

    /// Whether a built-in provider should be selectable based on API key configuration.
    /// - Always visible: on-device providers (Apple Intelligence, local MLX)
    /// - Cloud providers: only visible if an API key is configured
    func isBuiltInProviderSelectable(_ provider: AIProvider) -> Bool {
        switch provider {
        case .appleFoundation, .localMLX:
            return true
        default:
            // For all cloud providers, only show if user has configured the API key.
            // AIProvider raw values match APIProvider raw values for these cases.
            guard let apiProvider = APIProvider(rawValue: provider.rawValue) else {
                return false
            }
            return isAPIKeyConfigured(apiProvider)
        }
    }

    /// Whether a custom provider should be selectable.
    /// Option A: hide custom providers unless configured.
    func isCustomProviderSelectable(_ providerId: UUID) -> Bool {
        isCustomProviderConfigured(providerId)
    }

    /// Get all providers (built-in + custom) as unified list
    func allUnifiedProviders() -> [UnifiedProvider] {
        var providers: [UnifiedProvider] = AIProvider.allCases.map { .builtIn($0) }
        providers.append(contentsOf: settings.customProviders.map { .custom($0) })
        return providers
    }

    /// Providers filtered for selection in UI.
    func selectableUnifiedProviders() -> [UnifiedProvider] {
        allUnifiedProviders().filter { provider in
            switch provider {
            case .builtIn(let p):
                return isBuiltInProviderSelectable(p)
            case .custom(let config):
                return isCustomProviderSelectable(config.id)
            }
        }
    }

    /// Models for a provider (currently just a passthrough; exists for symmetry).
    func selectableModels(for provider: UnifiedProvider, customProviderIndex: Int? = nil) -> [UnifiedModel] {
        provider.availableModels(customProviderIndex: customProviderIndex)
    }

    /// Best-effort fallback provider when the current selection becomes unavailable.
    func fallbackUnifiedProvider() -> UnifiedProvider? {
        // 1) Prefer Apple Intelligence when available on this OS
        if AIProvider.appleFoundation.isAvailable {
            return .builtIn(.appleFoundation)
        }

        // 2) Prefer local MLX when available (physical device)
        if AIProvider.localMLX.isAvailable {
            return .builtIn(.localMLX)
        }

        // 3) Otherwise first selectable provider (configured cloud/custom)
        return selectableUnifiedProviders().first
    }

    // MARK: - Current selections

    /// Get currently selected unified provider
    func currentUnifiedProvider() -> UnifiedProvider? {
        if let customProviderId = settings.selectedCustomProviderId,
           let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }) {
            return .custom(customProvider)
        }
        return .builtIn(settings.defaultProvider)
    }

    /// Get currently selected unified model
    func currentUnifiedModel() -> UnifiedModel? {
        if let customProviderId = settings.selectedCustomProviderId,
           let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }),
           let customModelId = settings.selectedCustomModelId,
           let customModel = customProvider.models.first(where: { $0.id == customModelId }) {
            let providerIndex = settings.customProviders.firstIndex(where: { $0.id == customProviderId }) ?? 0
            let modelIndex = customProvider.models.firstIndex(where: { $0.id == customModelId }) ?? 0
            return .custom(customModel, providerName: customProvider.providerName, providerIndex: providerIndex + 1, modelIndex: modelIndex + 1)
        }

        // Fall back to built-in model (check registry first, then hardcoded enum)
        let registryModels = UnifiedModelRegistry.shared.chatModels(for: settings.defaultProvider)
        let availableModels = registryModels.isEmpty ? settings.defaultProvider.availableModels : registryModels
        if let builtInModel = availableModels.first(where: { $0.id == settings.defaultModel }) {
            return .builtIn(builtInModel)
        }

        return nil
    }

    // MARK: - Selection helpers

    /// Select a unified provider
    func selectUnifiedProvider(_ provider: UnifiedProvider) async {
        switch provider {
        case .builtIn(let aiProvider):
            // Switch to built-in provider
            settings.selectedCustomProviderId = nil
            settings.selectedCustomModelId = nil
            await updateSetting(\.defaultProvider, aiProvider)

            // Select first model from this provider (check registry first)
            let registryModels = UnifiedModelRegistry.shared.chatModels(for: aiProvider)
            let availableModels = registryModels.isEmpty ? aiProvider.availableModels : registryModels
            if let firstModel = availableModels.first {
                await updateSetting(\.defaultModel, firstModel.id)
            }

        case .custom(let config):
            // Switch to custom provider
            await updateSetting(\.selectedCustomProviderId, config.id)

            // Select first model from this custom provider
            if let firstModel = config.models.first {
                await updateSetting(\.selectedCustomModelId, firstModel.id)
            }
        }
    }

    /// Select a unified model
    func selectUnifiedModel(_ model: UnifiedModel) async {
        switch model {
        case .builtIn(let aiModel):
            // Selecting a built-in model
            settings.selectedCustomProviderId = nil
            settings.selectedCustomModelId = nil
            await updateSetting(\.defaultProvider, aiModel.provider)
            await updateSetting(\.defaultModel, aiModel.id)

        case .custom(let customModel, _, _, _):
            // Find which custom provider this model belongs to
            for customProvider in settings.customProviders {
                if customProvider.models.contains(where: { $0.id == customModel.id }) {
                    await updateSetting(\.selectedCustomProviderId, customProvider.id)
                    await updateSetting(\.selectedCustomModelId, customModel.id)
                    break
                }
            }
        }
    }
}
