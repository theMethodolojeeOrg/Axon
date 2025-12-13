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

    /// Load configuration with fallback chain: active -> bundled
    func loadConfiguration() {
        logger.info("Loading model configuration...")

        // Try to load active configuration
        if let activeURL = activeConfigURL,
           let catalog = loadCatalog(from: activeURL) {
            activeCatalog = catalog
            logger.info("Loaded active configuration v\(catalog.version) with \(catalog.providers.count) providers")
        }
        // Fall back to bundled configuration
        else if let bundledURL = bundledConfigURL,
                let catalog = loadCatalog(from: bundledURL) {
            activeCatalog = catalog
            logger.info("Loaded bundled configuration v\(catalog.version) with \(catalog.providers.count) providers")
        } else {
            logger.error("Failed to load any model configuration!")
        }

        // Check for pending draft
        if let draftURL = draftConfigURL,
           let catalog = loadCatalog(from: draftURL) {
            draftCatalog = catalog
            hasPendingDraft = true
            draftIssues = catalog.validate()
            logger.info("Found pending draft configuration v\(catalog.version)")
        }

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
        guard let draftURL = draftConfigURL else {
            throw ConfigurationError.fileSystemError("Cannot determine draft file path")
        }

        // Validate before saving
        let issues = catalog.validate()
        if issues.contains(where: { issue in
            if case .parseError = issue { return true }
            return false
        }) {
            throw ConfigurationError.validationFailed(issues)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(catalog)
        try data.write(to: draftURL, options: .atomic)

        draftCatalog = catalog
        hasPendingDraft = true
        draftIssues = issues

        logger.info("Saved draft configuration v\(catalog.version)")
    }

    /// Approve and activate the current draft
    func activateDraft() throws {
        guard let draft = draftCatalog,
              let draftURL = draftConfigURL,
              let activeURL = activeConfigURL else {
            throw ConfigurationError.noDraftAvailable
        }

        // Check for blocking issues
        let blockingIssues = draftIssues.filter { issue in
            switch issue {
            case .parseError, .invalidPricing, .invalidContextWindow:
                return true
            default:
                return false
            }
        }
        if !blockingIssues.isEmpty {
            throw ConfigurationError.validationFailed(blockingIssues)
        }

        // Backup current active configuration
        if let currentActive = activeCatalog,
           let backupURL = backupConfigURL {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(currentActive) {
                try? data.write(to: backupURL, options: .atomic)
                logger.info("Backed up previous active configuration")
            }
        }

        // Move draft to active
        try? FileManager.default.removeItem(at: activeURL)
        try FileManager.default.copyItem(at: draftURL, to: activeURL)
        try FileManager.default.removeItem(at: draftURL)

        activeCatalog = draft
        draftCatalog = nil
        hasPendingDraft = false
        draftIssues = []

        // Notify observers that configuration changed
        NotificationCenter.default.post(name: .modelConfigurationDidChange, object: nil)

        logger.info("Activated draft configuration v\(draft.version)")
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
        guard let backupURL = backupConfigURL,
              let activeURL = activeConfigURL,
              FileManager.default.fileExists(atPath: backupURL.path) else {
            throw ConfigurationError.noBackupAvailable
        }

        guard let catalog = loadCatalog(from: backupURL) else {
            throw ConfigurationError.invalidConfiguration("Backup file is corrupted")
        }

        try? FileManager.default.removeItem(at: activeURL)
        try FileManager.default.copyItem(at: backupURL, to: activeURL)

        activeCatalog = catalog
        NotificationCenter.default.post(name: .modelConfigurationDidChange, object: nil)

        logger.info("Rolled back to backup configuration v\(catalog.version)")
    }

    /// Reset to bundled defaults
    func resetToDefaults() throws {
        guard let bundledURL = bundledConfigURL,
              let activeURL = activeConfigURL else {
            throw ConfigurationError.fileSystemError("Cannot access bundled configuration")
        }

        guard let catalog = loadCatalog(from: bundledURL) else {
            throw ConfigurationError.invalidConfiguration("Bundled configuration is invalid")
        }

        // Backup current before reset
        if let currentActive = activeCatalog,
           let backupURL = backupConfigURL {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(currentActive) {
                try? data.write(to: backupURL, options: .atomic)
            }
        }

        try? FileManager.default.removeItem(at: activeURL)
        try FileManager.default.copyItem(at: bundledURL, to: activeURL)

        activeCatalog = catalog
        NotificationCenter.default.post(name: .modelConfigurationDidChange, object: nil)

        logger.info("Reset to bundled defaults v\(catalog.version)")
    }

    // MARK: - Query Methods

    /// Get all models for a specific provider
    func models(for provider: AIProvider) -> [AIModel] {
        guard let catalog = activeCatalog else { return [] }
        guard let providerConfig = catalog.providers.first(where: { $0.id == provider.rawValue }) else {
            return []
        }
        return providerConfig.models.map { $0.toAIModel(provider: provider) }
    }

    /// Get all available models across all providers
    func allModels() -> [AIModel] {
        guard let catalog = activeCatalog else { return [] }
        return catalog.providers.flatMap { providerConfig -> [AIModel] in
            guard let provider = providerConfig.aiProvider else { return [] }
            return providerConfig.models.map { $0.toAIModel(provider: provider) }
        }
    }

    /// Get pricing for a specific model ID
    func pricing(for modelId: String) -> ModelPricing? {
        guard let catalog = activeCatalog else { return nil }
        for provider in catalog.providers {
            if let model = provider.models.first(where: { $0.id == modelId }) {
                return model.pricing.toModelPricing()
            }
        }
        return nil
    }

    /// Get model configuration by ID
    func modelConfig(for modelId: String) -> ModelConfig? {
        guard let catalog = activeCatalog else { return nil }
        for provider in catalog.providers {
            if let model = provider.models.first(where: { $0.id == modelId }) {
                return model
            }
        }
        return nil
    }

    /// Get provider for a model ID
    func provider(for modelId: String) -> AIProvider? {
        guard let catalog = activeCatalog else { return nil }
        for provider in catalog.providers {
            if provider.models.contains(where: { $0.id == modelId }) {
                return provider.aiProvider
            }
        }
        return nil
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
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let modelConfigurationDidChange = Notification.Name("ModelConfigurationDidChange")
}
