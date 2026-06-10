//
//  MLXModelService.swift
//  Axon
//
//  Compatibility facade over AxonProviderKit's MLX runtime service.
//

import Foundation
import Combine
import AxonProviderKit
import AxonProviderKitCore

/// Error types for MLX model operations.
enum MLXModelError: LocalizedError {
    case modelNotFound(String)
    case loadFailed(String)
    case generationFailed(String)
    case notAvailable
    case simulatorNotSupported
    case downloadFailed(String)
    case notLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "MLX model not found at: \(path)"
        case .loadFailed(let reason):
            return "Failed to load MLX model: \(reason)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .notAvailable:
            return "MLX is not available on this platform"
        case .simulatorNotSupported:
            return "MLX requires a physical device (Metal GPU not available in simulator)"
        case .downloadFailed(let reason):
            return "Failed to download model: \(reason)"
        case .notLoaded:
            return "No model is currently loaded"
        }
    }
}

/// Axon-facing curated MLX model identifiers.
enum LocalMLXModel: String, CaseIterable {
    case gemma4_E2B = "google/gemma-4-E2B-it-MLX"
    case qwen3VL = "mlx-community/Qwen3-VL-2B-Instruct-4bit"
    case gemma3_270m = "lmstudio-community/gemma-3-270m-it-MLX-8bit"
    case smolLM = "mlx-community/SmolLM2-1.7B-Instruct-4bit"
    case qwen3 = "mlx-community/Qwen3-1.7B-4bit"
    case phi4Mini = "mlx-community/Phi-4-mini-instruct-4bit"
    case llama32 = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    static var defaultModel: LocalMLXModel { .gemma4_E2B }

    var isBundled: Bool {
        switch self {
        case .gemma4_E2B, .qwen3VL, .gemma3_270m:
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .gemma4_E2B: return "Gemma 4 E2B"
        case .qwen3VL: return "Qwen3 VL 2B"
        case .gemma3_270m: return "Gemma3 270M"
        case .smolLM: return "SmolLM2 1.7B"
        case .qwen3: return "Qwen3 1.7B"
        case .phi4Mini: return "Phi-4 Mini"
        case .llama32: return "Llama 3.2 1B"
        }
    }

    var description: String {
        switch self {
        case .gemma4_E2B:
            return "Google's Gemma 4 model. Most capable bundled option. Bundled in app - ready instantly."
        case .qwen3VL:
            return "Vision-language model. Bundled in app - ready instantly."
        case .gemma3_270m:
            return "Google's ultra-compact model. Fastest option. Bundled in app - ready instantly."
        case .smolLM:
            return "HuggingFace's efficient small model. ~1GB download."
        case .qwen3:
            return "Alibaba's multilingual model. ~1GB download."
        case .phi4Mini:
            return "Microsoft's capable small model. ~2GB download."
        case .llama32:
            return "Meta's compact model. ~0.7GB download."
        }
    }

    var contextWindow: Int {
        switch self {
        case .gemma4_E2B, .qwen3VL, .gemma3_270m, .smolLM, .llama32:
            return 8_192
        case .qwen3:
            return 32_768
        case .phi4Mini:
            return 16_384
        }
    }

    var modalities: [String] {
        switch self {
        case .qwen3VL:
            return ["text", "vision"]
        default:
            return ["text"]
        }
    }

    var isVisionModel: Bool {
        modalities.contains("vision")
    }

    func toAIModel() -> AIModel {
        AIModel(
            id: rawValue,
            name: displayName,
            provider: .localMLX,
            contextWindow: contextWindow,
            modalities: modalities,
            description: description
        )
    }
}

/// Helper for locating bundled MLX models in the host app bundle.
struct BundledMLXModels {
    static func bundledModelPath(for modelId: String) -> URL? {
        AxonProviderKitCore.BundledMLXModels.bundledModelPath(for: modelId)
    }

    static func isBundled(_ modelId: String) -> Bool {
        bundledModelPath(for: modelId) != nil
    }

    static var defaultModelId: String {
        LocalMLXModel.defaultModel.rawValue
    }
}

@MainActor
final class MLXModelService: ObservableObject {
    static let shared = MLXModelService()

    @Published private(set) var isLoading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var loadingStatus: String = ""
    @Published private(set) var downloadedModels: Set<String> = []
    @Published private(set) var modelInMemory: String?
    @Published private(set) var downloadingModel: String?

    private let providerService = AxonProviderKit.MLXModelService.shared

