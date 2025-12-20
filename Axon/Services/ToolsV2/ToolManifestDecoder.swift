//
//  ToolManifestDecoder.swift
//  Axon
//
//  Created by Claude Code on 2024-12-19.
//
//  Parses and validates tool.json manifest files for the ToolsV2 plugin system.
//

import Foundation
import os.log

// MARK: - Decoder Service

/// Service for decoding and validating tool manifests
final class ToolManifestDecoder {

    // MARK: - Singleton

    static let shared = ToolManifestDecoder()

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ToolManifestDecoder"
    )

    private let decoder: JSONDecoder

    // MARK: - Initialization

    private init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .useDefaultKeys
    }

    // MARK: - Public API

    /// Decode a tool manifest from a file URL
    /// - Parameter url: URL to the tool.json file
    /// - Returns: Result containing either the decoded manifest or an error
    func decode(from url: URL) -> Result<ToolManifest, ToolManifestError> {
        logger.debug("Decoding manifest from: \(url.path)")

        // Read file data
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read manifest file: \(error.localizedDescription)")
            return .failure(.fileNotFound(url.path))
        }

        return decode(from: data, path: url.path)
    }

    /// Decode a tool manifest from JSON data
    /// - Parameters:
    ///   - data: JSON data to decode
    ///   - path: Optional path for error reporting
    /// - Returns: Result containing either the decoded manifest or an error
    func decode(from data: Data, path: String? = nil) -> Result<ToolManifest, ToolManifestError> {
        // Attempt to decode
        let manifest: ToolManifest
        do {
            manifest = try decoder.decode(ToolManifest.self, from: data)
        } catch let error as DecodingError {
            let detailedError = formatDecodingError(error, path: path)
            logger.error("Decoding error: \(detailedError)")
            return .failure(.decodingFailed(detailedError))
        } catch {
            logger.error("Unknown decoding error: \(error.localizedDescription)")
            return .failure(.decodingFailed(error.localizedDescription))
        }

        // Validate the manifest
        let issues = manifest.validate()
        let errors = issues.filter { $0.isError }

        if !errors.isEmpty {
            let errorMessages = errors.map { $0.message }.joined(separator: "; ")
            logger.error("Validation errors in manifest: \(errorMessages)")
            return .failure(.validationFailed(errors))
        }

        // Log warnings if any
        let warnings = issues.filter { !$0.isError }
        for warning in warnings {
            logger.warning("Manifest warning: \(warning.message)")
        }

        logger.debug("Successfully decoded manifest for tool: \(manifest.tool.id)")
        return .success(manifest)
    }

    /// Decode a tool manifest from a JSON string
    /// - Parameter jsonString: JSON string to decode
    /// - Returns: Result containing either the decoded manifest or an error
    func decode(from jsonString: String) -> Result<ToolManifest, ToolManifestError> {
        guard let data = jsonString.data(using: .utf8) else {
            return .failure(.invalidJSON("Could not convert string to UTF-8 data"))
        }
        return decode(from: data)
    }

    /// Validate a manifest without fully decoding it
    /// - Parameter url: URL to the tool.json file
    /// - Returns: Array of validation issues found
    func validateFile(at url: URL) -> [ToolManifestIssue] {
        switch decode(from: url) {
        case .success(let manifest):
            return manifest.validate()
        case .failure(let error):
            return [.error(error.localizedDescription)]
        }
    }

    /// Decode the tool index file (_index.json)
    /// - Parameter url: URL to the index file
    /// - Returns: Result containing either the decoded index or an error
    func decodeIndex(from url: URL) -> Result<ToolIndex, ToolManifestError> {
        logger.debug("Decoding index from: \(url.path)")

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read index file: \(error.localizedDescription)")
            return .failure(.fileNotFound(url.path))
        }

        do {
            let index = try decoder.decode(ToolIndex.self, from: data)
            logger.debug("Successfully decoded index with \(index.tools?.count ?? 0) entries")
            return .success(index)
        } catch let error as DecodingError {
            let detailedError = formatDecodingError(error, path: url.path)
            logger.error("Index decoding error: \(detailedError)")
            return .failure(.decodingFailed(detailedError))
        } catch {
            logger.error("Unknown index decoding error: \(error.localizedDescription)")
            return .failure(.decodingFailed(error.localizedDescription))
        }
    }

    // MARK: - Encoding

    /// Encode a tool manifest to JSON data
    /// - Parameters:
    ///   - manifest: The manifest to encode
    ///   - prettyPrinted: Whether to format with indentation
    /// - Returns: Result containing either the encoded data or an error
    func encode(_ manifest: ToolManifest, prettyPrinted: Bool = true) -> Result<Data, ToolManifestError> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }

        do {
            let data = try encoder.encode(manifest)
            return .success(data)
        } catch {
            logger.error("Failed to encode manifest: \(error.localizedDescription)")
            return .failure(.encodingFailed(error.localizedDescription))
        }
    }

    /// Encode a tool index to JSON data
    /// - Parameters:
    ///   - index: The index to encode
    ///   - prettyPrinted: Whether to format with indentation
    /// - Returns: Result containing either the encoded data or an error
    func encode(_ index: ToolIndex, prettyPrinted: Bool = true) -> Result<Data, ToolManifestError> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }

        do {
            let data = try encoder.encode(index)
            return .success(data)
        } catch {
            logger.error("Failed to encode index: \(error.localizedDescription)")
            return .failure(.encodingFailed(error.localizedDescription))
        }
    }

    // MARK: - Private Helpers

    /// Format a DecodingError into a human-readable message
    private func formatDecodingError(_ error: DecodingError, path: String?) -> String {
        let pathPrefix = path.map { "In '\($0)': " } ?? ""

        switch error {
        case .keyNotFound(let key, let context):
            let keyPath = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(pathPrefix)Missing required key '\(key.stringValue)' at path '\(keyPath)'"

        case .valueNotFound(let type, let context):
            let keyPath = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(pathPrefix)Missing value of type '\(type)' at path '\(keyPath)'"

        case .typeMismatch(let type, let context):
            let keyPath = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(pathPrefix)Type mismatch: expected '\(type)' at path '\(keyPath)'. \(context.debugDescription)"

        case .dataCorrupted(let context):
            let keyPath = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(pathPrefix)Data corrupted at path '\(keyPath)': \(context.debugDescription)"

        @unknown default:
            return "\(pathPrefix)Unknown decoding error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Errors

/// Errors that can occur during manifest decoding/encoding
enum ToolManifestError: LocalizedError, Equatable {
    case fileNotFound(String)
    case invalidJSON(String)
    case decodingFailed(String)
    case validationFailed([ToolManifestIssue])
    case encodingFailed(String)
    case unsupportedVersion(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Manifest file not found: \(path)"
        case .invalidJSON(let reason):
            return "Invalid JSON: \(reason)"
        case .decodingFailed(let reason):
            return "Failed to decode manifest: \(reason)"
        case .validationFailed(let issues):
            let messages = issues.map { $0.message }.joined(separator: "; ")
            return "Manifest validation failed: \(messages)"
        case .encodingFailed(let reason):
            return "Failed to encode manifest: \(reason)"
        case .unsupportedVersion(let version):
            return "Unsupported manifest version: \(version)"
        }
    }

    static func == (lhs: ToolManifestError, rhs: ToolManifestError) -> Bool {
        switch (lhs, rhs) {
        case (.fileNotFound(let l), .fileNotFound(let r)): return l == r
        case (.invalidJSON(let l), .invalidJSON(let r)): return l == r
        case (.decodingFailed(let l), .decodingFailed(let r)): return l == r
        case (.validationFailed(let l), .validationFailed(let r)): return l == r
        case (.encodingFailed(let l), .encodingFailed(let r)): return l == r
        case (.unsupportedVersion(let l), .unsupportedVersion(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - Schema Validation

extension ToolManifestDecoder {

    /// Validate a manifest against the JSON schema
    /// - Parameter manifest: The manifest to validate
    /// - Returns: Array of schema validation issues
    func validateSchema(_ manifest: ToolManifest) -> [ToolManifestIssue] {
        var issues: [ToolManifestIssue] = []

        // Version check
        let versionComponents = manifest.version.split(separator: ".")
        if versionComponents.count != 3 {
            issues.append(.warning("Version should follow semver format (x.y.z)"))
        }

        // Parameter validation
        if let parameters = manifest.parameters {
            for (name, param) in parameters {
                issues.append(contentsOf: validateParameter(name: name, param: param))
            }
        }

        // UI config validation
        if let ui = manifest.ui {
            issues.append(contentsOf: validateUIConfig(ui, parameters: manifest.parameters))
        }

        // Pipeline validation
        if let pipeline = manifest.execution.pipeline {
            issues.append(contentsOf: validatePipeline(pipeline))
        }

        return issues
    }

    private func validateParameter(name: String, param: ToolParameterV2) -> [ToolManifestIssue] {
        var issues: [ToolManifestIssue] = []

        // String constraints
        if param.type == .string {
            if let min = param.minLength, let max = param.maxLength, min > max {
                issues.append(.error("Parameter '\(name)': minLength (\(min)) > maxLength (\(max))"))
            }
        }

        // Number constraints
        if param.type == .number || param.type == .integer {
            if let min = param.minimum, let max = param.maximum, min > max {
                issues.append(.error("Parameter '\(name)': minimum (\(min)) > maximum (\(max))"))
            }
        }

        // Array constraints
        if param.type == .array {
            if param.items == nil {
                issues.append(.warning("Parameter '\(name)': array type should have items definition"))
            }
            if let min = param.minItems, let max = param.maxItems, min > max {
                issues.append(.error("Parameter '\(name)': minItems (\(min)) > maxItems (\(max))"))
            }
        }

        // Object constraints
        if param.type == .object && param.properties == nil {
            issues.append(.warning("Parameter '\(name)': object type should have properties definition"))
        }

        return issues
    }

    private func validateUIConfig(_ ui: ToolUIConfig, parameters: [String: ToolParameterV2]?) -> [ToolManifestIssue] {
        var issues: [ToolManifestIssue] = []

        // Validate form fields reference valid parameters
        if let fields = ui.inputForm?.fields, let params = parameters {
            for field in fields {
                if params[field.param] == nil {
                    issues.append(.error("UI field '\(field.param)' references non-existent parameter"))
                }
            }
        }

        // Validate template references in result display
        if let sections = ui.resultDisplay?.sections {
            for section in sections {
                if let source = section.source {
                    issues.append(contentsOf: validateTemplateString(source))
                }
            }
        }

        return issues
    }

    private func validatePipeline(_ steps: [PipelineStepV2]) -> [ToolManifestIssue] {
        var issues: [ToolManifestIssue] = []
        var stepIds = Set<String>()

        for step in steps {
            // Check for duplicate IDs
            if stepIds.contains(step.id) {
                issues.append(.error("Duplicate pipeline step ID: '\(step.id)'"))
            }
            stepIds.insert(step.id)

            // Validate nested steps
            if let thenSteps = step.then {
                issues.append(contentsOf: validatePipeline(thenSteps))
            }
            if let elseSteps = step.else {
                issues.append(contentsOf: validatePipeline(elseSteps))
            }
            if let parallelSteps = step.steps {
                issues.append(contentsOf: validatePipeline(parallelSteps))
            }
        }

        return issues
    }

    private func validateTemplateString(_ template: String) -> [ToolManifestIssue] {
        var issues: [ToolManifestIssue] = []

        // Check for balanced {{ }}
        let openCount = template.components(separatedBy: "{{").count - 1
        let closeCount = template.components(separatedBy: "}}").count - 1

        if openCount != closeCount {
            issues.append(.error("Unbalanced template braces in '\(template)'"))
        }

        return issues
    }
}

// MARK: - Convenience Extensions

extension ToolManifestDecoder {

    /// Quick check if a file is a valid tool manifest
    /// - Parameter url: URL to check
    /// - Returns: True if the file is a valid manifest
    func isValidManifest(at url: URL) -> Bool {
        switch decode(from: url) {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    /// Get basic info from a manifest without full validation
    /// - Parameter url: URL to the manifest
    /// - Returns: Tuple of (id, name, category) or nil if decoding fails
    func quickInfo(from url: URL) -> (id: String, name: String, category: ToolCategoryV2)? {
        switch decode(from: url) {
        case .success(let manifest):
            return (manifest.tool.id, manifest.tool.name, manifest.tool.category)
        case .failure:
            return nil
        }
    }
}
