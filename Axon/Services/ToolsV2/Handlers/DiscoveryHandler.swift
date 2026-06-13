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
/// - `discovery` → list_tools, get_tool_details, get_runtime_catalog, discover_ports, invoke_port
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
        case "get_runtime_catalog":
            return executeGetRuntimeCatalog(inputs: inputs)
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
            output += renderParameters(params)
        }
        output += renderAIGuidance(manifest.ai)

        var structured: [String: Any] = [
            "id": manifest.tool.id,
            "name": manifest.tool.name
        ]

        if manifest.tool.id == "agent_state_configure_runtime" {
            output += "\n## Runtime Catalog\n\n"
            output += "Call `get_runtime_catalog` to inspect current provider/model availability, key/device/download status, and `usableNow` values.\n"
            structured["runtimeCatalogTool"] = "get_runtime_catalog"
        }
        
        return ToolResultV2.success(
            toolId: "get_tool_details",
            output: output,
            structured: structured
        )
    }

    // MARK: - get_runtime_catalog

    private struct RuntimeCatalogRequest {
        let provider: String?
        let usableOnly: Bool
        let includeModels: Bool
    }

    private func executeGetRuntimeCatalog(inputs: [String: Any]) -> ToolResultV2 {
        let request = parseRuntimeCatalogRequest(inputs)
        let catalog = AgentRuntimeCatalog.snapshot()
        let validProviderIds = catalog.providers.map(\.id).sorted()

        var providers = catalog.providers
        if let provider = request.provider, !provider.isEmpty {
            guard validProviderIds.contains(provider) else {
                return ToolResultV2.failure(
                    toolId: "get_runtime_catalog",
                    error: "Unknown provider '\(provider)'. Valid providers: \(validProviderIds.joined(separator: ", "))"
                )
            }
            providers = providers.filter { $0.id == provider }
        }

        if request.usableOnly {
            providers = providers
                .filter(\.usableNow)
                .map { provider in
                    AgentRuntimeCatalog.ProviderStatus(
                        id: provider.id,
                        displayName: provider.displayName,
                        configuredKey: provider.configuredKey,
                        deviceAvailable: provider.deviceAvailable,
                        modelExists: provider.modelExists,
                        usableNow: provider.usableNow,
                        unavailableReason: provider.unavailableReason,
                        models: provider.models.filter(\.usableNow)
                    )
                }
        }

        let output = renderRuntimeCatalog(
            providers: providers,
            includeModels: request.includeModels,
            usableOnly: request.usableOnly,
            providerFilter: request.provider
        )

        return ToolResultV2.success(
            toolId: "get_runtime_catalog",
            output: output,
            structured: [
                "runtimeOptions": [
                    "providerFilter": request.provider.map { $0 as Any } ?? NSNull(),
                    "usableOnly": request.usableOnly,
                    "includeModels": request.includeModels,
                    "providers": providers.map { runtimeProviderStructured($0, includeModels: request.includeModels) }
                ]
            ]
        )
    }

    private func renderParameters(_ params: [String: ToolParameterV2]) -> String {
        var output = "\n## Parameters\n\n"
        for (name, param) in params.sorted(by: { $0.key < $1.key }) {
            let required = param.isRequired ? "*" : ""
            output += "- **\(name)\(required)** (\(param.type.rawValue)): \(param.description ?? "")\n"
            output += renderParameterDetails(param, indent: "  ")
        }
        return output
    }

    private func renderParameterDetails(_ param: ToolParameterV2, indent: String) -> String {
        var output = ""

        if let enumValues = param.`enum`, !enumValues.isEmpty {
            if let descriptions = param.enumDescriptions, !descriptions.isEmpty {
                for value in enumValues {
                    if let description = descriptions[value] {
                        output += "\(indent)- `\(value)` - \(description)\n"
                    } else {
                        output += "\(indent)- `\(value)`\n"
                    }
                }
            } else {
                output += "\(indent)- allowed: \(enumValues.map { "`\($0)`" }.joined(separator: ", "))\n"
            }
        }

        if let defaultValue = param.defaultValue {
            output += "\(indent)- default: `\(formatAnyCodable(defaultValue))`\n"
        }

        if let min = param.minimum, let max = param.maximum {
            output += "\(indent)- range: \(formatNumber(min))-\(formatNumber(max))\n"
        } else if let min = param.minimum {
            output += "\(indent)- min: \(formatNumber(min))\n"
        } else if let max = param.maximum {
            output += "\(indent)- max: \(formatNumber(max))\n"
        }

        if let minLength = param.minLength, let maxLength = param.maxLength {
            output += "\(indent)- length: \(minLength)-\(maxLength)\n"
        } else if let minLength = param.minLength {
            output += "\(indent)- minLength: \(minLength)\n"
        } else if let maxLength = param.maxLength {
            output += "\(indent)- maxLength: \(maxLength)\n"
        }

        if let pattern = param.pattern {
            output += "\(indent)- pattern: `\(pattern)`\n"
        }

        if let minItems = param.minItems, let maxItems = param.maxItems {
            output += "\(indent)- items: \(minItems)-\(maxItems)\n"
        } else if let minItems = param.minItems {
            output += "\(indent)- minItems: \(minItems)\n"
        } else if let maxItems = param.maxItems {
            output += "\(indent)- maxItems: \(maxItems)\n"
        }

        if let item = param.items {
            output += "\(indent)- item type: \(item.type.rawValue)\n"
            output += renderParameterDetails(item, indent: indent + "  ")
        }

        if let properties = param.properties, !properties.isEmpty {
            output += "\(indent)- properties:\n"
            for (propertyName, property) in properties.sorted(by: { $0.key < $1.key }) {
                let required = property.isRequired ? "*" : ""
                let description = property.description.map { ": \($0)" } ?? ""
                output += "\(indent)  - `\(propertyName)\(required)` (\(property.type.rawValue))\(description)\n"
                output += renderParameterDetails(property, indent: indent + "    ")
            }
        }

        return output
    }

    private func renderAIGuidance(_ ai: ToolAIConfig?) -> String {
        guard let ai else { return "" }

        var output = ""
        if let examples = ai.usageExamples, !examples.isEmpty {
            output += "\n## Examples\n\n"
            for example in examples {
                output += "- \(example.description):\n"
                output += "  ```json\n"
                output += indentBlock(example.input, by: "  ")
                output += "\n  ```\n"
                if let expectedOutput = example.expectedOutput, !expectedOutput.isEmpty {
                    output += "  Expected: \(expectedOutput)\n"
                }
            }
        }

        if let whenToUse = ai.whenToUse, !whenToUse.isEmpty {
            output += "\n## When to use\n\n"
            for item in whenToUse {
                output += "- \(item)\n"
            }
        }

        if let whenNotToUse = ai.whenNotToUse, !whenNotToUse.isEmpty {
            output += "\n## When NOT to use\n\n"
            for item in whenNotToUse {
                output += "- \(item)\n"
            }
        }

        if let systemPromptSection = ai.systemPromptSection, !systemPromptSection.isEmpty {
            output += "\n## System prompt guidance\n\n"
            output += systemPromptSection
            output += "\n"
        }

        return output
    }

    private func parseRuntimeCatalogRequest(_ inputs: [String: Any]) -> RuntimeCatalogRequest {
        var parsedInputs = inputs
        if let query = inputs["query"] as? String {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{"),
               let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parsedInputs = json
            } else if !trimmed.isEmpty {
                parsedInputs["provider"] = trimmed
            }
        }

        let provider = (parsedInputs["provider"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return RuntimeCatalogRequest(
            provider: provider?.isEmpty == true ? nil : provider,
            usableOnly: boolValue(parsedInputs["usable_only"]) ?? false,
            includeModels: boolValue(parsedInputs["include_models"]) ?? true
        )
    }

    private func renderRuntimeCatalog(
        providers: [AgentRuntimeCatalog.ProviderStatus],
        includeModels: Bool,
        usableOnly: Bool,
        providerFilter: String?
    ) -> String {
        var lines: [String] = []
        lines.append("# Runtime Catalog")
        lines.append("")
        lines.append("Use these provider/model ids with `agent_state_configure_runtime`. `usableNow` reflects configured local state.")
        if let providerFilter {
            lines.append("- provider filter: `\(providerFilter)`")
        }
        lines.append("- usable_only: \(usableOnly)")
        lines.append("- include_models: \(includeModels)")
        lines.append("")

        guard !providers.isEmpty else {
            lines.append("No runtime providers matched the requested filters.")
            return lines.joined(separator: "\n")
        }

        for provider in providers {
            let status = provider.usableNow ? "usable" : "unavailable"
            let reason = provider.unavailableReason.map { " - \($0)" } ?? ""
            lines.append("## \(provider.displayName) (`\(provider.id)`) - \(status)\(reason)")
            lines.append("- configuredKey: \(provider.configuredKey)")
            lines.append("- deviceAvailable: \(provider.deviceAvailable)")
            lines.append("- modelExists: \(provider.modelExists)")
            lines.append("- usableNow: \(provider.usableNow)")

            if includeModels {
                lines.append("- models:")
                if provider.models.isEmpty {
                    lines.append("  - none")
                } else {
                    for model in provider.models {
                        let modelStatus = model.usableNow ? "usable" : "unavailable"
                        let modelReason = model.unavailableReason.map { " - \($0)" } ?? ""
                        lines.append("  - `\(model.id)` (\(model.name)): \(modelStatus)\(modelReason)")
                    }
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func runtimeProviderStructured(
        _ provider: AgentRuntimeCatalog.ProviderStatus,
        includeModels: Bool
    ) -> [String: Any] {
        var structured: [String: Any] = [
            "id": provider.id,
            "displayName": provider.displayName,
            "configuredKey": provider.configuredKey,
            "deviceAvailable": provider.deviceAvailable,
            "modelExists": provider.modelExists,
            "usableNow": provider.usableNow,
            "unavailableReason": provider.unavailableReason.map { $0 as Any } ?? NSNull()
        ]

        if includeModels {
            structured["models"] = provider.models.map(\.structured)
        }

        return structured
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func formatAnyCodable(_ value: AnyCodableV2) -> String {
        switch value.value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return "\(int)"
        case let double as Double:
            return formatNumber(double)
        case let array as [Any]:
            return formatJSON(array)
        case let dict as [String: Any]:
            return formatJSON(dict)
        default:
            return "\(value.value)"
        }
    }

    private func formatJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "\(value)"
        }
        return string
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return "\(value)"
    }

    private func indentBlock(_ text: String, by indent: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { indent + $0 }
            .joined(separator: "\n")
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