    private init() {
        ProviderKitModelCatalogAdapter.bootstrapMLXCatalog()
        updateDownloadedModels()
    }

    func clearCache() {
        providerService.clearCache()
        refreshState()
    }

    func unloadModel() {
        providerService.unloadModel()
        refreshState()
    }

    var isModelLoaded: Bool {
        providerService.isModelLoaded
    }

    func updateDownloadedModels() {
        providerService.updateDownloadedModels()
        refreshState()
        MLXModelRegistry.shared.syncFromDownloadedIds(downloadedModels)
    }

    func isModelDownloaded(modelId: String) -> Bool {
        providerService.isModelDownloaded(modelId: modelId)
    }

    func getModelPath(modelId: String) -> URL? {
        providerService.getModelPath(modelId: modelId)
    }

    func getModelSize(modelId: String) -> Int64? {
        providerService.getModelSize(modelId: modelId)
    }

    func deleteModel(modelId: String) async throws {
        do {
            try await providerService.deleteModel(modelId: modelId)
            refreshState()
            MLXModelRegistry.shared.syncFromDownloadedIds(downloadedModels)
        } catch {
            throw mapProviderError(error)
        }
    }

    func getTotalModelsSize() -> Int64 {
        providerService.getTotalModelsSize()
    }

    func loadModel(modelId: String = LocalMLXModel.defaultModel.rawValue) async throws {
        isLoading = true
        loadingStatus = "Loading model..."
        downloadingModel = modelId
        defer {
            refreshState()
            isLoading = false
            loadingStatus = ""
            downloadProgress = 0
            downloadingModel = nil
        }

        do {
            try await providerService.loadModel(modelId: modelId)
            MLXModelRegistry.shared.syncFromDownloadedIds(providerService.downloadedModels)
        } catch {
            throw mapProviderError(error)
        }
    }

    func loadGenerationConfig(for modelId: String) -> MLXGenerationConfig? {
        providerService.loadGenerationConfig(for: modelId)
    }

    func getEffectiveParameters(
        modelId: String,
        settings: AppSettings,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        repetitionPenalty: Double? = nil,
        repetitionContextSize: Int? = nil
    ) -> (maxTokens: Int, temperature: Double, topP: Double, repetitionPenalty: Double, repetitionContextSize: Int) {
        var effectiveMaxTokens = 2048
        var effectiveTemperature = 0.7
        var effectiveTopP = 0.8
        var effectiveRepPenalty = 1.2
        var effectiveRepContext = 64

        if let modelConfig = loadGenerationConfig(for: modelId) {
            if let temp = modelConfig.temperature { effectiveTemperature = temp }
            if let modelTopP = modelConfig.topP { effectiveTopP = modelTopP }
            if let repPenalty = modelConfig.repetitionPenalty { effectiveRepPenalty = repPenalty }
            if let maxNew = modelConfig.maxNewTokens { effectiveMaxTokens = maxNew }
        }

        if let override = settings.modelOverrides[modelId], override.enabled {
            if let temp = override.temperature { effectiveTemperature = temp }
            if let modelTopP = override.topP { effectiveTopP = modelTopP }
            if let repPenalty = override.repetitionPenalty { effectiveRepPenalty = repPenalty }
            if let repContext = override.repetitionContextSize { effectiveRepContext = repContext }
            if let maxResponseTokens = override.maxResponseTokens { effectiveMaxTokens = maxResponseTokens }
        }

        let globalSettings = settings.modelGenerationSettings
        let hasModelOverride = settings.modelOverrides[modelId]?.enabled == true

        if !hasModelOverride {
            if globalSettings.temperatureEnabled { effectiveTemperature = globalSettings.temperature }
            if globalSettings.topPEnabled { effectiveTopP = globalSettings.topP }
            if globalSettings.repetitionPenaltyEnabled {
                effectiveRepPenalty = globalSettings.repetitionPenalty
                effectiveRepContext = globalSettings.repetitionContextSize
            }
            if globalSettings.maxResponseTokensEnabled { effectiveMaxTokens = globalSettings.maxResponseTokens }
        }

        if let maxTokens { effectiveMaxTokens = maxTokens }
        if let temperature { effectiveTemperature = temperature }
        if let topP { effectiveTopP = topP }
        if let repetitionPenalty { effectiveRepPenalty = repetitionPenalty }
        if let repetitionContextSize { effectiveRepContext = repetitionContextSize }

        return (effectiveMaxTokens, effectiveTemperature, effectiveTopP, effectiveRepPenalty, effectiveRepContext)
    }

