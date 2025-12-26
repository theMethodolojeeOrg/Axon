//
//  MacSystemToolExecutor.swift
//  Axon
//
//  Executor for tools with bridge execution type.
//  On macOS: Executes locally via MacSystemService
//  On iOS: Routes through bridge to connected Mac
//

import Foundation
import os.log

@MainActor
final class MacSystemToolExecutor {
    static let shared = MacSystemToolExecutor()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "MacSystemToolExecutor")

    private init() {}

    // MARK: - Execution

    /// Execute a tool with bridge execution type
    func execute(manifest: ToolManifest, inputs: [String: Any]) async throws -> ToolResult {
        guard manifest.execution.type == .bridge else {
            throw MacSystemError.operationFailed("Tool is not a bridge execution type")
        }

        guard let bridgeMethod = manifest.execution.bridgeMethod else {
            throw MacSystemError.missingBridgeMethod
        }

        logger.info("Executing bridge tool: \(manifest.tool.id) via \(bridgeMethod)")

        #if os(macOS)
        // Execute locally via MacSystemService
        return try await executeLocally(method: bridgeMethod, inputs: inputs, manifest: manifest)
        #else
        // Execute remotely via bridge
        return try await executeViaBridge(method: bridgeMethod, inputs: inputs, manifest: manifest)
        #endif
    }

    // MARK: - Local Execution (macOS)

    #if os(macOS)
    private func executeLocally(method: String, inputs: [String: Any], manifest: ToolManifest) async throws -> ToolResult {
        let service = MacSystemService.shared

        // Convert inputs to appropriate params type and call service
        let result: Any
        switch method {
        case "system/info":
            result = try await service.getSystemInfo()

        case "system/processes":
            let limit = inputs["limit"] as? Int ?? 20
            result = try await service.getRunningProcesses(limit: limit)

        case "system/disk_usage":
            let path = inputs["path"] as? String ?? "/"
            result = try await service.getDiskUsage(path: path)

        case "clipboard/read":
            result = try await service.getClipboardContent()

        case "clipboard/write":
            guard let content = inputs["content"] as? String else {
                throw MacSystemError.operationFailed("Missing content parameter")
            }
            result = try await service.setClipboardContent(content)

        case "notification/send":
            guard let title = inputs["title"] as? String,
                  let message = inputs["message"] as? String else {
                throw MacSystemError.operationFailed("Missing title or message parameter")
            }
            result = try await service.sendNotification(
                title: title,
                message: message,
                subtitle: inputs["subtitle"] as? String,
                soundName: inputs["soundName"] as? String
            )

        case "spotlight/search":
            guard let query = inputs["query"] as? String else {
                throw MacSystemError.operationFailed("Missing query parameter")
            }
            result = try await service.spotlightSearch(
                query: query,
                limit: inputs["limit"] as? Int ?? 20,
                contentType: inputs["contentType"] as? String
            )

        case "file/find":
            guard let pattern = inputs["pattern"] as? String else {
                throw MacSystemError.operationFailed("Missing pattern parameter")
            }
            result = try await service.findFiles(
                pattern: pattern,
                directory: inputs["directory"] as? String ?? "~",
                maxDepth: inputs["maxDepth"] as? Int ?? 3
            )

        case "file/metadata":
            guard let path = inputs["path"] as? String else {
                throw MacSystemError.operationFailed("Missing path parameter")
            }
            result = try await service.getFileMetadata(path: path)

        case "file/read":
            guard let path = inputs["path"] as? String else {
                throw MacSystemError.operationFailed("Missing path parameter")
            }
            result = try await service.readFile(
                path: path,
                maxBytes: inputs["maxBytes"] as? Int,
                encoding: inputs["encoding"] as? String ?? "utf8"
            )

        case "file/list":
            let path = inputs["path"] as? String ?? "."
            result = try await service.listFiles(
                path: path,
                includeHidden: inputs["includeHidden"] as? Bool ?? false,
                maxItems: inputs["maxItems"] as? Int ?? 100
            )

        case "app/list":
            result = try await service.getRunningApplications()

        case "app/launch":
            guard let appName = inputs["appName"] as? String else {
                throw MacSystemError.operationFailed("Missing appName parameter")
            }
            result = try await service.launchApplication(
                name: appName,
                arguments: inputs["arguments"] as? [String]
            )

        case "screenshot/capture":
            result = try await service.takeScreenshot(
                path: inputs["path"] as? String,
                display: inputs["display"] as? Int,
                includeWindows: inputs["includeWindows"] as? Bool ?? true
            )

        case "network/info":
            result = try await service.getNetworkInfo()

        case "network/ping":
            guard let host = inputs["host"] as? String else {
                throw MacSystemError.operationFailed("Missing host parameter")
            }
            result = try await service.pingHost(
                host: host,
                count: inputs["count"] as? Int ?? 4,
                timeout: inputs["timeout"] as? Int ?? 5000
            )

        case "shell/execute":
            guard let command = inputs["command"] as? String else {
                throw MacSystemError.operationFailed("Missing command parameter")
            }
            result = try await service.executeShellCommand(
                command: command,
                timeout: inputs["timeout"] as? Int ?? 30000,
                workingDirectory: inputs["workingDirectory"] as? String
            )

        default:
            throw MacSystemError.operationFailed("Unknown bridge method: \(method)")
        }

        // Encode result to string
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let encodableResult = result as? Encodable {
            let data = try encoder.encode(AnyEncodable(encodableResult))
            let output = String(data: data, encoding: .utf8) ?? "{}"
            return ToolResult(
                tool: manifest.tool.id,
                success: true,
                result: output,
                sources: nil,
                memoryOperation: nil
            )
        } else {
            return ToolResult(
                tool: manifest.tool.id,
                success: true,
                result: String(describing: result),
                sources: nil,
                memoryOperation: nil
            )
        }
    }
    #endif

    // MARK: - Remote Execution (iOS via Bridge)

    #if !os(macOS)
    private func executeViaBridge(method: String, inputs: [String: Any], manifest: ToolManifest) async throws -> ToolResult {
        let connectionManager = BridgeConnectionManager.shared
        
        // Check if bridge is connected
        guard connectionManager.isConnected else {
            throw MacSystemError.bridgeNotConnected
        }

        logger.info("Executing via bridge: \(method)")

        // Convert inputs to AnyCodable using JSON encoding/decoding
        let params: AnyCodable
        do {
            let data = try JSONSerialization.data(withJSONObject: inputs)
            params = try JSONDecoder().decode(AnyCodable.self, from: data)
        } catch {
            throw MacSystemError.operationFailed("Failed to encode parameters: \(error.localizedDescription)")
        }

        // Send request via bridge connection manager
        let response = try await connectionManager.sendRequest(method: method, params: params)

        if let error = response.error {
            throw MacSystemError.operationFailed(error.message)
        }

        // Encode result to string
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let result = response.result {
            let data = try encoder.encode(result)
            let output = String(data: data, encoding: .utf8) ?? "{}"
            return ToolResult(
                tool: manifest.tool.id,
                success: true,
                result: output,
                sources: nil,
                memoryOperation: nil
            )
        } else {
            return ToolResult(
                tool: manifest.tool.id,
                success: true,
                result: "{}",
                sources: nil,
                memoryOperation: nil
            )
        }
    }
    #endif

    // Fallback for compilation on both platforms
    #if os(macOS)
    private func executeViaBridge(method: String, inputs: [String: Any], manifest: ToolManifest) async throws -> ToolResult {
        // On macOS, we execute locally, not via bridge
        throw MacSystemError.operationFailed("Bridge execution not needed on macOS - use local execution")
    }
    #else
    private func executeLocally(method: String, inputs: [String: Any], manifest: ToolManifest) async throws -> ToolResult {
        // On iOS, we can't execute locally
        throw MacSystemError.requiresBridge(method)
    }
    #endif
}

// MARK: - Type-Erased Encodable Wrapper

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        encodeFunc = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
