//
//  HuggingFaceMLXBrowserService.swift
//  Axon
//
//  Service for browsing and downloading MLX models from Hugging Face.
//  Restricted to mlx-community repos for compatibility.
//

import Foundation
import HuggingFace

// MARK: - Model Info Types

/// Basic model info from Hugging Face search results
struct HFModelInfo: Identifiable, Sendable, Equatable {
    let id: String              // "mlx-community/Qwen3-1.7B-4bit"
    let author: String          // "mlx-community"
    let name: String            // "Qwen3-1.7B-4bit"
    let downloads: Int?
    let likes: Int?
    let lastModified: Date?
    let tags: [String]
    let isVisionModel: Bool     // contains "vision" in tags or name

    init(from model: Model) {
        self.id = model.id.rawValue
        self.author = model.author ?? model.id.namespace
        self.name = model.id.name
        self.downloads = model.downloads
        self.likes = model.likes
        self.lastModified = model.lastModified
        self.tags = model.tags ?? []
        self.isVisionModel = (model.tags ?? []).contains { $0.lowercased().contains("vision") }
                          || model.id.name.lowercased().contains("vl")
                          || model.id.name.lowercased().contains("vision")
    }

    /// Time since last modified as a human-readable string
    var lastModifiedString: String {
        guard let date = lastModified else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Downloads as a formatted string (e.g., "70.01k")
    var downloadsString: String {
        guard let downloads = downloads else { return "" }
        if downloads >= 1_000_000 {
            return String(format: "%.2fM", Double(downloads) / 1_000_000)
        } else if downloads >= 1_000 {
            return String(format: "%.2fk", Double(downloads) / 1_000)
        }
        return "\(downloads)"
    }
}

/// Detailed model info with parsed model card data
struct HFModelDetailedInfo: Sendable {
    let basic: HFModelInfo
    let contextLength: Int?      // from cardData or config.json
    let license: String?         // from cardData
    let quantization: String?    // "4bit", "8bit" parsed from name
    let parameterCount: String?  // "1.7B", "2B" from name/cardData
    let description: String?     // from model card
    let files: [String]          // list of files in repo

    init(from model: Model, files: [String] = []) {
        self.basic = HFModelInfo(from: model)
        self.files = files

        // Parse quantization from model name
        let nameLower = model.id.name.lowercased()
        if nameLower.contains("4bit") || nameLower.contains("4-bit") {
            self.quantization = "4-bit"
        } else if nameLower.contains("8bit") || nameLower.contains("8-bit") {
            self.quantization = "8-bit"
        } else if nameLower.contains("fp16") {
            self.quantization = "FP16"
        } else {
            self.quantization = nil
        }

        // Parse parameter count from model name
        let paramPattern = #"(\d+(?:\.\d+)?)[bB]"#
        if let range = nameLower.range(of: paramPattern, options: .regularExpression) {
            let match = String(nameLower[range]).uppercased()
            self.parameterCount = match
        } else {
            self.parameterCount = nil
        }

        // Parse from cardData if available
        if let cardData = model.cardData {
            // Try to get license
            if case .string(let licenseStr) = cardData["license"] {
                self.license = licenseStr
            } else {
                self.license = nil
            }

            // Try to get context length
            if case .int(let ctx) = cardData["max_position_embeddings"] {
                self.contextLength = ctx
            } else if case .int(let ctx) = cardData["context_length"] {
                self.contextLength = ctx
            } else {
                self.contextLength = nil
            }

            // Try to get description
            if case .string(let desc) = cardData["description"] {
                self.description = desc
            } else {
                self.description = nil
            }
        } else {
            self.license = nil
            self.contextLength = nil
            self.description = nil
        }
    }

    /// Estimated download size based on files
    var estimatedSize: String? {
        // Look for safetensors files to estimate size
        // This is a rough estimate - actual size varies
        guard let paramCount = parameterCount else { return nil }
        let params = paramCount.replacingOccurrences(of: "B", with: "")
        guard let paramNum = Double(params) else { return nil }

        // Rough estimates based on quantization
        let bytesPerParam: Double
        switch quantization {
        case "4-bit": bytesPerParam = 0.5
        case "8-bit": bytesPerParam = 1.0
        case "FP16": bytesPerParam = 2.0
        default: bytesPerParam = 0.5 // Assume 4-bit
        }

        let sizeGB = paramNum * bytesPerParam
        if sizeGB >= 1.0 {
            return String(format: "~%.1f GB", sizeGB)
        } else {
            return String(format: "~%.0f MB", sizeGB * 1024)
        }
    }
}

// MARK: - Browser Service

/// Service for browsing and downloading MLX models from Hugging Face
@MainActor
final class HuggingFaceMLXBrowserService: ObservableObject {
    static let shared = HuggingFaceMLXBrowserService()

    private let hubClient = HubClient.default

    // MARK: - Published State

    @Published var searchResults: [HFModelInfo] = []
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var downloadProgress: [String: Double] = [:]  // repoId -> progress (0-1)
    @Published var downloadingModels: Set<String> = []

    // MARK: - Search

