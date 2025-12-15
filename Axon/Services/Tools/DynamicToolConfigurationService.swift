//
//  DynamicToolConfigurationService.swift
//  Axon
//
//  Service for managing dynamic tool configurations with bundle fallback,
//  active configuration, and draft/approve workflow.
//

import Foundation
import Combine
import os.log

@MainActor
final class DynamicToolConfigurationService: ObservableObject {
    static let shared = DynamicToolConfigurationService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "DynamicToolConfig")

    // MARK: - Published State

    /// Current active tool catalog
    @Published private(set) var activeCatalog: DynamicToolCatalog?

    /// Draft catalog pending user approval
    @Published private(set) var draftCatalog: DynamicToolCatalog?

    /// Whether a draft is available for review
    @Published private(set) var hasPendingDraft: Bool = false

    /// Any validation issues with current draft
    @Published private(set) var draftIssues: [DynamicToolIssue] = []

    /// Loading state
    @Published private(set) var isLoading: Bool = false

    // MARK: - File Paths

    private var applicationSupportURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Axon", isDirectory: true)
    }

    private var activeConfigURL: URL? {
        applicationSupportURL?.appendingPathComponent("tools-active.json")
    }

    private var draftConfigURL: URL? {
        applicationSupportURL?.appendingPathComponent("tools-draft.json")
    }

    private var backupConfigURL: URL? {
        applicationSupportURL?.appendingPathComponent("tools-backup.json")
    }

    private var bundledConfigURL: URL? {
        Bundle.main.url(forResource: "default-tools", withExtension: "json")
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
        isLoading = true
        defer { isLoading = false }

        logger.info("Loading dynamic tool configuration...")

        // Try to load active configuration
        if let activeURL = activeConfigURL,
           let catalog = loadCatalog(from: activeURL) {
            activeCatalog = catalog
            logger.info("Loaded active tool configuration v\(catalog.version) with \(catalog.tools.count) tools")
        }
        // Fall back to bundled configuration
        else if let bundledURL = bundledConfigURL,
                let catalog = loadCatalog(from: bundledURL) {
            activeCatalog = catalog
            logger.info("Loaded bundled tool configuration v\(catalog.version) with \(catalog.tools.count) tools")
        } else {
            logger.error("Failed to load any tool configuration!")
        }

        // Check for pending draft
        if let draftURL = draftConfigURL,
           let catalog = loadCatalog(from: draftURL) {
            draftCatalog = catalog
            hasPendingDraft = true
            draftIssues = catalog.validate()
            logger.info("Found pending draft tool configuration v\(catalog.version)")
        }
    }

    private func loadCatalog(from url: URL) -> DynamicToolCatalog? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(DynamicToolCatalog.self, from: data)
        } catch {
            logger.error("Failed to load tool catalog from \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Draft Management

    /// Save a new draft configuration
    func saveDraft(_ catalog: DynamicToolCatalog) throws {
        guard let draftURL = draftConfigURL else {
            throw DynamicToolError.fileSystemError("Cannot determine draft file path")
        }

        // Validate before saving
        let issues = catalog.validate()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(catalog)
        try data.write(to: draftURL, options: .atomic)

        draftCatalog = catalog
        hasPendingDraft = true
        draftIssues = issues

        logger.info("Saved draft tool configuration v\(catalog.version)")
    }

    /// Approve and activate the current draft
    func activateDraft() throws {
        guard let draft = draftCatalog,
              let draftURL = draftConfigURL,
              let activeURL = activeConfigURL else {
            throw DynamicToolError.noDraftAvailable
        }

        // Check for blocking issues
        let blockingIssues = draftIssues.filter { issue in
            switch issue {
            case .parseError, .invalidStepConfig:
                return true
            default:
                return false
            }
        }
        if !blockingIssues.isEmpty {
            throw DynamicToolError.validationFailed(blockingIssues)
        }

        // Backup current active configuration
        if let currentActive = activeCatalog,
           let backupURL = backupConfigURL {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(currentActive) {
                try? data.write(to: backupURL, options: .atomic)
                logger.info("Backed up previous active tool configuration")
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
        NotificationCenter.default.post(name: .dynamicToolConfigurationDidChange, object: nil)

        logger.info("Activated draft tool configuration v\(draft.version)")
    }

    /// Discard the current draft
    func discardDraft() {
        guard let draftURL = draftConfigURL else { return }

        try? FileManager.default.removeItem(at: draftURL)
        draftCatalog = nil
        hasPendingDraft = false
        draftIssues = []

        logger.info("Discarded draft tool configuration")
    }

    /// Rollback to the previous backup
    func rollbackToBackup() throws {
        guard let backupURL = backupConfigURL,
              let activeURL = activeConfigURL,
              FileManager.default.fileExists(atPath: backupURL.path) else {
            throw DynamicToolError.noBackupAvailable
        }

        guard let catalog = loadCatalog(from: backupURL) else {
            throw DynamicToolError.invalidConfiguration("Backup file is corrupted")
        }

        try? FileManager.default.removeItem(at: activeURL)
        try FileManager.default.copyItem(at: backupURL, to: activeURL)

        activeCatalog = catalog
        NotificationCenter.default.post(name: .dynamicToolConfigurationDidChange, object: nil)

        logger.info("Rolled back to backup tool configuration v\(catalog.version)")
    }

    /// Reset to bundled defaults
    func resetToDefaults() throws {
        guard let bundledURL = bundledConfigURL,
              let activeURL = activeConfigURL else {
            throw DynamicToolError.fileSystemError("Cannot access bundled configuration")
        }

        guard let catalog = loadCatalog(from: bundledURL) else {
            throw DynamicToolError.invalidConfiguration("Bundled configuration is invalid")
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
        NotificationCenter.default.post(name: .dynamicToolConfigurationDidChange, object: nil)

        logger.info("Reset to bundled defaults v\(catalog.version)")
    }

    // MARK: - Tool Management

    /// Get all enabled dynamic tools
    func enabledTools() -> [DynamicToolConfig] {
        activeCatalog?.tools.filter { $0.enabled } ?? []
    }

    /// Get a specific tool by ID
    func tool(withId id: String) -> DynamicToolConfig? {
        activeCatalog?.tools.first { $0.id == id }
    }

    /// Get tools by category
    func tools(forCategory category: DynamicToolCategory) -> [DynamicToolConfig] {
        activeCatalog?.tools.filter { $0.category == category } ?? []
    }

    /// Enable or disable a tool
    func setToolEnabled(_ toolId: String, enabled: Bool) throws {
        guard var catalog = activeCatalog else {
            throw DynamicToolError.invalidConfiguration("No active catalog")
        }

        guard let index = catalog.tools.firstIndex(where: { $0.id == toolId }) else {
            throw DynamicToolError.toolNotFound(toolId)
        }

        catalog.tools[index].enabled = enabled

        // Save directly to active (no draft needed for enable/disable)
        guard let activeURL = activeConfigURL else {
            throw DynamicToolError.fileSystemError("Cannot determine active file path")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(catalog)
        try data.write(to: activeURL, options: .atomic)

        activeCatalog = catalog
        NotificationCenter.default.post(name: .dynamicToolConfigurationDidChange, object: nil)

        logger.info("Tool '\(toolId)' \(enabled ? "enabled" : "disabled")")
    }

    /// Add a new tool (saves to draft)
    func addTool(_ tool: DynamicToolConfig) throws {
        var catalog = activeCatalog ?? DynamicToolCatalog(
            version: "1.0.0",
            lastUpdated: Date(),
            tools: []
        )

        // Check for duplicate ID
        if catalog.tools.contains(where: { $0.id == tool.id }) {
            throw DynamicToolError.duplicateToolId(tool.id)
        }

        catalog.tools.append(tool)

        // Increment version
        let newVersion = incrementVersion(catalog.version)
        let updatedCatalog = DynamicToolCatalog(
            version: newVersion,
            lastUpdated: Date(),
            tools: catalog.tools
        )

        try saveDraft(updatedCatalog)
        logger.info("Added new tool '\(tool.id)' to draft")
    }

    /// Update an existing tool (saves to draft)
    func updateTool(_ tool: DynamicToolConfig) throws {
        guard var catalog = activeCatalog else {
            throw DynamicToolError.invalidConfiguration("No active catalog")
        }

        guard let index = catalog.tools.firstIndex(where: { $0.id == tool.id }) else {
            throw DynamicToolError.toolNotFound(tool.id)
        }

        catalog.tools[index] = tool

        let newVersion = incrementVersion(catalog.version)
        let updatedCatalog = DynamicToolCatalog(
            version: newVersion,
            lastUpdated: Date(),
            tools: catalog.tools
        )

        try saveDraft(updatedCatalog)
        logger.info("Updated tool '\(tool.id)' in draft")
    }

    /// Delete a tool (saves to draft)
    func deleteTool(_ toolId: String) throws {
        guard var catalog = activeCatalog else {
            throw DynamicToolError.invalidConfiguration("No active catalog")
        }

        catalog.tools.removeAll { $0.id == toolId }

        let newVersion = incrementVersion(catalog.version)
        let updatedCatalog = DynamicToolCatalog(
            version: newVersion,
            lastUpdated: Date(),
            tools: catalog.tools
        )

        try saveDraft(updatedCatalog)
        logger.info("Deleted tool '\(toolId)' in draft")
    }

    // MARK: - Helpers

    private func incrementVersion(_ version: String) -> String {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return "1.0.1" }

        let newPatch = parts[2] + 1
        return "\(parts[0]).\(parts[1]).\(newPatch)"
    }

    // MARK: - System Prompt Generation

    /// Generate system prompt section for all enabled dynamic tools
    func generateSystemPromptSection() -> String {
        let enabled = enabledTools()
        guard !enabled.isEmpty else { return "" }

        var prompt = "\n\n## Dynamic Tools\n\nYou also have access to these custom tools:\n\n"

        for tool in enabled {
            prompt += tool.generatePromptDescription()
            prompt += "\n\n"
        }

        return prompt
    }
}

// MARK: - Errors

enum DynamicToolError: LocalizedError {
    case fileSystemError(String)
    case invalidConfiguration(String)
    case validationFailed([DynamicToolIssue])
    case noDraftAvailable
    case noBackupAvailable
    case toolNotFound(String)
    case duplicateToolId(String)
    case executionFailed(String)
    case secretNotConfigured(String)

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
        case .toolNotFound(let id):
            return "Tool not found: \(id)"
        case .duplicateToolId(let id):
            return "Duplicate tool ID: \(id)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .secretNotConfigured(let key):
            return "Secret not configured: \(key)"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let dynamicToolConfigurationDidChange = Notification.Name("DynamicToolConfigurationDidChange")
}
