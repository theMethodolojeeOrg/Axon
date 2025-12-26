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
            return await changeModel(provider: target, model: value, reasoning: reasoning)
        case "tool":
            return changeTool(toolId: target, enabled: value.lowercased() == "enable", reasoning: reasoning)
        case "provider":
            return await changeProvider(provider: target, reasoning: reasoning)
        default:
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: "Unknown category: \(category). Use: model, tool, or provider"
            )
        }
    }
    
    // MARK: - Model Change
    
    private func changeModel(provider providerString: String, model modelId: String, reasoning: String) async -> ToolResultV2 {
        // 1. Parse provider
        guard let targetProvider = parseProvider(providerString) else {
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: "Unknown provider: \(providerString). Available: \(AIProvider.allCases.map { $0.rawValue }.joined(separator: ", "))"
            )
        }
        
        // 2. Validate model exists for this provider
        let availableModels = targetProvider.availableModels
        guard availableModels.contains(where: { $0.id == modelId }) else {
            let modelNames = availableModels.map { $0.id }.joined(separator: ", ")
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: "Model '\(modelId)' not found for \(targetProvider.displayName). Available: \(modelNames)"
            )
        }
        
        // 3. Check if this is also a provider change
        let currentProvider = settingsViewModel.settings.defaultProvider
        let isProviderChange = targetProvider != currentProvider
        
        // 4. Check sovereignty permission
        let sovereigntyService = SovereigntyService.shared
        if isProviderChange {
            if !sovereigntyService.isProviderChangeAllowed() {
                let reason = sovereigntyService.providerChangeRestrictionReason() ?? "Provider change not allowed"
                return ToolResultV2.failure(
                    toolId: "change_system_state",
                    error: reason
                )
            }
        } else {
            if !sovereigntyService.isModelChangeAllowed() {
                let reason = sovereigntyService.modelChangeRestrictionReason() ?? "Model change not allowed"
                return ToolResultV2.failure(
                    toolId: "change_system_state",
                    error: reason
                )
            }
        }
        
        // 5. Request biometric approval
        let actionDescription = isProviderChange
            ? "Change AI provider from \(currentProvider.displayName) to \(targetProvider.displayName) and model to \(modelId)"
            : "Change AI model to \(modelId)"
        
        let approvalResult = await ToolApprovalBridgeV2.shared.requestApprovalForAction(
            actionDescription: actionDescription + (reasoning.isEmpty ? "" : " (Reason: \(reasoning))"),
            toolId: "change_system_state",
            approvalScopes: isProviderChange ? ["provider_change", "model_change"] : ["model_change"]
        )
        
        guard approvalResult.isApprovedV2 else {
            let failureReason = approvalResult.failureReasonV2 ?? "User denied approval"
            logger.info("Model change denied: \(failureReason)")
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: "Change denied: \(failureReason)"
            )
        }
        
        // 6. Apply the change
        logger.info("Applying model change: \(targetProvider.rawValue) / \(modelId)")
        
        if isProviderChange {
            await settingsViewModel.updateSetting(\.defaultProvider, targetProvider)
        }
        await settingsViewModel.updateSetting(\.defaultModel, modelId)
        
        // 7. Return success
        let modelName = availableModels.first { $0.id == modelId }?.name ?? modelId
        return ToolResultV2.success(
            toolId: "change_system_state",
            output: """
            ✅ Model changed successfully.
            
            **Provider:** \(targetProvider.displayName)
            **Model:** \(modelName)
            \(reasoning.isEmpty ? "" : "**Reason:** \(reasoning)")
            
            The change is now active.
            """,
            structured: [
                "provider": targetProvider.rawValue,
                "model": modelId,
                "providerChanged": isProviderChange
            ]
        )
    }
    
    // MARK: - Provider Change
    
    private func changeProvider(provider providerString: String, reasoning: String) async -> ToolResultV2 {
        // 1. Parse provider
        guard let targetProvider = parseProvider(providerString) else {
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: "Unknown provider: \(providerString). Available: \(AIProvider.allCases.map { $0.rawValue }.joined(separator: ", "))"
            )
        }
        
        let currentProvider = settingsViewModel.settings.defaultProvider
        if targetProvider == currentProvider {
            return ToolResultV2.success(
                toolId: "change_system_state",
                output: "Already using \(targetProvider.displayName). No change needed."
            )
        }
        
        // 2. Check sovereignty permission
        let sovereigntyService = SovereigntyService.shared
        if !sovereigntyService.isProviderChangeAllowed() {
            let reason = sovereigntyService.providerChangeRestrictionReason() ?? "Provider change not allowed"
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: reason
            )
        }
        
        // 3. Request biometric approval
        let actionDescription = "Change AI provider from \(currentProvider.displayName) to \(targetProvider.displayName)"
        
        let approvalResult = await ToolApprovalBridgeV2.shared.requestApprovalForAction(
            actionDescription: actionDescription + (reasoning.isEmpty ? "" : " (Reason: \(reasoning))"),
            toolId: "change_system_state",
            approvalScopes: ["provider_change"]
        )
        
        guard approvalResult.isApprovedV2 else {
            let failureReason = approvalResult.failureReasonV2 ?? "User denied approval"
            logger.info("Provider change denied: \(failureReason)")
            return ToolResultV2.failure(
                toolId: "change_system_state",
                error: "Change denied: \(failureReason)"
            )
        }
        
        // 4. Apply the change (use first available model for the new provider)
        let defaultModel = targetProvider.availableModels.first?.id ?? ""
        
        logger.info("Applying provider change: \(targetProvider.rawValue) with model \(defaultModel)")
        
        await settingsViewModel.updateSetting(\.defaultProvider, targetProvider)
        await settingsViewModel.updateSetting(\.defaultModel, defaultModel)
        
        // 5. Return success
        return ToolResultV2.success(
            toolId: "change_system_state",
            output: """
            ✅ Provider changed successfully.
            
            **Provider:** \(targetProvider.displayName)
            **Default Model:** \(targetProvider.availableModels.first?.name ?? defaultModel)
            \(reasoning.isEmpty ? "" : "**Reason:** \(reasoning)")
            
            The change is now active.
            """,
            structured: [
                "provider": targetProvider.rawValue,
                "model": defaultModel
            ]
        )
    }
    
    // MARK: - Tool Enable/Disable (stub for now)
    
    private func changeTool(toolId: String, enabled: Bool, reasoning: String) -> ToolResultV2 {
        // Tool enable/disable is out of scope for this implementation
        return ToolResultV2.success(
            toolId: "change_system_state",
            output: """
            Tool change requested.
            
            **Tool:** \(toolId)
            **Action:** \(enabled ? "Enable" : "Disable")
            **Reason:** \(reasoning)
            
            Tool enable/disable via this interface is not yet implemented.
            """
        )
    }
    
    // MARK: - Helpers
    
    /// Parse a provider string (case-insensitive) to AIProvider
    private func parseProvider(_ name: String) -> AIProvider? {
        let lowercased = name.lowercased()
        
        // Try exact match first
        if let provider = AIProvider(rawValue: lowercased) {
            return provider
        }
        
        // Try common aliases
        switch lowercased {
        case "claude", "anthropic":
            return .anthropic
        case "gpt", "openai", "chatgpt":
            return .openai
        case "gemini", "google":
            return .gemini
        case "grok", "xai":
            return .xai
        case "perplexity", "sonar":
            return .perplexity
        case "deepseek":
            return .deepseek
        case "zai", "glm":
            return .zai
        case "minimax":
            return .minimax
        case "mistral":
            return .mistral
        case "apple", "applefoundation", "apple_foundation", "apple-foundation":
            return .appleFoundation
        case "local", "mlx", "localmlx":
            return .localMLX
        default:
            return nil
        }
    }
}
