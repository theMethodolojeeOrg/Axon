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

#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
#endif

/// Error types for MLX model operations
enum MLXModelError: LocalizedError {
    case modelNotFound(String)
    case loadFailed(String)
    case generationFailed(String)
    case notAvailable
    case simulatorNotSupported
    case downloadFailed(String)

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
        }
    }
}

/// Available local MLX models
/// Note: Gemma 3n uses MatFormer architecture with array-based intermediate_size
/// which MLX Swift doesn't support yet - using SmolLM2 as default instead
enum LocalMLXModel: String, CaseIterable {
    case smolLM = "mlx-community/SmolLM2-1.7B-Instruct-4bit"
    case qwen3 = "mlx-community/Qwen3-1.7B-4bit"
    case phi4Mini = "mlx-community/Phi-4-mini-instruct-4bit"
    case llama32 = "mlx-community/Llama-3.2-1B-Instruct-4bit"

    /// The recommended default model for on-device inference
    static var defaultModel: LocalMLXModel { .smolLM }

    var displayName: String {
        switch self {
        case .smolLM: return "SmolLM2 1.7B"
        case .qwen3: return "Qwen3 1.7B"
        case .phi4Mini: return "Phi-4 Mini"
        case .llama32: return "Llama 3.2 1B"
        }
    }

    var description: String {
        switch self {
        case .smolLM: return "HuggingFace's efficient small model. ~1GB download."
        case .qwen3: return "Alibaba's multilingual model. ~1GB download."
        case .phi4Mini: return "Microsoft's capable small model. ~2GB download."
        case .llama32: return "Meta's compact model. ~0.7GB download."
        }
    }
}

/// Service for managing local MLX model inference
@MainActor
final class MLXModelService: ObservableObject {
    static let shared = MLXModelService()

