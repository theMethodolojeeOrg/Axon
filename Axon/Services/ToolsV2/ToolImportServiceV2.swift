//
//  ToolImportServiceV2.swift
//  Axon
//
//  Import tools from GitHub, iCloud, and Axon Store.
//

import Foundation
import os.log

// MARK: - Import Source

/// Where tools can be imported from
enum ToolImportSource {
    case github(url: URL)
    case iCloud
    case localFile(url: URL)
    case axonStore(toolId: String) // Future: central catalog
}

// MARK: - Import Result

/// Result of a tool import operation
struct ToolImportResult {
    let success: Bool
    let tool: LoadedTool?
    let error: ToolImportError?
    let warnings: [String]
}

// MARK: - Import Error

enum ToolImportError: LocalizedError {
    case invalidURL(String)
    case networkError(Error)
    case downloadFailed(String)
    case invalidManifest(String)
    case validationFailed([String])
    case securityViolation(String)
    case alreadyExists(String)
    case writePermissionDenied
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .invalidManifest(let reason):
            return "Invalid manifest: \(reason)"
        case .validationFailed(let issues):
            return "Validation failed: \(issues.joined(separator: ", "))"
        case .securityViolation(let reason):
            return "Security violation: \(reason)"
        case .alreadyExists(let toolId):
            return "Tool already exists: \(toolId)"
        case .writePermissionDenied:
            return "Cannot write to tools directory"
        case .unsupportedSource:
            return "Unsupported import source"
        }
    }
}

// MARK: - Import Service

/// Service for importing tools from external sources
@MainActor
final class ToolImportServiceV2: ObservableObject {

    // MARK: - Singleton

    static let shared = ToolImportServiceV2()

