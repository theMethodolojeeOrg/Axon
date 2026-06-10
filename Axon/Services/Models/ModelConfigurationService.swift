//
//  ModelConfigurationService.swift
//  Axon
//
//  Service for managing AI model configurations with bundle fallback,
//  active configuration, and draft/approve workflow.
//

import Foundation
import Combine
import os.log

@MainActor
final class ModelConfigurationService: ObservableObject {
    static let shared = ModelConfigurationService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "ModelConfiguration")

    // MARK: - Published State

    /// Current active model catalog
    @Published private(set) var activeCatalog: ModelCatalog?

    /// Draft catalog pending user approval (nil if no draft exists)
    @Published private(set) var draftCatalog: ModelCatalog?

    /// Whether a draft is available for review
    @Published private(set) var hasPendingDraft: Bool = false

    /// Last sync date
    @Published private(set) var lastSyncDate: Date?

    /// Loading/syncing state
    @Published private(set) var isSyncing: Bool = false

    /// Any validation issues with current draft
    @Published private(set) var draftIssues: [ConfigurationIssue] = []

    // MARK: - File Paths

    private var applicationSupportURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Axon", isDirectory: true)
    }

    private var activeConfigURL: URL? {
        applicationSupportURL?.appendingPathComponent("models-active.json")
    }

    private var draftConfigURL: URL? {
        applicationSupportURL?.appendingPathComponent("models-draft.json")
    }

    private var backupConfigURL: URL? {
        applicationSupportURL?.appendingPathComponent("models-backup.json")
    }

    private var bundledConfigURL: URL? {
        Bundle.main.url(forResource: "default-models", withExtension: "json")
    }

    // MARK: - Initialization

    private init() {
        ensureDirectoryExists()
        loadConfiguration()
    }

    private func ensureDirectoryExists() {
        guard let dir = applicationSupportURL else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Loading

    /// Load configuration with fallback chain: active -> bundled.
    /// If active config is missing, seed it from bundled defaults.
    func loadConfiguration() {
        logger.info("Loading ProviderKit model configuration...")
        let catalog = ProviderKitModelCatalogAdapter.catalogSnapshot()
        activeCatalog = catalog
        draftCatalog = nil
        hasPendingDraft = false
        draftIssues = []
        logger.info("Loaded ProviderKit configuration v\(catalog.version) with \(catalog.providers.count) providers")

        // Load last sync date
        if let dateString = UserDefaults.standard.string(forKey: "ModelConfiguration.lastSyncDate"),
           let date = ISO8601DateFormatter().date(from: dateString) {
            lastSyncDate = date
        }
    }

    private func loadCatalog(from url: URL) -> ModelCatalog? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(ModelCatalog.self, from: data)
        } catch {
            logger.error("Failed to load catalog from \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Draft Management

    /// Save a new draft configuration (from Perplexity sync or manual edit)
    func saveDraft(_ catalog: ModelCatalog) throws {
        _ = catalog
        throw ConfigurationError.providerKitCatalogIsReadOnly
    }

    /// Approve and activate the current draft
    func activateDraft() throws {
        throw ConfigurationError.providerKitCatalogIsReadOnly
    }

    /// Discard the current draft
    func discardDraft() {
        guard let draftURL = draftConfigURL else { return }

        try? FileManager.default.removeItem(at: draftURL)
        draftCatalog = nil
        hasPendingDraft = false
        draftIssues = []

        logger.info("Discarded draft configuration")
    }

    /// Rollback to the previous backup
    func rollbackToBackup() throws {
        throw ConfigurationError.providerKitCatalogIsReadOnly
    }

    /// Reset to bundled defaults
    func resetToDefaults() throws {
        let catalog = ProviderKitModelCatalogAdapter.catalogSnapshot()
        activeCatalog = catalog
        NotificationCenter.default.post(name: .modelConfigurationDidChange, object: nil)

        logger.info("Reloaded ProviderKit defaults v\(catalog.version)")
    }

    // MARK: - Query Methods

    /// Get all models for a specific provider
    func models(for provider: AIProvider) -> [AIModel] {
        ProviderKitModelCatalogAdapter.models(for: provider)
    }

    /// Get all available models across all providers
    func allModels() -> [AIModel] {
        ProviderKitModelCatalogAdapter.allModels()
    }

    /// Get pricing for a specific model ID
    func pricing(for modelId: String) -> ModelPricing? {
        ProviderKitModelCatalogAdapter.pricing(for: modelId)
    }

    /// Get model configuration by ID
    func modelConfig(for modelId: String) -> ModelConfig? {
        ProviderKitModelCatalogAdapter.modelConfig(for: modelId)
    }

    /// Get provider for a model ID
    func provider(for modelId: String) -> AIProvider? {
        ProviderKitModelCatalogAdapter.provider(for: modelId)
    }

    // MARK: - Sync State

    func updateLastSyncDate(_ date: Date = Date()) {
        lastSyncDate = date
        let formatter = ISO8601DateFormatter()
        UserDefaults.standard.set(formatter.string(from: date), forKey: "ModelConfiguration.lastSyncDate")
    }

    func setSyncing(_ syncing: Bool) {
        isSyncing = syncing
    }
}

// MARK: - Errors

enum ConfigurationError: LocalizedError {
    case fileSystemError(String)
    case invalidConfiguration(String)
    case validationFailed([ConfigurationIssue])
    case noDraftAvailable
    case noBackupAvailable
    case syncFailed(String)
    case providerKitCatalogIsReadOnly

    var errorDescription: String? {
        switch self {
        case .fileSystemError(let message):
            return "File system error: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .validationFailed(let issues):
            return "Validation failed: \(issues.map { $0.description }.joined(separator: ", "))"
        case .noDraftAvailable:
            return "No draft configuration available"
        case .noBackupAvailable:
            return "No backup configuration available"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        case .providerKitCatalogIsReadOnly:
            return "Built-in model configuration is provided by AxonProviderKit and cannot be edited from Axon."
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let modelConfigurationDidChange = Notification.Name("ModelConfigurationDidChange")
}