    #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
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
        // Scan for already downloaded models
        updateDownloadedModels()
        // Set up memory management for iOS
        #if canImport(MLX)
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
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        // The model container manages its own cache
        #endif
    }

    /// Unload the model completely to free memory
    func unloadModel() {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        modelContainer = nil
        currentModelId = nil
        modelInMemory = nil
        print("[MLXModelService] Model unloaded")
        #endif
    }

    /// Check if model is currently loaded
    var isModelLoaded: Bool {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        return modelContainer != nil
        #else
        return false
        #endif
    }
    
    // MARK: - Model Management
    
    /// Update the list of downloaded models by scanning the cache directory
    func updateDownloadedModels() {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        Task { @MainActor in
            var downloaded = Set<String>()
            
            // Check each model to see if it's downloaded
            for model in LocalMLXModel.allCases {
                if isModelDownloaded(modelId: model.rawValue) {
                    downloaded.insert(model.rawValue)
                }
            }
            
            self.downloadedModels = downloaded
            print("[MLXModelService] Found \(downloaded.count) downloaded models")
        }
        #endif
    }
    
    /// Check if a model is downloaded locally
    func isModelDownloaded(modelId: String) -> Bool {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        // MLX models are cached in ~/Library/Caches/models/
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("models")
        
        guard let cacheDir = cacheDir else { return false }
        
        // Model directory uses the full model ID path (e.g., "mlx-community/SmolLM2-1.7B-Instruct-4bit")
        let modelDir = cacheDir.appendingPathComponent(modelId)
        
        // Check if directory exists and has required files (config.json is essential)
        let configPath = modelDir.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configPath.path) {
            return true
        }
        
        return false
        #else
        return false
        #endif
    }
    
    /// Get the size of a downloaded model in bytes
    func getModelSize(modelId: String) -> Int64? {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("models")
        
        guard let cacheDir = cacheDir else { return nil }
        
        // Model directory uses the full model ID path
        let modelDir = cacheDir.appendingPathComponent(modelId)
        
        guard FileManager.default.fileExists(atPath: modelDir.path) else { return nil }
        
        do {
            let size = try FileManager.default.allocatedSizeOfDirectory(at: modelDir)
            return size
        } catch {
            print("[MLXModelService] Error getting model size: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }
    
    /// Delete a downloaded model to free up space
    func deleteModel(modelId: String) async throws {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        // Unload if this is the current model
        if currentModelId == modelId {
            unloadModel()
        }
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("models")
        
        guard let cacheDir = cacheDir else {
            throw MLXModelError.modelNotFound("Cache directory not found")
        }
        
        // Model directory uses the full model ID path
        let modelDir = cacheDir.appendingPathComponent(modelId)
        
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            throw MLXModelError.modelNotFound("Model directory not found")
        }
        
        try FileManager.default.removeItem(at: modelDir)
        
        await MainActor.run {
            downloadedModels.remove(modelId)
        }
        
        print("[MLXModelService] Deleted model: \(modelId)")
        #else
        throw MLXModelError.notAvailable
        #endif
    }
    
    /// Get total size of all downloaded models
    func getTotalModelsSize() -> Int64 {
        var totalSize: Int64 = 0
        for modelId in downloadedModels {
            if let size = getModelSize(modelId: modelId) {
                totalSize += size
            }
        }
        return totalSize
    }

    // MARK: - Model Loading

    /// Load a model from HuggingFace (downloads on first use, cached after)
    /// - Parameter modelId: HuggingFace model ID (e.g., "mlx-community/SmolLM2-1.7B-Instruct-4bit")
    func loadModel(modelId: String = LocalMLXModel.defaultModel.rawValue) async throws {
        #if targetEnvironment(simulator)
        throw MLXModelError.simulatorNotSupported
        #endif

        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        // Already loaded this model
        if modelContainer != nil && currentModelId == modelId {
            print("[MLXModelService] Model already loaded: \(modelId)")
            return
        }

        // Unload previous model if different
        if currentModelId != nil && currentModelId != modelId {
            unloadModel()
        }

        // Prevent concurrent loading
        guard !isLoading else {
            print("[MLXModelService] Already loading a model")
            return
        }

        isLoading = true
        downloadProgress = 0
        loadingStatus = "Preparing to download model..."
        downloadingModel = modelId

        defer {
            isLoading = false
            downloadingModel = nil
        }

        print("[MLXModelService] Loading model: \(modelId)")

        do {
            // Create model configuration from HuggingFace ID
            let configuration = ModelConfiguration(id: modelId)

            loadingStatus = "Downloading model from HuggingFace..."

            // Load the model container (downloads if not cached)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                    if progress.fractionCompleted < 1.0 {
                        self?.loadingStatus = "Downloading: \(Int(progress.fractionCompleted * 100))%"
                    } else {
                        self?.loadingStatus = "Loading model into memory..."
                    }
                }
                print("[MLXModelService] Download progress: \(Int(progress.fractionCompleted * 100))%")
            }

            self.modelContainer = container
            self.currentModelId = modelId
            self.modelInMemory = modelId
            loadingStatus = "Model ready!"
            
            // Update downloaded models list
            await MainActor.run {
                downloadedModels.insert(modelId)
            }
            
            print("[MLXModelService] Model loaded successfully: \(modelId)")

            // Log model info
            let numParams = await container.perform { context in
                context.model.numParameters()
            }
            print("[MLXModelService] Model parameters: \(numParams / 1_000_000)M")

        } catch {
            loadingStatus = "Failed to load model"
            print("[MLXModelService] Load error: \(error)")
            throw MLXModelError.loadFailed(error.localizedDescription)
        }
        #else
        throw MLXModelError.notAvailable
        #endif
    }

    // MARK: - Text Generation

    /// Generate a response using the loaded model
    func generate(
        systemPrompt: String?,
        messages: [Message],
        maxTokens: Int = 2048
    ) async throws -> String {
        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        // Verify model is loaded (orchestrator should have already loaded it)
        guard let container = modelContainer else {
            throw MLXModelError.loadFailed("No model loaded. Please load a model first using loadModel(modelId:)")
        }

        // Convert messages to the format expected by MLX
        let chatMessages = buildChatMessages(systemPrompt: systemPrompt, messages: messages)

        print("[MLXModelService] Generating with \(chatMessages.count) messages")

        // Perform generation within the model container context
        let response = try await container.perform { context in
            // Prepare input using UserInput with chat messages
            let userInput = UserInput(messages: chatMessages)
            let input = try await context.processor.prepare(input: userInput)

            // Configure generation parameters
            let parameters = GenerateParameters(
                temperature: 0.7,
                topP: 0.9
            )

            // Generate with token callback
            var output = ""
            _ = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            ) { tokens in
                // Decode tokens as they come in
                let text = context.tokenizer.decode(tokens: tokens)
                output = text
                // Stop if we've generated enough tokens
                return tokens.count < maxTokens ? .more : .stop
            }

            return output
        }

        // Clean up the response
        let cleanedResponse = cleanResponse(response)

        print("[MLXModelService] Generated \(cleanedResponse.count) characters")
        return cleanedResponse
        #else
        throw MLXModelError.notAvailable
        #endif
    }

    // MARK: - Message Formatting

    #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
    /// Convert Axon messages to MLX UserInput.Message format
    private func buildChatMessages(systemPrompt: String?, messages: [Message]) -> [[String: String]] {
        var chatMessages: [[String: String]] = []

        // Add system message if provided
        if let system = systemPrompt, !system.isEmpty {
            chatMessages.append(["role": "system", "content": system])
        }

        // Convert conversation messages
        for message in messages where message.role != .system {
            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .assistant:
                role = "assistant"
            case .system:
                continue
            }

            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                chatMessages.append(["role": role, "content": content])
            }
        }

        return chatMessages
    }
    #endif

    /// Clean up the generated response
    private func cleanResponse(_ response: String) -> String {
        var cleaned = response

        // Remove common special tokens
        let tokensToRemove = [
            "<end_of_turn>", "<start_of_turn>", "<eos>", "<bos>",
            "<|end|>", "<|assistant|>", "<|user|>", "<|system|>",
            "</s>", "<s>"
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
