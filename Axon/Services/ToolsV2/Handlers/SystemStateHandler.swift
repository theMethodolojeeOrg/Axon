//
//  SystemStateHandler.swift
//  Axon
//
//  V2 Handler for system state query and modification tools
//

import Foundation
import os.log

// MARK: - Lightweight Codable for Reading Overrides

/// Minimal struct for decoding per-conversation overrides
/// Mirrors relevant fields from ConversationOverrides in ChatInfoSettingsView
private struct ConversationOverridesForQuery: Codable {
    var builtInProvider: String?
    var customProviderId: UUID?
    var builtInModel: String?
    var customModelId: UUID?
    var providerDisplayName: String?
    var modelDisplayName: String?
}

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
            return executeQuerySystemState(inputs: inputs, context: context)
        case "change_system_state":
            return try await executeChangeSystemState(inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown system state tool: \(toolId)")
        }
    }

    // MARK: - query_system_state

    private func executeQuerySystemState(inputs: [String: Any], context: ToolContextV2) -> ToolResultV2 {
        let scope = (inputs["query"] as? String)?.lowercased() ?? "current"

        logger.info("Querying system state: \(scope), conversationId: \(context.conversationId ?? "none")")

        let settings = settingsViewModel.settings

        switch scope {
        case "current":
            return queryCurrentState(settings, context: context)
        case "providers":
            return queryProviders(settings)
        case "tools":
            return queryTools()
        case "permissions":
            return queryPermissions()
        case "all":
            return queryAllState(settings, context: context)
        default:
            return queryCurrentState(settings, context: context)
        }
    }

    // MARK: - Per-Conversation Override Resolution

    /// Resolves the effective provider and model for the current context
    /// Checks per-conversation overrides first, then falls back to global settings
    private func resolveEffectiveProviderAndModel(
        globalSettings: AppSettings,
        context: ToolContextV2
    ) -> (providerName: String, modelName: String, isOverridden: Bool) {
        // Check for per-conversation overrides
        if let conversationId = context.conversationId {
            let key = "conversation_overrides_\(conversationId)"
            if let data = UserDefaults.standard.data(forKey: key),
               let overrides = try? JSONDecoder().decode(ConversationOverridesForQuery.self, from: data) {

                // Determine provider display name
                var providerName: String?
                if let displayName = overrides.providerDisplayName {
                    providerName = displayName
                } else if let builtInProvider = overrides.builtInProvider,
                          let provider = AIProvider(rawValue: builtInProvider) {
                    providerName = provider.displayName
                } else if let customProviderId = overrides.customProviderId {
                    // Custom provider - try to get from settings
                    if let customProvider = globalSettings.customProviders.first(where: { $0.id == customProviderId }) {
                        providerName = customProvider.providerName
                    }
                }

                // Determine model display name
                var modelName: String?
                if let displayName = overrides.modelDisplayName {
                    modelName = displayName
                } else if let builtInModel = overrides.builtInModel {
                    modelName = builtInModel
                }

                // If we found overrides, use them
                if let provider = providerName, let model = modelName {
                    logger.info("Using per-conversation override: \(provider) / \(model)")
                    return (provider, model, true)
                } else if let provider = providerName {
                    // Have provider override but no model - use provider with default model
                    logger.info("Using per-conversation provider override: \(provider)")
                    return (provider, overrides.builtInModel ?? globalSettings.defaultModel, true)
                }
            }
        }

        // Fall back to global settings
        return (globalSettings.defaultProvider.displayName, globalSettings.defaultModel, false)
    }

    private func queryCurrentState(_ settings: AppSettings, context: ToolContextV2) -> ToolResultV2 {
        // Use runtime context if available (actual provider/model serving this response)
        let providerName: String
        let modelName: String
        let isRuntime: Bool
        let isOverridden: Bool
        
        if let runtimeProvider = context.runtimeProvider, let runtimeModel = context.runtimeModel {
            // Runtime context available - this is the actual provider/model
            providerName = runtimeProvider
            modelName = runtimeModel
            isRuntime = true
            isOverridden = false
            logger.info("Using runtime context: provider=\(runtimeProvider), model=\(runtimeModel)")
        } else {
            // Fall back to settings-based resolution
            let resolved = resolveEffectiveProviderAndModel(globalSettings: settings, context: context)
            providerName = resolved.providerName
            modelName = resolved.modelName
            isOverridden = resolved.isOverridden
            isRuntime = false
            logger.info("Using settings fallback: provider=\(providerName), model=\(modelName)")
        }

        var output = "# Current System State\n\n"
        output += "**Provider:** \(providerName)\n"
        output += "**Model:** \(modelName)\n"
        if isRuntime {
            output += "**Source:** Runtime (live request context)\n"
        } else if isOverridden {
            output += "**Note:** Using per-conversation override\n"
        }
        output += "**Orchestration:** \(settings.useOnDeviceOrchestration ? "Enabled" : "Disabled")\n"
        output += "**Internal Thread:** \(settings.internalThreadEnabled ? "Enabled" : "Disabled")\n"
        output += "**Heartbeat:** \(settings.heartbeatSettings.enabled ? "Enabled" : "Disabled")\n"

        return ToolResultV2.success(
            toolId: "query_system_state",
            output: output,
            structured: [
                "provider": providerName,
                "model": modelName,
                "isOverridden": isOverridden,
                "isRuntime": isRuntime
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
    
    private func queryAllState(_ settings: AppSettings, context: ToolContextV2) -> ToolResultV2 {
        // Use runtime context if available (actual provider/model serving this response)
        let providerName: String
        let modelName: String
        let isRuntime: Bool
        let isOverridden: Bool
        
        if let runtimeProvider = context.runtimeProvider, let runtimeModel = context.runtimeModel {
            providerName = runtimeProvider
            modelName = runtimeModel
            isRuntime = true
            isOverridden = false
        } else {
            let resolved = resolveEffectiveProviderAndModel(globalSettings: settings, context: context)
            providerName = resolved.providerName
            modelName = resolved.modelName
            isOverridden = resolved.isOverridden
            isRuntime = false
        }

        var output = "# Full System State\n\n"

        // Current config
        output += "## Configuration\n"
        output += "- Provider: \(providerName)\n"
        output += "- Model: \(modelName)\n"
        if isRuntime {
            output += "- Source: Runtime (live request context)\n"
        } else if isOverridden {
            output += "- Note: Using per-conversation override\n"
        }
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
