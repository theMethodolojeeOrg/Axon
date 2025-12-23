//
//  SystemStateHandler.swift
//  Axon
//
//  V2 Handler for system state query and modification tools
//

import Foundation
import os.log

/// Handler for system state tools
///
/// Registered handlers:
/// - `system_state` → query_system_state, change_system_state
@MainActor
final class SystemStateHandler: ToolHandlerV2 {
    
    let handlerId = "system_state"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "SystemStateHandler"
    )
    
    private let settingsViewModel = SettingsViewModel.shared
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        switch toolId {
        case "query_system_state":
            return executeQuerySystemState(inputs: inputs)
        case "change_system_state":
            return try await executeChangeSystemState(inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown system state tool: \(toolId)")
        }
    }
    
    // MARK: - query_system_state
    
    private func executeQuerySystemState(inputs: [String: Any]) -> ToolResultV2 {
        let scope = (inputs["query"] as? String)?.lowercased() ?? "current"
        
        logger.info("Querying system state: \(scope)")
        
        let settings = settingsViewModel.settings
        
        switch scope {
        case "current":
            return queryCurrentState(settings)
        case "providers":
            return queryProviders(settings)
        case "tools":
            return queryTools()
        case "permissions":
            return queryPermissions()
        case "all":
            return queryAllState(settings)
        default:
            return queryCurrentState(settings)
        }
    }
    
    private func queryCurrentState(_ settings: AppSettings) -> ToolResultV2 {
        var output = "# Current System State\n\n"
        output += "**Provider:** \(settings.defaultProvider.displayName)\n"
        output += "**Model:** \(settings.defaultModel)\n"
        output += "**Orchestration:** \(settings.useOnDeviceOrchestration ? "Enabled" : "Disabled")\n"
        output += "**Internal Thread:** \(settings.internalThreadEnabled ? "Enabled" : "Disabled")\n"
        output += "**Heartbeat:** \(settings.heartbeatSettings.enabled ? "Enabled" : "Disabled")\n"
        
        return ToolResultV2.success(
            toolId: "query_system_state",
            output: output,
            structured: [
                "provider": settings.defaultProvider.rawValue,
                "model": settings.defaultModel
            ]
        )
    }
    
    private func queryProviders(_ settings: AppSettings) -> ToolResultV2 {
        var output = "# Available Providers\n\n"
        
        for provider in AIProvider.allCases {
            let isCurrent = provider == settings.defaultProvider
            let icon = isCurrent ? "✅" : "○"
            output += "\(icon) **\(provider.displayName)**\n"
        }
        
        return ToolResultV2.success(
            toolId: "query_system_state",
            output: output
        )
    }
    
    private func queryTools() -> ToolResultV2 {
        let tools = ToolPluginLoader.shared.loadedTools
        // LoadedTool doesn't have a direct enabled property - just count all tools
        let totalCount = tools.count
        
        var output = "# Tool Status\n\n"
        output += "**Total Loaded:** \(totalCount)\n"
        
        return ToolResultV2.success(
            toolId: "query_system_state",
            output: output,
            structured: [
                "totalTools": totalCount
            ]
        )
    }
    
    private func queryPermissions() -> ToolResultV2 {
        let hasCovenant = SovereigntyService.shared.activeCovenant != nil
        
        var output = "# Permissions\n\n"
        output += "**Co-Sovereignty:** \(hasCovenant ? "Active" : "Not established")\n"
        
        return ToolResultV2.success(
            toolId: "query_system_state",
            output: output
        )
    }
    
    private func queryAllState(_ settings: AppSettings) -> ToolResultV2 {
        var output = "# Full System State\n\n"
        
        // Current config
        output += "## Configuration\n"
        output += "- Provider: \(settings.defaultProvider.displayName)\n"
        output += "- Model: \(settings.defaultModel)\n"
        output += "- Orchestration: \(settings.useOnDeviceOrchestration)\n\n"
        
        // Tools
        let tools = ToolPluginLoader.shared.loadedTools
        output += "## Tools\n"
        output += "- Total Loaded: \(tools.count)\n\n"
        
        // Sovereignty
        output += "## Co-Sovereignty\n"
        output += "- Active: \(SovereigntyService.shared.activeCovenant != nil)\n"
        
        return ToolResultV2.success(
            toolId: "query_system_state",
            output: output
        )
    }
    
    // MARK: - change_system_state
    
    private func executeChangeSystemState(inputs: [String: Any]) async throws -> ToolResultV2 {
        guard let query = inputs["query"] as? String else {
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: "Missing query. Format: CATEGORY|TARGET|VALUE|REASONING"
            )
        }
        
        let parts = query.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else {
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: "Invalid format. Expected: CATEGORY|TARGET|VALUE|REASONING"
            )
        }
        
        let category = parts[0].lowercased()
        let target = parts[1]
        let value = parts[2]
        let reasoning = parts.count > 3 ? parts[3] : ""
        
        logger.info("Changing system state: \(category)|\(target)|\(value)")
        
        switch category {
        case "model":
            return changeModel(provider: target, model: value, reasoning: reasoning)
        case "tool":
            return changeTool(toolId: target, enabled: value.lowercased() == "enable", reasoning: reasoning)
        case "provider":
            return changeProvider(provider: target, reasoning: reasoning)
        default:
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: "Unknown category: \(category). Use: model, tool, or provider"
            )
        }
    }
    
    private func changeModel(provider: String, model: String, reasoning: String) -> ToolResultV2 {
        // Note: Full implementation would require biometric approval
        // For now, just acknowledge the request
        
        return ToolResultV2.success(
            toolId: "change_system_state",
            output: """
            Model change requested.
            
            **Provider:** \(provider)
            **Model:** \(model)
            **Reason:** \(reasoning)
            
            This change requires user approval.
            """
        )
    }
    
    private func changeTool(toolId: String, enabled: Bool, reasoning: String) -> ToolResultV2 {
        return ToolResultV2.success(
            toolId: "change_system_state",
            output: """
            Tool change requested.
            
            **Tool:** \(toolId)
            **Action:** \(enabled ? "Enable" : "Disable")
            **Reason:** \(reasoning)
            
            This change requires user approval.
            """
        )
    }
    
    private func changeProvider(provider: String, reasoning: String) -> ToolResultV2 {
        return ToolResultV2.success(
            toolId: "change_system_state",
            output: """
            Provider change requested.
            
            **Provider:** \(provider)
            **Reason:** \(reasoning)
            
            This change requires user approval.
            """
        )
    }
}
