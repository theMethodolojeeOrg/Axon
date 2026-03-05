//
//  ModelOverride.swift
//  Axon
//
//  Per-model generation parameter overrides
//

import Foundation

// MARK: - Per-Model Generation Override

/// Per-model override for generation parameters
/// Allows fine-tuning specific models without affecting others
struct ModelOverride: Codable, Equatable, Identifiable, Sendable {
    /// Model ID (e.g., "lmstudio-community/gemma-3-270m-it-MLX-8bit")
    let id: String

    /// Whether this override is active
    var enabled: Bool = false

    // MARK: - Override Values (nil = use global default)

    /// Temperature override (0.0-1.0)
    var temperature: Double?

    /// Top-P override (0.0-1.0)
    var topP: Double?

    /// Top-K override (1-100)
    var topK: Int?

    /// Repetition penalty override (1.0-2.0)
    var repetitionPenalty: Double?

    /// Repetition context size override (16-512 tokens)
    var repetitionContextSize: Int?

    /// Max response tokens override (128-4096)
    var maxResponseTokens: Int?

    /// Custom system prompt suffix for this model
    var systemPromptSuffix: String?

    // MARK: - Initialization

    init(modelId: String) {
        self.id = modelId
    }

    init(
        modelId: String,
        enabled: Bool = false,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        repetitionPenalty: Double? = nil,
        repetitionContextSize: Int? = nil,
        maxResponseTokens: Int? = nil,
        systemPromptSuffix: String? = nil
    ) {
        self.id = modelId
        self.enabled = enabled
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repetitionPenalty = repetitionPenalty
        self.repetitionContextSize = repetitionContextSize
        self.maxResponseTokens = maxResponseTokens
        self.systemPromptSuffix = systemPromptSuffix
    }

    /// Check if any override values are set
    var hasOverrides: Bool {
        temperature != nil ||
        topP != nil ||
        topK != nil ||
        repetitionPenalty != nil ||
        repetitionContextSize != nil ||
        maxResponseTokens != nil ||
        (systemPromptSuffix != nil && !systemPromptSuffix!.isEmpty)
    }

    /// Count of active overrides
    var overrideCount: Int {
        var count = 0
        if temperature != nil { count += 1 }
        if topP != nil { count += 1 }
        if topK != nil { count += 1 }
        if repetitionPenalty != nil { count += 1 }
        if repetitionContextSize != nil { count += 1 }
        if maxResponseTokens != nil { count += 1 }
        if systemPromptSuffix != nil && !systemPromptSuffix!.isEmpty { count += 1 }
        return count
    }

    /// Clear all override values
    mutating func clearOverrides() {
        temperature = nil
        topP = nil
        topK = nil
        repetitionPenalty = nil
        repetitionContextSize = nil
        maxResponseTokens = nil
        systemPromptSuffix = nil
    }
}

// MARK: - Model Override Presets

/// Pre-configured override presets for common model types
enum ModelOverridePreset: String, CaseIterable, Identifiable {
    case smallModel = "small_model"
    case visionModel = "vision_model"
    case codingModel = "coding_model"
    case creativeModel = "creative_model"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smallModel: return "Small Model (< 3B)"
        case .visionModel: return "Vision Model"
        case .codingModel: return "Coding Focus"
        case .creativeModel: return "Creative Writing"
        }
    }

    var description: String {
        switch self {
        case .smallModel: return "Higher repetition penalty, shorter responses"
        case .visionModel: return "Balanced settings for multimodal"
        case .codingModel: return "Lower temperature for precise code"
        case .creativeModel: return "Higher temperature for creativity"
        }
    }

    /// Create a ModelOverride with preset values
    func createOverride(for modelId: String) -> ModelOverride {
        switch self {
        case .smallModel:
            return ModelOverride(
                modelId: modelId,
                enabled: true,
                temperature: 0.7,
                topP: 0.85,
                repetitionPenalty: 1.5,
                repetitionContextSize: 256,
                maxResponseTokens: 512
            )
        case .visionModel:
            return ModelOverride(
                modelId: modelId,
                enabled: true,
                temperature: 0.7,
                topP: 0.9,
                repetitionPenalty: 1.2,
                repetitionContextSize: 128,
                maxResponseTokens: 1024
            )
        case .codingModel:
            return ModelOverride(
                modelId: modelId,
                enabled: true,
                temperature: 0.3,
                topP: 0.95,
                repetitionPenalty: 1.1,
                maxResponseTokens: 2048
            )
        case .creativeModel:
            return ModelOverride(
                modelId: modelId,
                enabled: true,
                temperature: 0.9,
                topP: 0.95,
                repetitionPenalty: 1.0,
                maxResponseTokens: 2048
            )
        }
    }
}
