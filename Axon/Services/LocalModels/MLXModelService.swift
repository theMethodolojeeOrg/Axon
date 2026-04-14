//
//  MLXModelService.swift
//  Axon
//
//  Service for loading and running local MLX models.
//  Downloads models from HuggingFace on first use, then caches locally.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MLX packages for on-device inference
#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers
private let mlxPackagesAvailable = true
#else
private let mlxPackagesAvailable = false
#endif

/// Error types for MLX model operations
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

/// Available local MLX models
/// The default bundled models (Gemma4 E2B, Qwen3-VL, and Gemma3 270M) are included in the app bundle.
/// Other models are downloaded on demand from Hugging Face.
enum LocalMLXModel: String, CaseIterable {
    // Bundled in app - ready immediately
    case gemma4_E2B = "google/gemma-4-E2B-it-MLX"
    case qwen3VL = "mlx-community/Qwen3-VL-2B-Instruct-4bit"
    case gemma3_270m = "lmstudio-community/gemma-3-270m-it-MLX-8bit"

    // Downloadable models
    case smolLM = "mlx-community/SmolLM2-1.7B-Instruct-4bit"
    case qwen3 = "mlx-community/Qwen3-1.7B-4bit"
    case phi4Mini = "mlx-community/Phi-4-mini-instruct-4bit"
    case llama32 = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    /// The recommended default model - bundled in app
    static var defaultModel: LocalMLXModel { .gemma4_E2B }

    /// Whether this model is bundled in the app (no download required)
    var isBundled: Bool {
        switch self {
        case .gemma4_E2B, .qwen3VL, .gemma3_270m: return true
        default: return false
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
        case .gemma4_E2B: return "Google's Gemma 4 model. Most capable bundled option. Bundled in app - ready instantly."
        case .qwen3VL: return "Vision-language model. Bundled in app - ready instantly."
        case .gemma3_270m: return "Google's ultra-compact model. Fastest option. Bundled in app - ready instantly."
        case .smolLM: return "HuggingFace's efficient small model. ~1GB download."
        case .qwen3: return "Alibaba's multilingual model. ~1GB download."
        case .phi4Mini: return "Microsoft's capable small model. ~2GB download."
        case .llama32: return "Meta's compact model. ~0.7GB download."
        }
    }

    /// Context window size for this model
    var contextWindow: Int {
        switch self {
        case .gemma4_E2B: return 8_192
        case .qwen3VL: return 8_192
        case .gemma3_270m: return 8_192
        case .smolLM: return 8_192
        case .qwen3: return 32_768
        case .phi4Mini: return 16_384
        case .llama32: return 8_192
        }
    }

    /// Modalities supported by this model
    var modalities: [String] {
        switch self {
        case .qwen3VL: return ["text", "vision"]
        default: return ["text"]
        }
    }

    /// Whether this is a vision-language model (requires VLMModelFactory)
    var isVisionModel: Bool {
        modalities.contains("vision")
    }

    /// Convert to AIModel for unified selection
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

// MARK: - Bundled Model Support

/// Helper for locating bundled MLX models in the app bundle
struct BundledMLXModels {
    /// Get the bundle path for a bundled model
    /// - Parameter modelId: The HuggingFace repo ID (e.g., "mlx-community/Qwen3-VL-2B-Instruct-4bit")
    /// - Returns: URL to the bundled model directory, or nil if not bundled
    static func bundledModelPath(for modelId: String) -> URL? {
        // Convert repo ID to directory name (replace / with _)
        let directoryName = modelId.replacingOccurrences(of: "/", with: "_")

        // Check in Resources/MLXModels/
        if let bundlePath = Bundle.main.path(
            forResource: directoryName,
            ofType: nil,
            inDirectory: "MLXModels"
        ) {
            return URL(fileURLWithPath: bundlePath)
        }

        // Also check directly in bundle
        if let bundlePath = Bundle.main.path(forResource: directoryName, ofType: nil) {
            return URL(fileURLWithPath: bundlePath)
        }

        return nil
    }

    /// Check if a model is bundled in the app
    static func isBundled(_ modelId: String) -> Bool {
        bundledModelPath(for: modelId) != nil
    }

    /// Get the default bundled model ID
    static var defaultModelId: String {
        LocalMLXModel.defaultModel.rawValue
    }
}

// MARK: - MLX Model Service

/// Service for managing local MLX model inference
@MainActor
final class MLXModelService: ObservableObject {
    static let shared = MLXModelService()

