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

// MLX packages temporarily disabled due to swift-transformers version conflict
// between f5-tts-swift (requires 0.x) and mlx-swift-lm (requires 1.x)
// Uncomment when dependency conflict is resolved:
// #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
// import MLX
// import MLXLLM
// import MLXLMCommon
// import Tokenizers
// #endif

// Stub flag - set to false until packages are re-added
private let mlxPackagesAvailable = false

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

    // MLX packages temporarily disabled - uncomment when re-added:
    // #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
    // /// Cached model container to avoid reloading
    // private var modelContainer: ModelContainer?
    // private var currentModelId: String?
    // #endif

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
        // Note: MLX requires physical device - simulator has no Metal GPU support
        // MLX packages temporarily disabled - uncomment when re-added:
        // #if canImport(MLX) && !targetEnvironment(simulator)
        // // Limit Metal buffer cache to 20MB to help with memory pressure
        // MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        // #endif

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
        // MLX packages temporarily disabled
        // The model container manages its own cache
    }

    /// Unload the model completely to free memory
    func unloadModel() {
        // MLX packages temporarily disabled
        modelInMemory = nil
        print("[MLXModelService] Model unloaded (MLX disabled)")
    }

    /// Check if model is currently loaded
    var isModelLoaded: Bool {
        // MLX packages temporarily disabled
        return false
    }
    
    // MARK: - Model Management
    
    /// Update the list of downloaded models by scanning the cache directory
    func updateDownloadedModels() {
        // MLX packages temporarily disabled
        print("[MLXModelService] MLX packages disabled - skipping model scan")
    }

    /// Check if a model is downloaded locally
    func isModelDownloaded(modelId: String) -> Bool {
        // MLX packages temporarily disabled
        return false
    }

    /// Get the size of a downloaded model in bytes
    func getModelSize(modelId: String) -> Int64? {
        // MLX packages temporarily disabled
        return nil
    }

    /// Delete a downloaded model to free up space
    func deleteModel(modelId: String) async throws {
        // MLX packages temporarily disabled
        throw MLXModelError.notAvailable
    }

    /// Get total size of all downloaded models
    func getTotalModelsSize() -> Int64 {
        // MLX packages temporarily disabled
        return 0
    }

    // MARK: - Model Loading

    /// Load a model from HuggingFace (downloads on first use, cached after)
    /// - Parameter modelId: HuggingFace model ID (e.g., "mlx-community/SmolLM2-1.7B-Instruct-4bit")
    func loadModel(modelId: String = LocalMLXModel.defaultModel.rawValue) async throws {
        // MLX packages temporarily disabled
        throw MLXModelError.notAvailable
    }

    // MARK: - Text Generation

    /// Generate a response using the loaded model
    func generate(
        systemPrompt: String?,
        messages: [Message],
        maxTokens: Int = 2048
    ) async throws -> String {
        // MLX packages temporarily disabled
        throw MLXModelError.notAvailable
    }

    // MARK: - Message Formatting

    // MLX packages temporarily disabled - buildChatMessages commented out
    // Uncomment when packages are re-added

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
