//
//  ToolPluginLoader.swift
//  Axon
//
//  Created by Claude Code on 2024-12-19.
//
//  Discovers and loads tool plugin folders from bundled resources, Documents, and iCloud.
//

import Foundation
import os.log
import Combine

// MARK: - Plugin Loader Service

/// Service for discovering and loading tool plugins from various sources
@MainActor
final class ToolPluginLoader: ObservableObject {

    // MARK: - Singleton

    static let shared = ToolPluginLoader()

    // MARK: - Published State

    /// All loaded tools
    @Published private(set) var loadedTools: [LoadedTool] = []

    /// Loading state
    @Published private(set) var isLoading: Bool = false

    /// Last load error, if any
    @Published private(set) var lastError: ToolPluginLoaderError?

    /// Default trust tier configurations by category (loaded from _index.json)
    @Published private(set) var defaultTrustTiers: [String: TrustTierDefault] = [:]

    /// Tools grouped by category
    var toolsByCategory: [ToolCategoryV2: [LoadedTool]] {
        Dictionary(grouping: loadedTools, by: { $0.category })
    }

    /// Enabled tools only
    var enabledTools: [LoadedTool] {
        loadedTools.filter { $0.isEnabled }
    }

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ToolPluginLoader"
    )

    private let decoder = ToolManifestDecoder.shared
    private let fileManager = FileManager.default

    /// Tool manifest filename prefix (matches tool.json or tool_*.json)
    private let manifestFilenamePrefix = "tool"
    private let manifestFileExtension = "json"

    /// Root folder name for tools
    private let toolsFolderName = "AxonTools"

    /// User defaults key for enabled/disabled state
    private let enabledStateKey = "ToolsV2EnabledState"

    // MARK: - Initialization

    private init() {
        logger.debug("ToolPluginLoader initialized")
    }

    // MARK: - Public API

    /// Load all tools from all sources
    func loadAllTools() async {
        guard !isLoading else {
            logger.warning("Already loading tools, skipping duplicate request")
            return
        }

        isLoading = true
        lastError = nil
        logger.info("Starting tool discovery...")

        var allTools: [LoadedTool] = []

        // 1. Load bundled tools (read-only, shipped with app)
        let bundledTools = await loadBundledTools()
        allTools.append(contentsOf: bundledTools)
        logger.info("Loaded \(bundledTools.count) bundled tools")

        // 2. Load iCloud tools
        let iCloudTools = await loadICloudTools()
        allTools.append(contentsOf: iCloudTools)
        logger.info("Loaded \(iCloudTools.count) iCloud tools")

        // 3. Load imported/custom tools from Documents
        let documentTools = await loadDocumentTools()
        allTools.append(contentsOf: documentTools)
        logger.info("Loaded \(documentTools.count) document tools")

        // Apply saved enabled/disabled state
        allTools = applyEnabledState(to: allTools)

        // Sort by category then name
        allTools.sort { ($0.category.rawValue, $0.name) < ($1.category.rawValue, $1.name) }

        loadedTools = allTools
        isLoading = false

        logger.info("Tool discovery complete. Total tools: \(allTools.count)")
    }

    /// Reload all tools (clears cache and reloads)
    func reloadTools() async {
        loadedTools = []
        await loadAllTools()
    }

    /// Load a single tool from a specific path
    /// - Parameter url: URL to the tool folder (containing tool.json or tool_*.json)
    /// - Returns: The loaded tool or nil if loading fails
    func loadTool(from url: URL) async -> LoadedTool? {
        // First try tool.json, then look for tool_*.json pattern
        let toolJsonURL = url.appendingPathComponent("tool.json")
        if fileManager.fileExists(atPath: toolJsonURL.path) {
            return loadManifest(at: toolJsonURL, source: .custom, folderPath: url)
        }

        // Look for tool_*.json pattern
        if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
           let manifestURL = contents.first(where: {
               $0.lastPathComponent.hasPrefix("tool_") && $0.pathExtension == "json"
           }) {
            return loadManifest(at: manifestURL, source: .custom, folderPath: url)
        }

        return nil
    }

    /// Get a tool by ID
    func tool(byId id: String) -> LoadedTool? {
        loadedTools.first { $0.id == id }
    }

    /// Search tools by query
    func searchTools(query: String) -> [LoadedTool] {
        guard !query.isEmpty else { return loadedTools }

        let lowercaseQuery = query.lowercased()
        return loadedTools.filter { tool in
            tool.name.lowercased().contains(lowercaseQuery) ||
            tool.description.lowercased().contains(lowercaseQuery) ||
            tool.id.lowercased().contains(lowercaseQuery) ||
            tool.category.displayName.lowercased().contains(lowercaseQuery)
        }
    }

    /// Toggle tool enabled state
    func setToolEnabled(_ toolId: String, enabled: Bool) {
        guard let index = loadedTools.firstIndex(where: { $0.id == toolId }) else {
            logger.warning("Tool not found for enable toggle: \(toolId)")
            return
        }

        loadedTools[index].isEnabled = enabled
        saveEnabledState()

        logger.debug("Tool '\(toolId)' enabled state set to: \(enabled)")
    }

    // MARK: - Source-Specific Loading

    /// Load tools bundled with the app
    private func loadBundledTools() async -> [LoadedTool] {
        guard let bundleURL = Bundle.main.resourceURL?.appendingPathComponent(toolsFolderName) else {
            logger.warning("Bundle tools folder not found - resourceURL is nil")
            return []
        }

        // Debug: Log the path being checked
        logger.info("Looking for bundled tools at: \(bundleURL.path)")
        logger.info("Directory exists: \(self.fileManager.fileExists(atPath: bundleURL.path))")

        // If directory doesn't exist, list what IS in the bundle resources
        if !self.fileManager.fileExists(atPath: bundleURL.path) {
            if let resourceURL = Bundle.main.resourceURL {
                logger.warning("AxonTools folder not found in bundle. Available resources:")
                if let contents = try? self.fileManager.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) {
                    for item in contents.prefix(20) {
                        logger.info("  - \(item.lastPathComponent)")
                    }
                }
            }
        }

        // Load trust tier defaults from the bundled index
        loadTrustTierDefaults(from: bundleURL)

        return await discoverTools(in: bundleURL, source: .bundled)
    }

    /// Load default trust tier configurations from _index.json
    private func loadTrustTierDefaults(from directory: URL) {
        let indexURL = directory.appendingPathComponent("_index.json")

        guard fileManager.fileExists(atPath: indexURL.path) else {
            logger.debug("No _index.json found at \(directory.path)")
            return
        }

        switch decoder.decodeIndex(from: indexURL) {
        case .success(let index):
            if let defaults = index.defaultTrustTiers {
                defaultTrustTiers = defaults
                logger.info("Loaded \(defaults.count) default trust tier configurations")
            }
        case .failure(let error):
            logger.warning("Failed to load trust tier defaults: \(error.localizedDescription)")
        }
    }

    /// Load tools from iCloud Drive
    private func loadICloudTools() async -> [LoadedTool] {
        guard let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent(toolsFolderName) else {
            logger.debug("iCloud not available or tools folder not found")
            return []
        }

        // Ensure directory exists
        if !fileManager.fileExists(atPath: iCloudURL.path) {
            logger.debug("iCloud tools folder does not exist")
            return []
        }

        return await discoverTools(in: iCloudURL, source: .iCloud)
    }

    /// Load tools from Documents directory
    private func loadDocumentTools() async -> [LoadedTool] {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.warning("Documents directory not accessible")
            return []
        }

        let toolsURL = documentsURL.appendingPathComponent(toolsFolderName)

        // Ensure directory exists
        if !fileManager.fileExists(atPath: toolsURL.path) {
            do {
                try fileManager.createDirectory(at: toolsURL, withIntermediateDirectories: true)
                logger.info("Created tools folder in Documents")
            } catch {
                logger.error("Failed to create tools folder: \(error.localizedDescription)")
                return []
            }
        }

        // Load custom tools
        let customURL = toolsURL.appendingPathComponent("custom")
        let customTools = await discoverTools(in: customURL, source: .custom)

        // Load community/imported tools
        let communityURL = toolsURL.appendingPathComponent("community")
        let communityTools = await discoverTools(in: communityURL, source: .custom)

        return customTools + communityTools
    }

    // MARK: - Discovery

    /// Discover all tools in a directory (recursively)
    private func discoverTools(in directory: URL, source: ToolSource) async -> [LoadedTool] {
        var tools: [LoadedTool] = []

        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        // Use directory enumerator for recursive discovery
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Failed to enumerate directory: \(directory.path)")
            return []
        }

        for case let fileURL as URL in enumerator {
            // Check if this is a tool manifest file (tool.json or tool_*.json)
            let filename = fileURL.lastPathComponent
            let isToolManifest = fileURL.pathExtension == manifestFileExtension &&
                (filename == "tool.json" ||
                 (filename.hasPrefix("tool_") && filename.hasSuffix(".json")))

            if isToolManifest {
                let folderPath = fileURL.deletingLastPathComponent()
                if let tool = loadManifest(at: fileURL, source: source, folderPath: folderPath) {
                    tools.append(tool)
                }
            }
        }

        return tools
    }

    /// Load a single manifest file
    private func loadManifest(at url: URL, source: ToolSource, folderPath: URL) -> LoadedTool? {
        switch decoder.decode(from: url) {
        case .success(let manifest):
            return LoadedTool(
                manifest: manifest,
                source: source,
                manifestPath: url,
                folderPath: folderPath,
                isEnabled: true  // Default to enabled, will be overridden by saved state
            )

        case .failure(let error):
            logger.error("Failed to load manifest at \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - State Persistence

    /// Apply saved enabled/disabled state to loaded tools
    private func applyEnabledState(to tools: [LoadedTool]) -> [LoadedTool] {
        guard let savedState = UserDefaults.standard.dictionary(forKey: enabledStateKey) as? [String: Bool] else {
            return tools
        }

        return tools.map { tool in
            var mutableTool = tool
            if let enabled = savedState[tool.id] {
                mutableTool.isEnabled = enabled
            }
            return mutableTool
        }
    }

    /// Save current enabled/disabled state
    private func saveEnabledState() {
        let state = Dictionary(uniqueKeysWithValues: loadedTools.map { ($0.id, $0.isEnabled) })
        UserDefaults.standard.set(state, forKey: enabledStateKey)
        logger.debug("Saved enabled state for \(state.count) tools")
    }

    // MARK: - Index Management

    /// Load or create the index file for a directory
    func loadIndex(from directory: URL) -> ToolIndex? {
        let indexURL = directory.appendingPathComponent("_index.json")

        switch decoder.decodeIndex(from: indexURL) {
        case .success(let index):
            return index
        case .failure:
            return nil
        }
    }

    /// Create an index from discovered tools
    func createIndex(for tools: [LoadedTool], relativeTo baseURL: URL) -> ToolIndex {
        let entries = tools.map { tool in
            let relativePath = tool.folderPath.path.replacingOccurrences(of: baseURL.path + "/", with: "")
            return ToolIndexEntry(
                id: tool.id,
                path: relativePath,
                category: tool.category,
                enabled: tool.isEnabled
            )
        }

        return ToolIndex(
            version: ToolIndex.currentVersion,
            lastUpdated: Date(),
            tools: entries,
            defaultTrustTiers: defaultTrustTiers.isEmpty ? nil : defaultTrustTiers
        )
    }

    /// Save an index to disk
    func saveIndex(_ index: ToolIndex, to directory: URL) throws {
        let indexURL = directory.appendingPathComponent("_index.json")

        switch decoder.encode(index) {
        case .success(let data):
            try data.write(to: indexURL)
            logger.debug("Saved index to: \(indexURL.path)")

        case .failure(let error):
            throw error
        }
    }
}

// MARK: - Errors

/// Errors that can occur during plugin loading
enum ToolPluginLoaderError: LocalizedError {
    case directoryNotFound(String)
    case permissionDenied(String)
    case invalidManifest(String, ToolManifestError)
    case duplicateToolId(String)

    var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Tools directory not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied accessing: \(path)"
        case .invalidManifest(let path, let error):
            return "Invalid manifest at \(path): \(error.localizedDescription)"
        case .duplicateToolId(let id):
            return "Duplicate tool ID found: \(id)"
        }
    }
}