    func generate(
        systemPrompt: String?,
        messages: [Message],
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        repetitionPenalty: Double? = nil,
        repetitionContextSize: Int? = nil,
        settings: AppSettings? = nil
    ) async throws -> String {
        let effective = effectiveParametersForLoadedModel(
            settings: settings,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            repetitionPenalty: repetitionPenalty,
            repetitionContextSize: repetitionContextSize
        )

        do {
            return try await providerService.generate(
                systemPrompt: systemPrompt,
                messages: Self.providerKitMessages(from: messages),
                maxTokens: effective.maxTokens,
                temperature: effective.temperature,
                topP: effective.topP,
                repetitionPenalty: effective.repetitionPenalty,
                repetitionContextSize: effective.repetitionContextSize
            )
        } catch {
            throw mapProviderError(error)
        }
    }

    func generateStreaming(
        systemPrompt: String?,
        messages: [Message],
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        repetitionPenalty: Double? = nil,
        repetitionContextSize: Int? = nil,
        settings: AppSettings? = nil,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        let effective = effectiveParametersForLoadedModel(
            settings: settings,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            repetitionPenalty: repetitionPenalty,
            repetitionContextSize: repetitionContextSize
        )

        do {
            try await providerService.generateStreaming(
                systemPrompt: systemPrompt,
                messages: Self.providerKitMessages(from: messages),
                maxTokens: effective.maxTokens,
                temperature: effective.temperature,
                topP: effective.topP,
                repetitionPenalty: effective.repetitionPenalty,
                repetitionContextSize: effective.repetitionContextSize,
                onToken: onToken
            )
        } catch {
            throw mapProviderError(error)
        }
    }

    func generateStreaming(
        systemPrompt: String?,
        messages: [[String: String]],
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        repetitionPenalty: Double,
        repetitionContextSize: Int,
        onToken: @escaping (String) -> Void
    ) async throws {
        do {
            try await providerService.generateStreaming(
                systemPrompt: systemPrompt,
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty,
                repetitionContextSize: repetitionContextSize,
                onToken: onToken
            )
        } catch {
            throw mapProviderError(error)
        }
    }

    private func refreshState() {
        downloadedModels = providerService.downloadedModels
        modelInMemory = providerService.modelInMemory
        downloadingModel = providerService.downloadingModel
        downloadProgress = providerService.downloadProgress
        loadingStatus = providerService.loadingStatus
        isLoading = providerService.isLoading
    }

    private func effectiveParametersForLoadedModel(
        settings: AppSettings?,
        maxTokens: Int?,
        temperature: Double?,
        topP: Double?,
        repetitionPenalty: Double?,
        repetitionContextSize: Int?
    ) -> (maxTokens: Int, temperature: Double, topP: Double, repetitionPenalty: Double, repetitionContextSize: Int) {
        guard let settings, let modelId = modelInMemory else {
            return (
                maxTokens: maxTokens ?? 2048,
                temperature: temperature ?? 0.7,
                topP: topP ?? 0.8,
                repetitionPenalty: repetitionPenalty ?? 1.2,
                repetitionContextSize: repetitionContextSize ?? 64
            )
        }

        return getEffectiveParameters(
            modelId: modelId,
            settings: settings,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            repetitionPenalty: repetitionPenalty,
            repetitionContextSize: repetitionContextSize
        )
    }

    private static func providerKitMessages(from messages: [Message]) -> [AxonProviderKitCore.Message] {
        messages.map { message in
            let role: AxonProviderKitCore.MessageRole
            switch message.role {
            case .assistant:
                role = .assistant
            case .system:
                role = .system
            case .user:
                role = .user
            }
            return AxonProviderKitCore.Message(role: role, content: message.content)
        }
    }

    private func mapProviderError(_ error: Error) -> MLXModelError {
        guard let providerError = error as? MLXProviderError else {
            return .generationFailed(error.localizedDescription)
        }

        switch providerError {
        case .frameworkNotAvailable:
            return .notAvailable
        case .simulatorNotSupported:
            return .simulatorNotSupported
        case .modelNotLoaded:
            return .notLoaded
        case .modelLoadFailed(let reason):
            return .loadFailed(reason)
        case .generationFailed(let reason):
            return .generationFailed(reason)
        case .modelNotFound(let modelId):
            return .modelNotFound(modelId)
        }
    }
}