    // MARK: - Published State

    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: Double = 0
    @Published private(set) var importStatus: String = ""

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ToolImportService"
    )

    private let fileManager = FileManager.default
    private let decoder = ToolManifestDecoder.shared

    /// Allowed domains for API endpoints in imported tools
    private let allowedAPIDomains: Set<String> = [
        "api.openai.com",
        "generativelanguage.googleapis.com",
        "api.anthropic.com",
        "api.x.ai",
        "api.perplexity.ai",
        "api.deepseek.com",
        "open.bigmodel.cn"
    ]

    /// Disallowed execution types for imported tools
    private let disallowedExecutionTypes: Set<ToolExecution.ExecutionType> = [
        .bridge // Don't allow imported tools to use bridge
    ]

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Import a tool from a GitHub URL
    /// - Parameter urlString: GitHub URL (can be repo root, raw file, or release)
    /// - Returns: Import result
    func importFromGitHub(urlString: String) async -> ToolImportResult {
        guard let url = parseGitHubURL(urlString) else {
            return ToolImportResult(
                success: false,
                tool: nil,
                error: .invalidURL(urlString),
                warnings: []
            )
        }

        isImporting = true
        importProgress = 0
        importStatus = "Fetching tool manifest..."

        defer {
            isImporting = false
            importProgress = 0
            importStatus = ""
        }

        do {
            // Download the tool.json
            importProgress = 0.2
            let manifestData = try await downloadFile(from: url)

            importProgress = 0.4
            importStatus = "Validating manifest..."

            // Parse and validate
            guard let manifest = try? JSONDecoder().decode(ToolManifest.self, from: manifestData) else {
                return ToolImportResult(
                    success: false,
                    tool: nil,
                    error: .invalidManifest("Failed to parse tool.json"),
                    warnings: []
                )
            }

            // Security validation
            importProgress = 0.6
            importStatus = "Security check..."

            let securityResult = validateSecurity(manifest: manifest)
            if let securityError = securityResult.error {
                return ToolImportResult(
                    success: false,
                    tool: nil,
                    error: securityError,
                    warnings: securityResult.warnings
                )
            }

            // Check for duplicates
            let pluginLoader = ToolPluginLoader.shared
            if pluginLoader.hasToolId(manifest.id) {
                return ToolImportResult(
                    success: false,
                    tool: nil,
                    error: .alreadyExists(manifest.id),
                    warnings: []
                )
            }

            // Write to community folder
            importProgress = 0.8
            importStatus = "Installing tool..."

            let installedTool = try await installTool(manifest: manifest, data: manifestData, source: .github(url: url))

            importProgress = 1.0
            importStatus = "Complete!"

            logger.info("Successfully imported tool: \(manifest.id) from GitHub")

            return ToolImportResult(
                success: true,
                tool: installedTool,
                error: nil,
                warnings: securityResult.warnings
            )

        } catch {
            logger.error("Failed to import from GitHub: \(error.localizedDescription)")
            return ToolImportResult(
                success: false,
                tool: nil,
                error: .networkError(error),
                warnings: []
            )
        }
    }

    /// Import a tool from a local file
    /// - Parameter fileURL: Local file URL to tool.json
    /// - Returns: Import result
    func importFromLocalFile(fileURL: URL) async -> ToolImportResult {
        isImporting = true
        importProgress = 0
        importStatus = "Reading file..."

        defer {
            isImporting = false
            importProgress = 0
            importStatus = ""
        }

        do {
            // Read the file
            let manifestData = try Data(contentsOf: fileURL)

            importProgress = 0.3
            importStatus = "Validating manifest..."

            // Parse and validate
            guard let manifest = try? JSONDecoder().decode(ToolManifest.self, from: manifestData) else {
                return ToolImportResult(
                    success: false,
                    tool: nil,
                    error: .invalidManifest("Failed to parse tool.json"),
                    warnings: []
                )
            }

            // Security validation
            importProgress = 0.5
            let securityResult = validateSecurity(manifest: manifest)
            if let securityError = securityResult.error {
                return ToolImportResult(
                    success: false,
                    tool: nil,
                    error: securityError,
                    warnings: securityResult.warnings
                )
            }

            // Check for duplicates
            let pluginLoader = ToolPluginLoader.shared
            if pluginLoader.hasToolId(manifest.id) {
                return ToolImportResult(
                    success: false,
                    tool: nil,
                    error: .alreadyExists(manifest.id),
                    warnings: []
                )
            }

            // Install
            importProgress = 0.8
            importStatus = "Installing..."

            let installedTool = try await installTool(manifest: manifest, data: manifestData, source: .localFile(url: fileURL))

            importProgress = 1.0
            logger.info("Successfully imported tool: \(manifest.id) from local file")

            return ToolImportResult(
                success: true,
                tool: installedTool,
                error: nil,
                warnings: securityResult.warnings
            )

        } catch {
            logger.error("Failed to import from local file: \(error.localizedDescription)")
            return ToolImportResult(
                success: false,
                tool: nil,
                error: .networkError(error),
                warnings: []
            )
        }
    }

    /// Delete an imported tool
    /// - Parameter toolId: Tool ID to delete
    /// - Returns: True if deleted successfully
    func deleteImportedTool(toolId: String) async -> Bool {
        let pluginLoader = ToolPluginLoader.shared

        guard let tool = pluginLoader.tool(byId: toolId) else {
            logger.warning("Tool not found for deletion: \(toolId)")
            return false
        }

        // Only allow deleting custom/imported tools
        guard tool.source != .bundled else {
            logger.warning("Cannot delete bundled tool: \(toolId)")
            return false
        }

        do {
            try fileManager.removeItem(at: tool.folderPath)
            await pluginLoader.reloadTools()
            logger.info("Deleted tool: \(toolId)")
            return true
        } catch {
            logger.error("Failed to delete tool: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - GitHub URL Parsing

    private func parseGitHubURL(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString) else { return nil }

        // Handle various GitHub URL formats
        var rawURL: String

        if url.host == "raw.githubusercontent.com" {
            // Already a raw URL
            rawURL = urlString
        } else if url.host == "github.com" {
            // Convert to raw URL
            // github.com/user/repo/blob/main/path/tool.json -> raw.githubusercontent.com/user/repo/main/path/tool.json
            let pathComponents = url.pathComponents.filter { $0 != "/" }

            if pathComponents.count >= 4 && pathComponents[2] == "blob" {
                let user = pathComponents[0]
                let repo = pathComponents[1]
                let branch = pathComponents[3]
                let filePath = pathComponents.dropFirst(4).joined(separator: "/")
                rawURL = "https://raw.githubusercontent.com/\(user)/\(repo)/\(branch)/\(filePath)"
            } else if pathComponents.count >= 2 {
                // Assume it's a repo root, look for tool.json in root
                let user = pathComponents[0]
                let repo = pathComponents[1]
                rawURL = "https://raw.githubusercontent.com/\(user)/\(repo)/main/tool.json"
            } else {
                return nil
            }
        } else {
            return nil
        }

        return URL(string: rawURL)
    }

    // MARK: - Download

    private func downloadFile(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolImportError.downloadFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw ToolImportError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }

        return data
    }

    // MARK: - Security Validation

    private func validateSecurity(manifest: ToolManifest) -> (error: ToolImportError?, warnings: [String]) {
        var warnings: [String] = []

        // Check execution type
        if disallowedExecutionTypes.contains(manifest.execution.type) {
            return (
                .securityViolation("Execution type '\(manifest.execution.type.rawValue)' is not allowed for imported tools"),
                warnings
            )
        }

        // Check for internal handlers (must be registered handlers only)
        if manifest.execution.type == .internalHandler {
            warnings.append("Tool uses internal handler - may not work if handler is not registered")
        }

        // Validate manifest
        let issues = manifest.validate()
        let errors = issues.filter { $0.isError }
        if !errors.isEmpty {
            return (
                .validationFailed(errors.map { $0.message }),
                warnings
            )
        }

        // Add any validation warnings
        warnings.append(contentsOf: issues.filter { !$0.isError }.map { $0.message })

        // Tool requires approval warning
        if manifest.tool.effectiveRequiresApproval {
            warnings.append("This tool requires user approval before execution")
        }

        return (nil, warnings)
    }

    // MARK: - Installation

    private func installTool(manifest: ToolManifest, data: Data, source: ToolImportSource) async throws -> LoadedTool {
        // Get community tools directory
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ToolImportError.writePermissionDenied
        }

        let communityURL = documentsURL
            .appendingPathComponent("AxonTools")
            .appendingPathComponent("community")
            .appendingPathComponent(manifest.id)

        // Create directory
        try fileManager.createDirectory(at: communityURL, withIntermediateDirectories: true)

        // Write manifest
        let manifestURL = communityURL.appendingPathComponent("tool.json")
        try data.write(to: manifestURL)

        // Create loaded tool
        let loadedTool = LoadedTool(
            manifest: manifest,
            source: .imported(url: manifestURL),
            manifestPath: manifestURL,
            folderPath: communityURL,
            isEnabled: true
        )

        // Reload plugin loader
        await ToolPluginLoader.shared.reloadTools()

        return loadedTool
    }

    // MARK: - iCloud Sync

    /// Sync tools from iCloud
    func syncFromICloud() async {
        logger.info("Syncing tools from iCloud...")
        await ToolPluginLoader.shared.reloadTools()
    }

    /// Export a tool to iCloud for sharing
    func exportToICloud(toolId: String) async -> Bool {
        guard let tool = ToolPluginLoader.shared.tool(byId: toolId) else {
            logger.warning("Tool not found for export: \(toolId)")
            return false
        }

        guard let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("AxonTools")
            .appendingPathComponent("shared") else {
            logger.warning("iCloud not available")
            return false
        }

        do {
            // Create shared directory if needed
            try fileManager.createDirectory(at: iCloudURL, withIntermediateDirectories: true)

            // Copy tool folder
            let destinationURL = iCloudURL.appendingPathComponent(tool.id)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: tool.folderPath, to: destinationURL)

            logger.info("Exported tool to iCloud: \(toolId)")
            return true
        } catch {
            logger.error("Failed to export to iCloud: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Import View Model

/// View model for tool import UI
@MainActor
final class ToolImportViewModel: ObservableObject {
    @Published var urlInput = ""
    @Published var isImporting = false
    @Published var importResult: ToolImportResult?
    @Published var showingFilePicker = false

    private let importService = ToolImportServiceV2.shared

    var canImport: Bool {
        !urlInput.isEmpty && !isImporting
    }

    func importFromURL() async {
        guard canImport else { return }

        isImporting = true
        importResult = nil

        importResult = await importService.importFromGitHub(urlString: urlInput)

        isImporting = false

        if importResult?.success == true {
            urlInput = ""
        }
    }

    func importFromFile(url: URL) async {
        isImporting = true
        importResult = nil

        importResult = await importService.importFromLocalFile(fileURL: url)

        isImporting = false
    }
}