// MARK: - Convenience Extensions

extension ToolPluginLoader {

    /// Get all tools for a specific category
    func tools(for category: ToolCategoryV2) -> [LoadedTool] {
        loadedTools.filter { $0.category == category }
    }

    /// Get enabled tools for a specific category
    func enabledTools(for category: ToolCategoryV2) -> [LoadedTool] {
        loadedTools.filter { $0.category == category && $0.isEnabled }
    }

    /// Check if a tool ID exists
    func hasToolId(_ id: String) -> Bool {
        loadedTools.contains { $0.id == id }
    }

    // MARK: - Trust Tier Inference

    /// Get the effective trust tier category for a tool, applying defaults if needed
    /// - Parameter tool: The loaded tool to check
    /// - Returns: The trust tier category string, or nil if none is defined
    func effectiveTrustTierCategory(for tool: LoadedTool) -> String? {
        // 1. Check explicit trustTierCategory on the tool
        if let explicit = tool.manifest.tool.trustTierCategory {
            return explicit
        }

        // 2. Check sovereignty actionCategory
        if let sovereignty = tool.manifest.sovereignty?.actionCategory {
            return sovereignty
        }

        // 3. Fall back to category defaults from _index.json
        let categoryKey = tool.manifest.tool.category.rawValue
        if let defaults = defaultTrustTiers[categoryKey] {
            return defaults.trustTierCategory
        }

        // Also check alternative category names (mac_system vs system)
        // The index uses category names from _index.json which may differ from enum raw values
        return nil
    }

