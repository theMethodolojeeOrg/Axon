//
//  DiscoveryHandler.swift
//  Axon
//
//  V2 Handler for tool discovery
//

import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Handler for discovery-related tools
///
/// Registered handlers:
/// - `discovery` → list_tools, get_tool_details, discover_ports, invoke_port
@MainActor
final class DiscoveryHandler: ToolHandlerV2 {
    
    let handlerId = "discovery"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "DiscoveryHandler"
    )
    
    private let pluginLoader = ToolPluginLoader.shared
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        switch toolId {
        case "list_tools":
            return executeListTools(inputs: inputs)
        case "get_tool_details":
            return executeGetToolDetails(inputs: inputs)
        case "discover_ports":
            return executeDiscoverPorts(inputs: inputs)
        case "invoke_port":
            return try await executeInvokePort(inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown discovery tool: \(toolId)")
        }
    }
    
    // MARK: - list_tools
    
    private func executeListTools(inputs: [String: Any]) -> ToolResultV2 {
        let filter = (inputs["query"] as? String)?.lowercased() ?? "all"
        
        logger.info("Listing tools: filter=\(filter)")
        
        let allTools = pluginLoader.loadedTools
        
        // All tools are considered loaded/available
        let filtered = allTools
        
        if filtered.isEmpty {
            return ToolResultV2.success(
                toolId: "list_tools",
                output: "No tools found for filter: \(filter)"
            )
        }
        
        var output = "# Available Tools (\(filtered.count))\n\n"
        
        // Group by category
        let grouped = Dictionary(grouping: filtered) { $0.manifest.tool.category }
        
        for (category, tools) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            output += "## \(category.rawValue.capitalized)\n"
            for tool in tools {
                output += "- **\(tool.id)**: \(tool.manifest.tool.description)\n"
            }
            output += "\n"
        }
        
        return ToolResultV2.success(
            toolId: "list_tools",
            output: output,
            structured: [
                "count": filtered.count,
                "filter": filter
            ]
        )
    }
    
    // MARK: - get_tool_details
    
    private func executeGetToolDetails(inputs: [String: Any]) -> ToolResultV2 {
        guard let toolId = inputs["query"] as? String else {
            return ToolResultV2.failure(
                toolId: "get_tool_details",
                error: "Missing tool ID in query"
            )
        }
        
        guard let loadedTool = pluginLoader.loadedTools.first(where: { $0.id == toolId }) else {
            return ToolResultV2.failure(
                toolId: "get_tool_details",
                error: "Tool not found: \(toolId)"
            )
        }
        
        let manifest = loadedTool.manifest
        
        var output = "# \(manifest.tool.name)\n\n"
        output += "**ID:** \(manifest.tool.id)\n"
        output += "**Description:** \(manifest.tool.description)\n"
        output += "**Category:** \(manifest.tool.category.rawValue)\n"
        output += "**Requires Approval:** \(manifest.tool.effectiveRequiresApproval ? "Yes" : "No")\n"
        
        if let params = manifest.parameters, !params.isEmpty {
            output += "\n## Parameters\n\n"
            for (name, param) in params.sorted(by: { $0.key < $1.key }) {
                let required = (param.required ?? false) ? "*" : ""
                output += "- **\(name)\(required)** (\(param.type.rawValue)): \(param.description ?? "")\n"
            }
        }
        
        return ToolResultV2.success(
            toolId: "get_tool_details",
            output: output,
            structured: [
                "id": manifest.tool.id,
                "name": manifest.tool.name
            ]
        )
    }
    
    // MARK: - discover_ports
    
    private func executeDiscoverPorts(inputs: [String: Any]) -> ToolResultV2 {
        let category = (inputs["query"] as? String)?.lowercased()
        
        logger.info("Discovering ports: category=\(category ?? "all")")
        
        // Get available ports from PortRegistry
        let ports = PortRegistry.shared.ports
        
        let filtered = category != nil && category != ""
            ? ports.filter { $0.category.rawValue.lowercased() == category }
            : ports
        
        if filtered.isEmpty {
            return ToolResultV2.success(
                toolId: "discover_ports",
                output: "No ports found\(category.map { " for category: \($0)" } ?? "")."
            )
        }
        
        var output = "# Available External App Ports\n\n"
        
        let grouped = Dictionary(grouping: filtered) { $0.category }
        
        for (cat, catPorts) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            output += "## \(cat.rawValue.capitalized)\n"
            for port in catPorts {
                output += "- **\(port.id)**: \(port.name)\n"
                output += "  \(port.description ?? "")\n"
            }
            output += "\n"
        }
        
        return ToolResultV2.success(
            toolId: "discover_ports",
            output: output,
            structured: [
                "count": filtered.count
            ]
        )
    }
    
    // MARK: - invoke_port
    
    private func executeInvokePort(inputs: [String: Any]) async throws -> ToolResultV2 {
        guard let query = inputs["query"] as? String else {
            return ToolResultV2.failure(
                toolId: "invoke_port",
                error: "Missing query. Format: port_id | param1=value1 | param2=value2"
            )
        }
        
        let parts = query.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let portId = parts.first, !portId.isEmpty else {
            return ToolResultV2.failure(
                toolId: "invoke_port",
                error: "Missing port_id in query"
            )
        }
        
        guard let port = PortRegistry.shared.port(id: portId) else {
            return ToolResultV2.failure(
                toolId: "invoke_port",
                error: "Port not found: \(portId)"
            )
        }
        
        // Parse parameters
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 {
                params[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
            }
        }
        
        logger.info("Invoking port: \(portId) with \(params.count) params")
        
        // Build and open URL
        guard let url = port.generateUrl(with: params) else {
            return ToolResultV2.failure(
                toolId: "invoke_port",
                error: "Failed to build URL for port: \(portId)"
            )
        }
        
        #if canImport(UIKit)
        await UIApplication.shared.open(url)
        #endif
        
        return ToolResultV2.success(
            toolId: "invoke_port",
            output: "Port invoked: \(portId)\nURL: \(url.absoluteString)",
            structured: [
                "portId": portId,
                "url": url.absoluteString
            ]
        )
    }
}