    #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)
    /// Cached model container to avoid reloading
    private var modelContainer: ModelContainer?
    private var currentModelId: String?
    #endif

    /// Loading state for UI
    @Published var isLoading = false
    @Published var downloadProgress: Double = 0
    @Published var loadingStatus: String = ""

    /// Model management state
    @Published var downloadedModels: Set<String> = []
    @Published var modelInMemory: String? = nil
    @Published var downloadingModel: String? = nil

    private init() {
        // Register custom model types not yet in upstream mlx-swift-examples
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        LLMTypeRegistry.shared.registerModelType("gemma4") { url in
            let config = try JSONDecoder().decode(
                Gemma4TextConfiguration.self, from: Data(contentsOf: url))
            return Gemma4TextModel(config)
        }
        #endif

        // Scan for already downloaded models
        updateDownloadedModels()

        #if canImport(MLX) && !targetEnvironment(simulator)
        // Limit Metal buffer cache to 20MB to help with memory pressure
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        #endif

        #if canImport(UIKit)
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Clear cache when app backgrounds
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        #endif
    }

    @objc private func handleMemoryWarning() {
        print("[MLXModelService] Memory warning - clearing KV cache")
        clearCache()
    }

    @objc private func handleBackground() {
        print("[MLXModelService] App backgrounded - clearing KV cache")
        clearCache()
    }

    /// Clear the KV cache to free memory
    func clearCache() {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)
        // Model container manages its own cache - unload to free memory
        #endif
    }