    /// Get the effective risk level for a tool, applying defaults if needed
    /// - Parameter tool: The loaded tool to check
    /// - Returns: The risk level, defaulting to .medium if none defined
    func effectiveRiskLevel(for tool: LoadedTool) -> ToolSovereigntyConfig.RiskLevel {
        // 1. Check explicit sovereignty riskLevel
        if let explicit = tool.manifest.sovereignty?.riskLevel {
            return explicit
        }

        // 2. Fall back to category defaults
        let categoryKey = tool.manifest.tool.category.rawValue
        if let defaults = defaultTrustTiers[categoryKey] {
            return defaults.riskLevel
        }

        // 3. Default to medium
        return .medium
    }

    /// Get whether a tool effectively requires approval, applying defaults if needed
    /// - Parameter tool: The loaded tool to check
    /// - Returns: True if the tool requires user approval
    func effectiveRequiresApproval(for tool: LoadedTool) -> Bool {
        // 1. Check explicit requiresApproval on the tool
        if let explicit = tool.manifest.tool.requiresApproval {
            return explicit
        }

        // 2. Check sovereignty risk level (high/critical requires approval)
        if let riskLevel = tool.manifest.sovereignty?.riskLevel {
            switch riskLevel {
            case .high, .critical:
                return true
            case .low, .medium:
                return false
            }
        }

        // 3. Fall back to category defaults
        let categoryKey = tool.manifest.tool.category.rawValue
        if let defaults = defaultTrustTiers[categoryKey] {
            return defaults.requiresApproval
        }

        // 4. Default to no approval required
        return false
    }

