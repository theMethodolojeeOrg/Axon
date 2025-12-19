//
//  DiscoverPortsTool.swift
//  Axon
//
//  AI tool for discovering available external app ports.
//  Allows the AI to list and search for apps it can invoke.
//

import Foundation
import os.log

// MARK: - Discover Ports Tool

/// Tool for the AI to discover available external app ports
struct DiscoverPortsTool {
    static let toolId = "discover_ports"
    static let toolName = "Discover External App Ports"
    static let toolDescription = """
    List available external app integrations (ports) that can be invoked. \
    Use this to discover what apps and actions are available, then use invoke_port to execute them.
    """

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "DiscoverPortsTool")

    /// Execute the tool with given query
    /// Query can be: empty (list all), category name, app name, or search term
    @MainActor
    static func execute(query: String) -> String {
        let portRegistry = PortRegistry.shared
        let enabledPorts = portRegistry.enabledPorts

        guard !enabledPorts.isEmpty else {
            return "No external app ports are currently enabled. Enable them in Settings > App Integrations."
        }

        // Parse query
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces).lowercased()

        // Check if query is a category
        if let category = PortCategory.allCases.first(where: { $0.rawValue.lowercased() == trimmedQuery || $0.displayName.lowercased() == trimmedQuery }) {
            let categoryPorts = portRegistry.ports(in: category)
            if categoryPorts.isEmpty {
                return "No ports available in category '\(category.displayName)'"
            }
            return formatPortList(categoryPorts, title: "Ports in \(category.displayName)")
        }

        // Search by query
        if !trimmedQuery.isEmpty {
            let searchResults = portRegistry.searchPorts(query: trimmedQuery)
            if searchResults.isEmpty {
                return "No ports found matching '\(query)'. Try: discover_ports (to list all) or discover_ports | category=notes"
            }
            return formatPortList(searchResults, title: "Ports matching '\(query)'")
        }

        // List all ports grouped by category
        return formatAllPorts(enabledPorts)
    }

    /// Format a list of ports for display
    private static func formatPortList(_ ports: [PortRegistryEntry], title: String) -> String {
        var output = "## \(title)\n\n"

        for port in ports {
            output += formatPort(port)
            output += "\n"
        }

        return output
    }

    /// Format all ports grouped by category
    private static func formatAllPorts(_ ports: [PortRegistryEntry]) -> String {
        var output = "## Available External App Ports\n\n"

        let grouped = Dictionary(grouping: ports) { $0.category }

        for category in PortCategory.allCases {
            guard let categoryPorts = grouped[category], !categoryPorts.isEmpty else { continue }

            output += "### \(category.displayName)\n\n"
            for port in categoryPorts {
                output += formatPort(port)
                output += "\n"
            }
        }

        output += """

        ---
        To invoke a port, use: invoke_port | port_id | param1=value1 | param2=value2
        To see more details about a category: discover_ports | category_name
        """

        return output
    }

    /// Format a single port for display
    private static func formatPort(_ port: PortRegistryEntry) -> String {
        var output = "**\(port.id)** - \(port.name)\n"
        output += "  App: \(port.appName) | Type: \(port.invocationType.displayName)\n"
        output += "  \(port.description)\n"

        if !port.parameters.isEmpty {
            output += "  Parameters:\n"
            for param in port.parameters {
                let required = param.isRequired ? "(required)" : "(optional)"
                output += "    - \(param.name) \(required): \(param.description)\n"
            }
        }

        return output
    }

    /// Generate the tool configuration for dynamic tool system
    static func generateToolConfig() -> DynamicToolConfig {
        DynamicToolConfig(
            id: toolId,
            name: toolName,
            description: toolDescription,
            category: .integration,
            enabled: true,
            icon: "app.connected.to.app.below.fill",
            requiredSecrets: [],
            pipeline: [], // Special handling - not a pipeline tool
            parameters: [
                "query": ToolParameter(
                    type: .string,
                    required: false,
                    description: "Optional search query, category name, or app name to filter results",
                    defaultValue: ""
                )
            ],
            outputTemplate: nil,
            requiresApproval: false,
            approvalScopes: nil
        )
    }
}

// MARK: - Tool Registration

extension DiscoverPortsTool {
    /// Check if a tool query is for this tool
    static func matches(toolId: String) -> Bool {
        return toolId == Self.toolId || toolId == "discover-ports" || toolId == "list_ports" || toolId == "list-ports"
    }

    /// Parse input from various formats
    static func parseInput(_ input: String) -> String {
        // Handle JSON format
        if input.hasPrefix("{"),
           let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let query = json["query"] as? String {
            return query
        }

        // Handle pipe format: "discover_ports | query"
        if input.contains("|") {
            let parts = input.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count > 1 {
                // Check for key=value format
                let paramPart = parts[1]
                if paramPart.contains("=") {
                    let keyValue = paramPart.split(separator: "=", maxSplits: 1)
                    if keyValue.count == 2 {
                        return String(keyValue[1]).trimmingCharacters(in: .whitespaces)
                    }
                }
                return paramPart
            }
        }

        // Plain text query
        return input
    }
}
