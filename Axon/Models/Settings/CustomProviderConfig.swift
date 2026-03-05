//
//  CustomProviderConfig.swift
//  Axon
//
//  Custom provider and model configuration
//

import Foundation

// MARK: - Custom Provider Configuration

struct CustomProviderConfig: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var providerName: String
    var apiEndpoint: String
    var models: [CustomModelConfig]

    init(id: UUID = UUID(), providerName: String, apiEndpoint: String, models: [CustomModelConfig] = []) {
        self.id = id
        self.providerName = providerName
        self.apiEndpoint = apiEndpoint
        self.models = models
    }
}

// MARK: - Custom Model Configuration

struct CustomModelConfig: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var modelCode: String
    var friendlyName: String?
    var contextWindow: Int
    var description: String?
    var pricing: CustomModelPricing?
    var colorHex: String?  // Optional hex color (RRGGBB format, uppercase, no #)
    var acceptedAttachmentMimeTypes: [String]?  // Optional per-model MIME allowlist

    init(
        id: UUID = UUID(),
        modelCode: String,
        friendlyName: String? = nil,
        contextWindow: Int = 128_000,
        description: String? = nil,
        pricing: CustomModelPricing? = nil,
        colorHex: String? = nil,
        acceptedAttachmentMimeTypes: [String]? = nil
    ) {
        self.id = id
        self.modelCode = modelCode
        self.friendlyName = friendlyName
        self.contextWindow = contextWindow
        self.description = description
        self.pricing = pricing
        self.colorHex = colorHex
        self.acceptedAttachmentMimeTypes = acceptedAttachmentMimeTypes
    }

    /// Display name with fallback logic
    func displayName(providerName: String) -> String {
        return friendlyName ?? providerName
    }

    /// Auto-generated description with fallback
    func displayDescription(providerIndex: Int, modelIndex: Int) -> String {
        return description ?? "Custom Provider \(providerIndex), Model \(modelIndex)"
    }
}

// MARK: - Custom Model Pricing

struct CustomModelPricing: Codable, Equatable, Hashable, Sendable {
    var inputPerMTok: Double
    var outputPerMTok: Double
    var cachedInputPerMTok: Double?

    init(inputPerMTok: Double, outputPerMTok: Double, cachedInputPerMTok: Double? = nil) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
        self.cachedInputPerMTok = cachedInputPerMTok
    }

    /// Format pricing for display
    func formattedPricing() -> String {
        var parts: [String] = []
        parts.append(String(format: "$%.2f in / $%.2f out per 1M tokens", inputPerMTok, outputPerMTok))
        if let cached = cachedInputPerMTok {
            parts.append(String(format: "cached: $%.2f", cached))
        }
        return parts.joined(separator: " · ")
    }
}
