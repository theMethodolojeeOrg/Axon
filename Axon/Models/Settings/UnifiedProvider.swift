//
//  UnifiedProvider.swift
//  Axon
//
//  Unified provider and model types for UI
//

import Foundation

// MARK: - Unified Provider & Model (for UI)

/// Unified provider that can represent either built-in or custom providers
enum UnifiedProvider: Identifiable, Hashable {
    case builtIn(AIProvider)
    case custom(CustomProviderConfig)

    var id: String {
        switch self {
        case .builtIn(let provider):
            return "builtin_\(provider.rawValue)"
        case .custom(let config):
            return "custom_\(config.id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .builtIn(let provider):
            return provider.displayName
        case .custom(let config):
            return config.providerName
        }
    }

    var isCustom: Bool {
        if case .custom = self {
            return true
        }
        return false
    }

    func availableModels(customProviderIndex: Int? = nil) -> [UnifiedModel] {
        switch self {
        case .builtIn(let provider):
            // Use registry first, fall back to hardcoded enum for backwards compatibility
            let registryModels = UnifiedModelRegistry.shared.chatModels(for: provider)
            let models = registryModels.isEmpty ? provider.availableModels : registryModels
            return models.map { UnifiedModel.builtIn($0) }
        case .custom(let config):
            return config.models.enumerated().map { index, model in
                UnifiedModel.custom(model, providerName: config.providerName, providerIndex: customProviderIndex ?? 1, modelIndex: index + 1)
            }
        }
    }
}

/// Unified model that can represent either built-in or custom models
enum UnifiedModel: Identifiable, Hashable, Sendable {
    case builtIn(AIModel)
    case custom(CustomModelConfig, providerName: String, providerIndex: Int, modelIndex: Int)

    var id: String {
        switch self {
        case .builtIn(let model):
            return "builtin_\(model.id)"
        case .custom(let config, _, _, _):
            return "custom_\(config.id.uuidString)"
        }
    }

    var name: String {
        switch self {
        case .builtIn(let model):
            return model.name
        case .custom(let config, let providerName, _, _):
            return config.displayName(providerName: providerName)
        }
    }

    var description: String {
        switch self {
        case .builtIn(let model):
            return model.description
        case .custom(let config, _, let providerIndex, let modelIndex):
            return config.displayDescription(providerIndex: providerIndex, modelIndex: modelIndex)
        }
    }

    var contextWindow: Int {
        switch self {
        case .builtIn(let model):
            return model.contextWindow
        case .custom(let config, _, _, _):
            return config.contextWindow
        }
    }

    var modalities: [String] {
        switch self {
        case .builtIn(let model):
            return model.modalities
        case .custom:
            // Assume custom models support text and image by default, or make it configurable later
            return ["text", "image"]
        }
    }

    var pricing: CustomModelPricing? {
        switch self {
        case .builtIn:
            return nil  // Built-in models use PricingRegistry
        case .custom(let config, _, _, _):
            return config.pricing
        }
    }

    var modelCode: String {
        switch self {
        case .builtIn(let model):
            return model.id
        case .custom(let config, _, _, _):
            return config.modelCode
        }
    }
}
