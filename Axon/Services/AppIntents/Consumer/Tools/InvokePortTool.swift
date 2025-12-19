//
//  InvokePortTool.swift
//  Axon
//
//  AI tool for invoking external app ports.
//  Handles URL scheme invocation with session-based approval.
//

import Foundation
import os.log

// MARK: - Invoke Port Tool

/// Tool for the AI to invoke external app ports
struct InvokePortTool {
    static let toolId = "invoke_port"
    static let toolName = "Invoke External App"
    static let toolDescription = """
    Invoke an external app action via URL scheme. Use discover_ports first to see available ports and their parameters. \
    Requires user approval on first use per port per session.
    """

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "InvokePortTool")

    /// Execute the tool with given query
    /// Query format: "port_id | param1=value1 | param2=value2"
    @MainActor
    static func execute(query: String) async -> String {
        let invocationService = ShortcutInvocationService.shared

        // Parse the query
        guard let (portId, parameters) = parseQuery(query) else {
            return """
            Error: Invalid query format.

            Expected format: port_id | param1=value1 | param2=value2

            Examples:
            - obsidian_new_note | name=My Note | content=Hello world
            - things_add | title=Buy groceries | when=today
            - shortcuts_run | name=My Shortcut | input=some text

            Use discover_ports to see available ports and their parameters.
            """
        }

        // Execute the invocation
        let result = await invocationService.invokePort(portId: portId, parameters: parameters)

        return formatResult(result, portId: portId)
    }

    /// Parse query string into port ID and parameters
    private static func parseQuery(_ query: String) -> (portId: String, parameters: [String: String])? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)

        // Try JSON format first
        if trimmedQuery.hasPrefix("{"),
           let data = trimmedQuery.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseJsonQuery(json)
        }

        // Pipe-separated format
        let parts = trimmedQuery.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }

        guard !parts.isEmpty, !parts[0].isEmpty else {
            return nil
        }

        let portId = parts[0]
        var parameters: [String: String] = [:]

        for i in 1..<parts.count {
            let paramStr = parts[i]
            if let eqIndex = paramStr.firstIndex(of: "=") {
                let key = String(paramStr[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(paramStr[paramStr.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                parameters[key] = value
            }
        }

        return (portId, parameters)
    }

    /// Parse JSON query format
    private static func parseJsonQuery(_ json: [String: Any]) -> (portId: String, parameters: [String: String])? {
        // Try "port" or "port_id" key
        guard let portId = (json["port"] as? String) ?? (json["port_id"] as? String) ?? (json["id"] as? String) else {
            return nil
        }

        var parameters: [String: String] = [:]

        // Get parameters from "params" or "parameters" key, or from root level
        let paramSource: [String: Any]
        if let params = json["params"] as? [String: Any] {
            paramSource = params
        } else if let params = json["parameters"] as? [String: Any] {
            paramSource = params
        } else {
            // Use root level, excluding known keys
            let excludeKeys = Set(["port", "port_id", "id", "tool", "query"])
            paramSource = json.filter { !excludeKeys.contains($0.key) }
        }

        for (key, value) in paramSource {
            if let strValue = value as? String {
                parameters[key] = strValue
            } else {
                parameters[key] = String(describing: value)
            }
        }

        return (portId, parameters)
    }

    /// Format the invocation result for display
    private static func formatResult(_ result: PortInvocationResult, portId: String) -> String {
        switch result {
        case .success(let url):
            return """
            ✓ Successfully invoked '\(portId)'
            URL: \(url.absoluteString)

            The external app should now be open with the requested action.
            """

        case .appNotInstalled(let appStoreUrl):
            var message = "✗ App not installed for '\(portId)'"
            if let storeUrl = appStoreUrl {
                message += "\n\nInstall from App Store: \(storeUrl)"
            }
            return message

        case .invalidParameters(let missing):
            let portRegistry = PortRegistry.shared
            let port = portRegistry.port(id: portId)

            var message = "✗ Missing required parameters: \(missing.joined(separator: ", "))\n\n"

            if let port = port {
                message += "Required parameters for '\(portId)':\n"
                for param in port.parameters where param.isRequired {
                    message += "  - \(param.name): \(param.description)\n"
                }

                let optionalParams = port.parameters.filter { !$0.isRequired }
                if !optionalParams.isEmpty {
                    message += "\nOptional parameters:\n"
                    for param in optionalParams {
                        message += "  - \(param.name): \(param.description)\n"
                    }
                }
            }

            return message

        case .urlGenerationFailed:
            return "✗ Failed to generate URL for '\(portId)'. Please check the parameters."

        case .userCancelled:
            return "✗ User declined to invoke '\(portId)'. The action was not performed."

        case .error(let message):
            return "✗ Error invoking '\(portId)': \(message)"
        }
    }

    /// Generate the tool configuration for dynamic tool system
    static func generateToolConfig() -> DynamicToolConfig {
        DynamicToolConfig(
            id: toolId,
            name: toolName,
            description: toolDescription,
            category: .integration,
            enabled: true,
            icon: "arrow.up.forward.app",
            requiredSecrets: [],
            pipeline: [], // Special handling - not a pipeline tool
            parameters: [
                "query": ToolParameter(
                    type: .string,
                    required: true,
                    description: "Port ID and parameters in format: port_id | param1=value1 | param2=value2"
                )
            ],
            outputTemplate: nil,
            requiresApproval: true,  // Requires approval before invoking external apps
            approvalScopes: ["Invoke external app: {{input.query}}"]
        )
    }
}

// MARK: - Tool Registration

extension InvokePortTool {
    /// Check if a tool query is for this tool
    static func matches(toolId: String) -> Bool {
        return toolId == Self.toolId ||
               toolId == "invoke-port" ||
               toolId == "open_app" ||
               toolId == "open-app" ||
               toolId == "run_port" ||
               toolId == "run-port"
    }

    /// Parse input from the query field
    static func parseInput(_ input: String) -> String {
        // Handle JSON wrapper
        if input.hasPrefix("{"),
           let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let query = json["query"] as? String {
            return query
        }

        return input
    }
}