    /// Search for MLX models on Hugging Face
    /// Restricted to mlx-community author for compatibility
    func searchModels(query: String) async {
        isSearching = true
        searchError = nil

        do {
            let response = try await hubClient.listModels(
                search: query.isEmpty ? nil : query,
                author: "mlx-community",  // Restrict to mlx-community
                sort: "downloads",
                direction: .descending,
                limit: 50,
                full: true
            )
            searchResults = response.items.map { HFModelInfo(from: $0) }
        } catch {
            searchError = error.localizedDescription
            searchResults = []
        }

        isSearching = false
    }

    /// Get popular MLX models (no search query)
    func loadPopularModels() async {
        await searchModels(query: "")
    }

    // MARK: - Model Details

    /// Get detailed info for a specific model
    func getModelDetails(repoId: String) async throws -> HFModelDetailedInfo {
        guard let id = Repo.ID(rawValue: repoId) else {
            throw HFBrowserError.invalidRepoId(repoId)
        }

        let model = try await hubClient.getModel(id, full: true)
        let files = try await hubClient.listFiles(in: id)
        let fileNames = files.map { $0.path }

        return HFModelDetailedInfo(from: model, files: fileNames)
    }

    // MARK: - Download

    /// Download a model from Hugging Face
    func downloadModel(repoId: String) async throws {
        guard let id = Repo.ID(rawValue: repoId) else {
            throw HFBrowserError.invalidRepoId(repoId)
        }

        downloadingModels.insert(repoId)
        downloadProgress[repoId] = 0

        defer {
            downloadingModels.remove(repoId)
        }

        let destination = modelStorageURL(for: id)

        // Create directory if needed
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        // Download all model files (safetensors, config, tokenizer)
        _ = try await hubClient.downloadSnapshot(
            of: id,
            to: destination,
            matching: ["*.safetensors", "*.json", "tokenizer.*", "*.txt"]
        ) { [weak self] progress in
            Task { @MainActor in
                let ratio = Double(progress.completedUnitCount) / Double(max(1, progress.totalUnitCount))
                self?.downloadProgress[repoId] = ratio
            }
        }

        downloadProgress[repoId] = 1.0
    }

    /// Check if a model is currently downloading
    func isDownloading(_ repoId: String) -> Bool {
        downloadingModels.contains(repoId)
    }

    /// Get download progress for a model (0-1)
    func progress(for repoId: String) -> Double {
        downloadProgress[repoId] ?? 0
    }

    // MARK: - Storage

    /// Storage location for downloaded models
    func modelStorageURL(for repoId: Repo.ID) -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL
            .appendingPathComponent("MLXModels", isDirectory: true)
            .appendingPathComponent(repoId.namespace, isDirectory: true)
            .appendingPathComponent(repoId.name, isDirectory: true)
    }

    /// Storage location for downloaded models (string version)
    func modelStorageURL(for repoIdString: String) -> URL? {
        guard let repoId = Repo.ID(rawValue: repoIdString) else { return nil }
        return modelStorageURL(for: repoId)
    }

    /// Check if a model is downloaded
    func isModelDownloaded(_ repoId: String) -> Bool {
        guard let url = modelStorageURL(for: repoId) else { return false }
        // Check if directory exists and contains safetensors files
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return contents.contains { $0.hasSuffix(".safetensors") }
        } catch {
            return false
        }
    }

    /// Get the size of a downloaded model
    func getModelSize(_ repoId: String) -> Int64? {
        guard let url = modelStorageURL(for: repoId) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            return try FileManager.default.allocatedSizeOfDirectory(at: url)
        } catch {
            return nil
        }
    }

    /// Delete a downloaded model
    func deleteModel(_ repoId: String) async throws {
        guard let url = modelStorageURL(for: repoId) else {
            throw HFBrowserError.invalidRepoId(repoId)
        }

        try FileManager.default.removeItem(at: url)
    }

    /// Get all downloaded models
    func getDownloadedModels() -> [String] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mlxModelsURL = documentsURL.appendingPathComponent("MLXModels", isDirectory: true)

        guard FileManager.default.fileExists(atPath: mlxModelsURL.path) else { return [] }

        var downloadedModels: [String] = []

        do {
            let namespaces = try FileManager.default.contentsOfDirectory(atPath: mlxModelsURL.path)
            for namespace in namespaces {
                let namespaceURL = mlxModelsURL.appendingPathComponent(namespace, isDirectory: true)
                let models = try FileManager.default.contentsOfDirectory(atPath: namespaceURL.path)
                for model in models {
                    let repoId = "\(namespace)/\(model)"
                    if isModelDownloaded(repoId) {
                        downloadedModels.append(repoId)
                    }
                }
            }
        } catch {
            // Ignore errors, return empty
        }

        return downloadedModels
    }

    /// Get total size of all downloaded models
    func getTotalDownloadedSize() -> Int64 {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mlxModelsURL = documentsURL.appendingPathComponent("MLXModels", isDirectory: true)

        guard FileManager.default.fileExists(atPath: mlxModelsURL.path) else { return 0 }

        do {
            return try FileManager.default.allocatedSizeOfDirectory(at: mlxModelsURL)
        } catch {
            return 0
        }
    }
}

// MARK: - Errors

enum HFBrowserError: LocalizedError {
    case invalidRepoId(String)
    case downloadFailed(String)
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepoId(let id):
            return "Invalid repository ID: \(id). Expected format: 'namespace/name'"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .modelNotFound(let id):
            return "Model not found: \(id)"
        }
    }
}