    /// Get the full trust tier default for a category
    /// - Parameter category: The category to look up
    /// - Returns: The default trust tier configuration, or nil if not defined
    func trustTierDefault(for category: ToolCategoryV2) -> TrustTierDefault? {
        defaultTrustTiers[category.rawValue]
    }

    /// Get tool IDs for enabled tools
    var enabledToolIds: Set<String> {
        Set(enabledTools.map { $0.id })
    }

    /// Statistics about loaded tools
    var stats: ToolLoaderStats {
        ToolLoaderStats(
            totalCount: loadedTools.count,
            enabledCount: enabledTools.count,
            bundledCount: loadedTools.filter { $0.source == .bundled }.count,
            iCloudCount: loadedTools.filter { $0.source == .iCloud }.count,
            customCount: loadedTools.filter { $0.source == .custom }.count,
            categoryBreakdown: Dictionary(grouping: loadedTools) { $0.category }
                .mapValues { $0.count }
        )
    }
}

/// Statistics about loaded tools
struct ToolLoaderStats {
    let totalCount: Int
    let enabledCount: Int
    let bundledCount: Int
    let iCloudCount: Int
    let customCount: Int
    let categoryBreakdown: [ToolCategoryV2: Int]
}

// MARK: - Hot Reload Support

extension ToolPluginLoader {

    /// Watch for changes in tool directories (for development)
    /// Note: This is a simplified version; full implementation would use FSEvents
    func setupFileWatcher() {
        // This would be implemented using DispatchSource or FSEvents
        // for real-time file watching during development
        logger.debug("File watcher setup (not yet implemented)")
    }

    /// Force reload a specific tool
    func reloadTool(_ toolId: String) async -> Bool {
        guard let existingTool = tool(byId: toolId) else {
            logger.warning("Cannot reload non-existent tool: \(toolId)")
            return false
        }

        guard let reloaded = await loadTool(from: existingTool.folderPath) else {
            logger.error("Failed to reload tool: \(toolId)")
            return false
        }

        // Replace in array
        if let index = loadedTools.firstIndex(where: { $0.id == toolId }) {
            var updatedTool = reloaded
            updatedTool.isEnabled = loadedTools[index].isEnabled
            loadedTools[index] = updatedTool
            logger.info("Successfully reloaded tool: \(toolId)")
            return true
        }

        return false
    }
}