    /// Unload the model completely to free memory
    func unloadModel() {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)
        modelContainer = nil
        currentModelId = nil
        #endif
        modelInMemory = nil
        print("[MLXModelService] Model unloaded")
    }

    /// Check if model is currently loaded
    var isModelLoaded: Bool {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)
        return modelContainer != nil
        #else
        return false
        #endif
    }

    // MARK: - Model Management

    /// Get the HuggingFace cache directory
    private var hfCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
    }

    /// Get the downloaded models directory (from HuggingFaceMLXBrowserService)
    private var downloadedModelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MLXModels", isDirectory: true)
    }

    /// Update the list of downloaded models by scanning the cache directory
    func updateDownloadedModels() {
        var models = Set<String>()

        // Check bundled models
        for model in LocalMLXModel.allCases where model.isBundled {
            if BundledMLXModels.isBundled(model.rawValue) {
                models.insert(model.rawValue)
            }
        }

        // Check HF cache directory
        let cacheDir = hfCacheDirectory
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: cacheDir.path)
                for dir in contents where dir.hasPrefix("models--mlx-community--") {
                    let modelName = dir
                        .replacingOccurrences(of: "models--", with: "")
                        .replacingOccurrences(of: "--", with: "/")
                    models.insert(modelName)
                }
            } catch {
                print("[MLXModelService] Error scanning cache: \(error)")
            }
        }

        // Check downloaded models directory (from browser)
        let downloadDir = downloadedModelsDirectory
        if FileManager.default.fileExists(atPath: downloadDir.path) {
            do {
                let namespaces = try FileManager.default.contentsOfDirectory(atPath: downloadDir.path)
                for namespace in namespaces {
                    let namespaceURL = downloadDir.appendingPathComponent(namespace)
                    let modelNames = try FileManager.default.contentsOfDirectory(atPath: namespaceURL.path)
                    for modelName in modelNames {
                        let modelPath = namespaceURL.appendingPathComponent(modelName)
                        // Check if it contains safetensors
                        let files = try? FileManager.default.contentsOfDirectory(atPath: modelPath.path)
                        if files?.contains(where: { $0.hasSuffix(".safetensors") }) == true {
                            models.insert("\(namespace)/\(modelName)")
                        }
                    }
                }
            } catch {
                print("[MLXModelService] Error scanning downloads: \(error)")
            }
        }

        downloadedModels = models
        print("[MLXModelService] Found \(models.count) downloaded models")
    }

    /// Check if a model is downloaded locally
    func isModelDownloaded(modelId: String) -> Bool {
        // Check if bundled
        if BundledMLXModels.isBundled(modelId) {
            return true
        }

        // Check downloaded models set
        return downloadedModels.contains(modelId)
    }

    /// Get the local path for a model (bundled, downloaded, or HF cache)
    func getModelPath(modelId: String) -> URL? {
        // 1. Check bundled first
        if let bundledPath = BundledMLXModels.bundledModelPath(for: modelId) {
            return bundledPath
        }

        // 2. Check downloaded models directory
        let components = modelId.split(separator: "/")
        if components.count == 2 {
            let downloadPath = downloadedModelsDirectory
                .appendingPathComponent(String(components[0]))
                .appendingPathComponent(String(components[1]))
            if FileManager.default.fileExists(atPath: downloadPath.path) {
                return downloadPath
            }
        }

        // 3. Check HF cache
        let cacheName = "models--\(modelId.replacingOccurrences(of: "/", with: "--"))"
        let cachePath = hfCacheDirectory.appendingPathComponent(cacheName)
        if FileManager.default.fileExists(atPath: cachePath.path) {
            // Find the snapshot directory
            let snapshotsPath = cachePath.appendingPathComponent("snapshots")
            if let snapshots = try? FileManager.default.contentsOfDirectory(atPath: snapshotsPath.path),
               let firstSnapshot = snapshots.first {
                return snapshotsPath.appendingPathComponent(firstSnapshot)
            }
        }

        return nil
    }

    /// Get the size of a downloaded model in bytes
    func getModelSize(modelId: String) -> Int64? {
        guard let path = getModelPath(modelId: modelId) else { return nil }
        return try? FileManager.default.allocatedSizeOfDirectory(at: path)
    }

    /// Delete a downloaded model to free up space
    func deleteModel(modelId: String) async throws {
        // Don't delete bundled models
        if BundledMLXModels.isBundled(modelId) {
            throw MLXModelError.loadFailed("Cannot delete bundled model")
        }

        // Unload if this model is loaded
        if modelInMemory == modelId {
            unloadModel()
        }

        // Try to delete from downloaded models directory
        let components = modelId.split(separator: "/")
        if components.count == 2 {
            let downloadPath = downloadedModelsDirectory
                .appendingPathComponent(String(components[0]))
                .appendingPathComponent(String(components[1]))
            if FileManager.default.fileExists(atPath: downloadPath.path) {
                try FileManager.default.removeItem(at: downloadPath)
            }
        }

        // Try to delete from HF cache
        let cacheName = "models--\(modelId.replacingOccurrences(of: "/", with: "--"))"
        let cachePath = hfCacheDirectory.appendingPathComponent(cacheName)
        if FileManager.default.fileExists(atPath: cachePath.path) {
            try FileManager.default.removeItem(at: cachePath)
        }

        downloadedModels.remove(modelId)
        print("[MLXModelService] Deleted model: \(modelId)")
    }

    /// Get total size of all downloaded models
    func getTotalModelsSize() -> Int64 {
        var total: Int64 = 0
        for modelId in downloadedModels {
            if let size = getModelSize(modelId: modelId) {
                total += size
            }
        }
        return total
    }

    // MARK: - Model Loading

    /// Load a model from local path or HuggingFace
    /// - Parameter modelId: HuggingFace model ID (e.g., "mlx-community/SmolLM2-1.7B-Instruct-4bit")
    func loadModel(modelId: String = LocalMLXModel.defaultModel.rawValue) async throws {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)

        #if targetEnvironment(simulator)
        throw MLXModelError.simulatorNotSupported
        #endif

        // Skip if already loaded
        if currentModelId == modelId && modelContainer != nil {
            print("[MLXModelService] Model already loaded: \(modelId)")
            return
        }

        isLoading = true
        loadingStatus = "Loading model..."

        do {
            // Unload previous model
            if modelContainer != nil {
                unloadModel()
            }

            // Determine the model configuration
            let config: ModelConfiguration

            if let localPath = getModelPath(modelId: modelId) {
                // Use local path (bundled or downloaded)
                print("[MLXModelService] Loading from local path: \(localPath.path)")
                loadingStatus = "Loading from device..."
                config = ModelConfiguration(directory: localPath)
            } else {
                // Download from HuggingFace
                print("[MLXModelService] Downloading from HuggingFace: \(modelId)")
                loadingStatus = "Downloading model..."
                downloadingModel = modelId
                config = ModelConfiguration(id: modelId)
            }

            // Determine if this is a vision model
            let isVisionModel = Self.isVisionModel(modelId: modelId)

            // Load the model using appropriate factory
            loadingStatus = "Initializing model..."
            let container: ModelContainer

            if isVisionModel {
                print("[MLXModelService] Using VLMModelFactory for vision model")
                container = try await VLMModelFactory.shared.loadContainer(configuration: config) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress.fractionCompleted
                        if progress.fractionCompleted < 1.0 {
                            self.loadingStatus = String(format: "Downloading... %.0f%%", progress.fractionCompleted * 100)
                        }
                    }
                }
            } else {
                print("[MLXModelService] Using LLMModelFactory for text model")
                container = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress.fractionCompleted
                        if progress.fractionCompleted < 1.0 {
                            self.loadingStatus = String(format: "Downloading... %.0f%%", progress.fractionCompleted * 100)
                        }
                    }
                }
            }

            modelContainer = container
            currentModelId = modelId
            modelInMemory = modelId
            downloadingModel = nil

            // Update downloaded models list
            updateDownloadedModels()

            print("[MLXModelService] Model loaded successfully: \(modelId)")

        } catch {
            print("[MLXModelService] Failed to load model: \(error)")
            throw MLXModelError.loadFailed(error.localizedDescription)
        }

        isLoading = false
        loadingStatus = ""
        downloadProgress = 0

        #else
        throw MLXModelError.notAvailable
        #endif
    }

    /// Determine if a model ID is a vision-language model
    private static func isVisionModel(modelId: String) -> Bool {
        // Check known VLM patterns
        let vlmPatterns = ["VL", "vl", "vision", "Vision", "paligemma", "Paligemma", "idefics", "smolvlm"]
        let modelName = modelId.lowercased()

        for pattern in vlmPatterns {
            if modelName.contains(pattern.lowercased()) {
                return true
            }
        }

        // Also check LocalMLXModel enum if it matches
        if let localModel = LocalMLXModel(rawValue: modelId) {
            return localModel.isVisionModel
        }

        return false
    }

    // MARK: - Text Generation

    // MARK: - Generation Config Loading

    /// Cached generation configs per model
    private var generationConfigs: [String: GenerationConfig] = [:]

    /// Generation config loaded from model's generation_config.json
    struct GenerationConfig: Codable {
        var temperature: Double?
        var topP: Double?
        var topK: Int?
        var repetitionPenalty: Double?
        var maxNewTokens: Int?
        var doSample: Bool?

        enum CodingKeys: String, CodingKey {
            case temperature
            case topP = "top_p"
            case topK = "top_k"
            case repetitionPenalty = "repetition_penalty"
            case maxNewTokens = "max_new_tokens"
            case doSample = "do_sample"
        }
    }

    /// Load generation config from model directory
    func loadGenerationConfig(for modelId: String) -> GenerationConfig? {
        // Check cache first
        if let cached = generationConfigs[modelId] {
            return cached
        }

        guard let modelPath = getModelPath(modelId: modelId) else {
            return nil
        }

        let configPath = modelPath.appendingPathComponent("generation_config.json")
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            print("[MLXModelService] No generation_config.json found for \(modelId)")
            return nil
        }

        do {
            let data = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(GenerationConfig.self, from: data)
            generationConfigs[modelId] = config
            print("[MLXModelService] Loaded generation config for \(modelId): temp=\(config.temperature ?? -1), rep_penalty=\(config.repetitionPenalty ?? -1)")
            return config
        } catch {
            print("[MLXModelService] Failed to load generation_config.json: \(error)")
            return nil
        }
    }

    /// Get effective generation parameters for a model, applying overrides in order:
    /// 1. Model's generation_config.json (lowest priority)
    /// 2. User's per-model override (if enabled)
    /// 3. Global settings (if enabled)
    /// 4. Function parameters (highest priority, if explicitly provided)
    func getEffectiveParameters(
        modelId: String,
        settings: AppSettings,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        repetitionPenalty: Double? = nil,
        repetitionContextSize: Int? = nil
    ) -> (maxTokens: Int, temperature: Double, topP: Double, repetitionPenalty: Double, repetitionContextSize: Int) {
        // Start with defaults
        var effectiveMaxTokens = 2048
        var effectiveTemperature = 0.7
        var effectiveTopP = 0.8
        var effectiveRepPenalty = 1.2
        var effectiveRepContext = 64

        // 1. Apply model's generation_config.json
        if let modelConfig = loadGenerationConfig(for: modelId) {
            if let temp = modelConfig.temperature { effectiveTemperature = temp }
            if let topP = modelConfig.topP { effectiveTopP = topP }
            if let repPenalty = modelConfig.repetitionPenalty { effectiveRepPenalty = repPenalty }
            if let maxNew = modelConfig.maxNewTokens { effectiveMaxTokens = maxNew }
        }

        // 2. Apply per-model override (if enabled)
        if let override = settings.modelOverrides[modelId], override.enabled {
            if let temp = override.temperature { effectiveTemperature = temp }
            if let topP = override.topP { effectiveTopP = topP }
            if let repPenalty = override.repetitionPenalty { effectiveRepPenalty = repPenalty }
            if let repContext = override.repetitionContextSize { effectiveRepContext = repContext }
            if let maxTokens = override.maxResponseTokens { effectiveMaxTokens = maxTokens }
        }

        // 3. Apply global settings (if enabled and no per-model override)
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

        // 4. Apply explicit function parameters (highest priority)
        if let maxTokens = maxTokens { effectiveMaxTokens = maxTokens }
        if let temperature = temperature { effectiveTemperature = temperature }
        if let topP = topP { effectiveTopP = topP }
        if let repetitionPenalty = repetitionPenalty { effectiveRepPenalty = repetitionPenalty }
        if let repetitionContextSize = repetitionContextSize { effectiveRepContext = repetitionContextSize }

        return (effectiveMaxTokens, effectiveTemperature, effectiveTopP, effectiveRepPenalty, effectiveRepContext)
    }

    // MARK: - Text Generation

    /// Generate a response using the loaded model
    /// - Parameters:
    ///   - systemPrompt: Optional system prompt
    ///   - messages: Conversation messages
    ///   - maxTokens: Maximum tokens to generate (nil = use effective default)
    ///   - temperature: Sampling temperature (nil = use effective default)
    ///   - topP: Nucleus sampling threshold (nil = use effective default)
    ///   - repetitionPenalty: Penalty for repeated tokens (nil = use effective default)
    ///   - repetitionContextSize: Number of tokens to look back (nil = use effective default)
    ///   - settings: App settings for applying overrides (nil = use defaults only)
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
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)

        guard let container = modelContainer, let modelId = currentModelId else {
            throw MLXModelError.notLoaded
        }

        // Get effective parameters (applies model config, overrides, and global settings)
        let effectiveParams: (maxTokens: Int, temperature: Double, topP: Double, repetitionPenalty: Double, repetitionContextSize: Int)
        if let settings = settings {
            effectiveParams = getEffectiveParameters(
                modelId: modelId,
                settings: settings,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty,
                repetitionContextSize: repetitionContextSize
            )
        } else {
            // Use defaults with any explicit overrides
            effectiveParams = (
                maxTokens: maxTokens ?? 2048,
                temperature: temperature ?? 0.7,
                topP: topP ?? 0.8,
                repetitionPenalty: repetitionPenalty ?? 1.2,
                repetitionContextSize: repetitionContextSize ?? 64
            )
        }

        print("[MLXModelService] Generating with params: maxTokens=\(effectiveParams.maxTokens), temp=\(effectiveParams.temperature), topP=\(effectiveParams.topP), repPenalty=\(effectiveParams.repetitionPenalty), repContext=\(effectiveParams.repetitionContextSize)")

        // Build chat messages for UserInput
        let chatMessages = buildChatMessages(systemPrompt: systemPrompt, messages: messages)

        // Create UserInput with chat messages
        let userInput = UserInput(chat: chatMessages)

        // Create generation parameters with effective settings
        let generateParams = GenerateParameters(
            maxTokens: effectiveParams.maxTokens,
            temperature: Float(effectiveParams.temperature),
            topP: Float(effectiveParams.topP),
            repetitionPenalty: Float(effectiveParams.repetitionPenalty),
            repetitionContextSize: effectiveParams.repetitionContextSize
        )

        // Generate response
        let result: GenerateResult = try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            return try MLXLMCommon.generate(
                input: input,
                parameters: generateParams,
                context: context
            ) { (tokens: [Int]) -> GenerateDisposition in
                return .more
            }
        }

        // Clean up the response
        let cleaned = cleanResponse(result.output)
        print("[MLXModelService] Generated \(result.tokens.count) tokens")

        return cleaned

        #else
        throw MLXModelError.notAvailable
        #endif
    }

    /// Generate a streaming response
    /// - Parameters:
    ///   - systemPrompt: Optional system prompt
    ///   - messages: Conversation messages
    ///   - maxTokens: Maximum tokens to generate (nil = use effective default)
    ///   - temperature: Sampling temperature (nil = use effective default)
    ///   - topP: Nucleus sampling threshold (nil = use effective default)
    ///   - repetitionPenalty: Penalty for repeated tokens (nil = use effective default)
    ///   - repetitionContextSize: Number of tokens to look back (nil = use effective default)
    ///   - settings: App settings for applying overrides (nil = use defaults only)
    ///   - onToken: Callback for each generated token
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
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)

        guard let container = modelContainer, let modelId = currentModelId else {
            throw MLXModelError.notLoaded
        }

        // Get effective parameters (applies model config, overrides, and global settings)
        let effectiveParams: (maxTokens: Int, temperature: Double, topP: Double, repetitionPenalty: Double, repetitionContextSize: Int)
        if let settings = settings {
            effectiveParams = getEffectiveParameters(
                modelId: modelId,
                settings: settings,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty,
                repetitionContextSize: repetitionContextSize
            )
        } else {
            // Use defaults with any explicit overrides
            effectiveParams = (
                maxTokens: maxTokens ?? 2048,
                temperature: temperature ?? 0.7,
                topP: topP ?? 0.8,
                repetitionPenalty: repetitionPenalty ?? 1.2,
                repetitionContextSize: repetitionContextSize ?? 64
            )
        }

        print("[MLXModelService] Streaming with params: maxTokens=\(effectiveParams.maxTokens), temp=\(effectiveParams.temperature), topP=\(effectiveParams.topP), repPenalty=\(effectiveParams.repetitionPenalty), repContext=\(effectiveParams.repetitionContextSize)")

        // Build chat messages for UserInput
        let chatMessages = buildChatMessages(systemPrompt: systemPrompt, messages: messages)

        // Create UserInput with chat messages
        let userInput = UserInput(chat: chatMessages)

        // Create generation parameters with effective settings
        let generateParams = GenerateParameters(
            maxTokens: effectiveParams.maxTokens,
            temperature: Float(effectiveParams.temperature),
            topP: Float(effectiveParams.topP),
            repetitionPenalty: Float(effectiveParams.repetitionPenalty),
            repetitionContextSize: effectiveParams.repetitionContextSize
        )

        // Use the AsyncStream-based generate API for streaming
        let stream = try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            return try MLXLMCommon.generate(
                input: input,
                parameters: generateParams,
                context: context
            )
        }

        // Process the stream
        for await generation in stream {
            switch generation {
            case .chunk(let text):
                let cleaned = Self.cleanResponseStatic(text)
                if !cleaned.isEmpty {
                    onToken(cleaned)
                }
            case .info(let info):
                print("[MLXModelService] Streaming complete: \(info.generationTokenCount) tokens")
            case .toolCall:
                // Tool calls not handled in basic streaming
                break
            }
        }

        #else
        throw MLXModelError.notAvailable
        #endif
    }

    // MARK: - Message Formatting

    #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXVLM)
    /// Convert app messages to Chat.Message for MLX UserInput
    private func buildChatMessages(systemPrompt: String?, messages: [Message]) -> [Chat.Message] {
        var chatMessages: [Chat.Message] = []

        // Add system prompt if provided
        if let system = systemPrompt, !system.isEmpty {
            chatMessages.append(.system(system))
        }

        // Add conversation messages
        for message in messages {
            if message.role == .user {
                chatMessages.append(.user(message.content))
            } else {
                chatMessages.append(.assistant(message.content))
            }
        }

        return chatMessages
    }
    #endif

    /// Clean up the generated response
    private func cleanResponse(_ response: String) -> String {
        Self.cleanResponseStatic(response)
    }

    /// Static version for use in closures
    private static func cleanResponseStatic(_ response: String) -> String {
        var cleaned = response

        // Remove common special tokens
        let tokensToRemove = [
            "<end_of_turn>", "<start_of_turn>", "<eos>", "<bos>",
            "<|end|>", "<|assistant|>", "<|user|>", "<|system|>",
            "</s>", "<s>", "<|im_end|>", "<|im_start|>",
            "<|endoftext|>", "[/INST]", "[INST]"
        ]

        for token in tokensToRemove {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }

        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
}

// MARK: - FileManager Extension for Directory Size

extension FileManager {
    /// Calculate the allocated size of a directory and its contents
    func allocatedSizeOfDirectory(at url: URL) throws -> Int64 {
        guard let enumerator = self.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                  let size = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize else {
                continue
            }
            totalSize += Int64(size)
        }

        return totalSize
    }
}
