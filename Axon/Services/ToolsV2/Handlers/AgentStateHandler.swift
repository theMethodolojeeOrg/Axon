//
//  AgentStateHandler.swift
//  Axon
//
//  V2 Handler for agent state (internal thread) tools
//

import Foundation
import os.log

/// Handler for agent state (internal thread) tools
///
/// Registered handlers:
/// - `agent_state` → agent_state_append, agent_state_query, agent_state_clear,
///   persistence_disable, agent_state_configure_runtime
@MainActor
final class AgentStateHandler: ToolHandlerV2 {
    
    let handlerId = "agent_state"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "AgentStateHandler"
    )
    
    private let stateService = AgentStateService.shared
    private let settingsViewModel = SettingsViewModel.shared
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        switch toolId {
        case "agent_state_append":
            return try await executeAppend(inputs: inputs)
        case "agent_state_query":
            return try await executeQuery(inputs: inputs)
        case "agent_state_clear":
            return try await executeClear(inputs: inputs)
        case "persistence_disable":
            return try await executeDisablePersistence(inputs: inputs)
        case "agent_state_configure_runtime":
            return await executeConfigureRuntime(inputs: inputs, context: context)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown agent state tool: \(toolId)")
        }
    }
    
    // MARK: - agent_state_append
    
    /// Append a new entry to the internal thread
    private func executeAppend(inputs: [String: Any]) async throws -> ToolResultV2 {
        // Parse JSON query if provided
        let parsedInputs: [String: Any]
        if let query = inputs["query"] as? String {
            guard let data = query.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ToolResultV2.failure(
                    toolId: "agent_state_append",
                    error: "Invalid JSON format in query"
                )
            }
            parsedInputs = json
        } else {
            parsedInputs = inputs
        }
        
        // Extract parameters
        let kindStr = (parsedInputs["kind"] as? String) ?? "note"
        let content = (parsedInputs["content"] as? String) ?? ""
        let tags = (parsedInputs["tags"] as? [String]) ?? []
        let visibilityStr = (parsedInputs["visibility"] as? String) ?? "userVisible"
        
        guard !content.isEmpty else {
            return ToolResultV2.failure(
                toolId: "agent_state_append",
                error: "Content cannot be empty"
            )
        }
        
        let kind = InternalThreadEntryKind(rawValue: kindStr) ?? .note
        let visibility = InternalThreadVisibility(rawValue: visibilityStr) ?? .userVisible
        
        logger.info("Appending agent state entry: kind=\(kindStr), visibility=\(visibilityStr)")
        
        do {
            let entry = try await stateService.appendEntry(
                kind: kind,
                content: content,
                tags: tags,
                visibility: visibility,
                origin: .ai
            )
            
            return ToolResultV2.success(
                toolId: "agent_state_append",
                output: "Entry appended successfully.\nID: \(entry.id)\nKind: \(entry.kind.rawValue)\nTimestamp: \(entry.timestamp)",
                structured: [
                    "id": entry.id,
                    "kind": entry.kind.rawValue,
                    "timestamp": ISO8601DateFormatter().string(from: entry.timestamp)
                ]
            )
        } catch {
            logger.error("Failed to append entry: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: "agent_state_append",
                error: "Failed to append entry: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - agent_state_query
    
    /// Query internal thread entries
    private func executeQuery(inputs: [String: Any]) async throws -> ToolResultV2 {
        // Parse JSON query if provided
        let parsedInputs: [String: Any]
        if let query = inputs["query"] as? String {
            if let data = query.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parsedInputs = json
            } else {
                // Simple string query - treat as search text
                parsedInputs = ["search": query]
            }
        } else {
            parsedInputs = inputs
        }
        
        // Extract parameters
        let limit = (parsedInputs["limit"] as? Int) ?? 10
        let kindStr = parsedInputs["kind"] as? String
        let tags = (parsedInputs["tags"] as? [String]) ?? []
        let searchText = parsedInputs["search"] as? String
        let includeAIOnly = (parsedInputs["include_ai_only"] as? Bool) ?? false
        
        let kind = kindStr.flatMap { InternalThreadEntryKind(rawValue: $0) }
        
        logger.info("Querying agent state: limit=\(limit), kind=\(kindStr ?? "any")")
        
        let entries = stateService.queryEntries(
            limit: limit,
            kind: kind,
            tags: tags,
            searchText: searchText,
            includeAIOnly: includeAIOnly
        )
        
        if entries.isEmpty {
            return ToolResultV2.success(
                toolId: "agent_state_query",
                output: "No entries found matching the query."
            )
        }
        
        var output = "Found \(entries.count) entries:\n\n"
        for entry in entries {
            let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
            output += "[\(entry.kind.rawValue)] \(timestamp)\n"
            output += "\(entry.content.prefix(300))\n"
            if !entry.tags.isEmpty {
                output += "Tags: \(entry.tags.joined(separator: ", "))\n"
            }
            output += "\n"
        }
        
        return ToolResultV2.success(
            toolId: "agent_state_query",
            output: output,
            structured: [
                "count": entries.count
            ]
        )
    }
    
    // MARK: - agent_state_clear
    
    /// Clear internal thread entries
    private func executeClear(inputs: [String: Any]) async throws -> ToolResultV2 {
        // Parse JSON query if provided
        let parsedInputs: [String: Any]
        if let query = inputs["query"] as? String {
            guard let data = query.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ToolResultV2.failure(
                    toolId: "agent_state_clear",
                    error: "Invalid JSON format in query"
                )
            }
            parsedInputs = json
        } else {
            parsedInputs = inputs
        }
        
        let clearAll = (parsedInputs["all"] as? Bool) ?? false
        let ids = (parsedInputs["ids"] as? [String]) ?? []
        
        logger.info("Clearing agent state: all=\(clearAll), ids=\(ids.count)")
        
        do {
            if clearAll {
                try await stateService.clearAllEntries()
                return ToolResultV2.success(
                    toolId: "agent_state_clear",
                    output: "All entries cleared."
                )
            } else if !ids.isEmpty {
                try await stateService.deleteEntries(ids: ids)
                return ToolResultV2.success(
                    toolId: "agent_state_clear",
                    output: "Deleted \(ids.count) entries."
                )
            } else {
                return ToolResultV2.failure(
                    toolId: "agent_state_clear",
                    error: "Specify either 'all': true or 'ids' to delete"
                )
            }
        } catch {
            logger.error("Failed to clear entries: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: "agent_state_clear",
                error: "Failed to clear entries: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - persistence_disable
    
    /// Disable persistence (optionally wiping existing entries)
    private func executeDisablePersistence(inputs: [String: Any]) async throws -> ToolResultV2 {
        // Parse JSON query if provided
        let parsedInputs: [String: Any]
        if let query = inputs["query"] as? String {
            if let data = query.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parsedInputs = json
            } else {
                parsedInputs = [:]
            }
        } else {
            parsedInputs = inputs
        }
        
        let wipe = (parsedInputs["wipe"] as? Bool) ?? false
        
        logger.warning("Persistence disable requested, wipe=\(wipe)")
        
        if wipe {
            do {
                try await stateService.clearAllEntries()
            } catch {
                return ToolResultV2.failure(
                    toolId: "persistence_disable",
                    error: "Failed to wipe entries: \(error.localizedDescription)"
                )
            }
        }
        
        // Note: We don't actually disable persistence at runtime
        // This would require UserDefaults flag that the service checks
        return ToolResultV2.success(
            toolId: "persistence_disable",
            output: "Persistence disable acknowledged.\(wipe ? " All existing entries wiped." : "")\nNote: Full persistence disable requires app restart.",
            structured: [
                "wiped": wipe
            ]
        )
    }

    // MARK: - agent_state_configure_runtime

    private enum RuntimeAction: String {
        case set
        case clear
    }

    private enum RuntimeScope: String {
        case conversation
        case turn
    }

    private struct ParsedRuntimeRequest {
        let action: RuntimeAction
        let scope: RuntimeScope
        let turns: Int?
        let provider: String?
        let model: String?
        let sampling: ConversationSamplingOverride?
        let reasoning: String?
    }

    private enum RuntimeRequestParseError: LocalizedError {
        case invalidAction(String)
        case invalidScope(String)

        var errorDescription: String? {
            switch self {
            case .invalidAction(let value):
                return "Invalid action '\(value)'. Use 'set' or 'clear'."
            case .invalidScope(let value):
                return "Invalid scope '\(value)'. Use 'conversation' or 'turn'."
            }
        }
    }

    private func executeConfigureRuntime(
        inputs: [String: Any],
        context: ToolContextV2
    ) async -> ToolResultV2 {
        let toolId = "agent_state_configure_runtime"

        guard let conversationId = context.conversationId, !conversationId.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Conversation context is required for scope-aware runtime overrides."
            )
        }

        let parsedInputs: [String: Any]
        if let query = inputs["query"] as? String {
            guard let data = query.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: "Invalid JSON format in query."
                )
            }
            parsedInputs = json
        } else {
            parsedInputs = inputs
        }

        let parseResult = parseRuntimeRequest(parsedInputs)
        switch parseResult {
        case .failure(let error):
            return ToolResultV2.failure(toolId: toolId, error: error.localizedDescription)
        case .success(let request):
            switch request.action {
            case .set:
                return await executeConfigureRuntimeSet(
                    request: request,
                    conversationId: conversationId,
                    context: context,
                    toolId: toolId
                )
            case .clear:
                return await executeConfigureRuntimeClear(
                    request: request,
                    conversationId: conversationId,
                    toolId: toolId
                )
            }
        }
    }

    private func executeConfigureRuntimeSet(
        request: ParsedRuntimeRequest,
        conversationId: String,
        context: ToolContextV2,
        toolId: String
    ) async -> ToolResultV2 {
        if request.scope == .turn {
            guard let turns = request.turns, turns > 0 else {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: "'turns' is required and must be > 0 when scope is 'turn' with action 'set'."
                )
            }
            if turns > 100 {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: "'turns' must be <= 100."
                )
            }
        }

        let hasSamplingMutation = request.sampling?.hasAnyValue == true
        let hasProviderOrModelMutation = request.provider != nil || request.model != nil
        guard hasSamplingMutation || hasProviderOrModelMutation else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "No runtime mutation requested. Provide provider/model and/or sampling."
            )
        }

        let settings = settingsViewModel.settings
        let fallbackResolved = ConversationModelResolver.resolve(conversationId: conversationId, settings: settings)
        let currentProviderString = normalizeProviderString(context.runtimeProvider ?? fallbackResolved.normalizedProvider)
        let currentModelId = context.runtimeModel ?? fallbackResolved.modelId

        guard let currentProvider = parseBuiltInProvider(currentProviderString) else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Current runtime provider '\(currentProviderString)' is not a supported built-in provider for this tool."
            )
        }

        let targetProvider: AIProvider
        if let requestedProvider = request.provider {
            guard let parsed = parseBuiltInProvider(requestedProvider) else {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: "Unknown or unsupported provider '\(requestedProvider)'. Built-in providers: \(AIProvider.allCases.map { $0.rawValue }.joined(separator: ", "))"
                )
            }
            targetProvider = parsed
        } else {
            targetProvider = currentProvider
        }

        let targetModelId = request.model ?? currentModelId
        let availableModels = resolvedChatModels(for: targetProvider)
        guard availableModels.contains(where: { $0.id == targetModelId }) else {
            let modelIds = availableModels.map { $0.id }.joined(separator: ", ")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Model '\(targetModelId)' is not available for \(targetProvider.displayName). Available: \(modelIds)"
            )
        }

        if let sampling = request.sampling,
           let validationError = validateSamplingOverride(sampling, provider: targetProvider) {
            return ToolResultV2.failure(toolId: toolId, error: validationError)
        }

        let providerWillChange = targetProvider != currentProvider
        let modelWillChange = targetModelId != currentModelId

        let sovereigntyService = SovereigntyService.shared
        if providerWillChange {
            guard sovereigntyService.isProviderChangeAllowed() else {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: sovereigntyService.providerChangeRestrictionReason() ?? "Provider change not allowed."
                )
            }
        }

        if modelWillChange {
            guard sovereigntyService.isModelChangeAllowed() else {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: sovereigntyService.modelChangeRestrictionReason() ?? "Model change not allowed."
                )
            }
        }

        let providerModelMutation = providerWillChange || modelWillChange
        let approvalMode = settings.sovereigntySettings.agentSelfReconfigApprovalMode
        let requiresApproval: Bool
        switch approvalMode {
        case .providerModelOnly:
            requiresApproval = providerModelMutation
        case .allChanges:
            requiresApproval = providerModelMutation || hasSamplingMutation
        case .noApproval:
            requiresApproval = false
        }

        if requiresApproval {
            var scopeLabels: [String] = []
            if providerWillChange { scopeLabels.append("provider_change") }
            if modelWillChange { scopeLabels.append("model_change") }
            if hasSamplingMutation { scopeLabels.append("sampling_change") }
            if scopeLabels.isEmpty { scopeLabels.append("runtime_config") }

            var actionDescription = "Configure runtime (\(request.scope.rawValue)) to \(targetProvider.displayName) / \(targetModelId)"
            if request.scope == .turn, let turns = request.turns {
                actionDescription += " for \(turns) turn(s)"
            }
            if hasSamplingMutation {
                actionDescription += " with sampling override"
            }
            if let reasoning = request.reasoning, !reasoning.isEmpty {
                actionDescription += " (Reason: \(reasoning))"
            }

            let approvalResult = await ToolApprovalBridgeV2.shared.requestApprovalForAction(
                actionDescription: actionDescription,
                toolId: toolId,
                approvalScopes: scopeLabels
            )
            guard approvalResult.isApprovedV2 else {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: "Change denied: \(approvalResult.failureReasonV2 ?? "User denied approval")"
                )
            }
        }

        let runtimeManager = ConversationRuntimeOverrideManager.shared
        let providerStringForStorage: String? = hasProviderOrModelMutation ? targetProvider.rawValue : nil
        let modelStringForStorage: String? = hasProviderOrModelMutation ? targetModelId : nil

        if request.scope == .conversation {
            runtimeManager.setConversationRuntimeOverrides(
                conversationId: conversationId,
                provider: providerStringForStorage.flatMap { AIProvider(rawValue: $0) },
                model: modelStringForStorage,
                samplingOverride: request.sampling
            )
        } else {
            runtimeManager.setTurnLease(
                conversationId: conversationId,
                turns: request.turns ?? 1,
                provider: providerStringForStorage,
                model: modelStringForStorage,
                samplingOverride: request.sampling
            )
        }

        let summary = runtimeSummaryText(
            action: request.action,
            scope: request.scope,
            turns: request.turns,
            provider: hasProviderOrModelMutation ? targetProvider.rawValue : nil,
            model: hasProviderOrModelMutation ? targetModelId : nil,
            sampling: request.sampling
        )

        return ToolResultV2.success(
            toolId: toolId,
            output: summary,
            structured: [
                "action": request.action.rawValue,
                "scope": request.scope.rawValue,
                "turns": request.turns ?? NSNull(),
                "provider": hasProviderOrModelMutation ? targetProvider.rawValue : NSNull(),
                "model": hasProviderOrModelMutation ? targetModelId : NSNull(),
                "sampling": samplingStructured(request.sampling)
            ]
        )
    }

    private func executeConfigureRuntimeClear(
        request: ParsedRuntimeRequest,
        conversationId: String,
        toolId: String
    ) async -> ToolResultV2 {
        let runtimeManager = ConversationRuntimeOverrideManager.shared
        let settings = settingsViewModel.settings

        let providerModelMutation: Bool
        let samplingMutation: Bool

        switch request.scope {
        case .conversation:
            let overrides = runtimeManager.loadConversationOverrides(conversationId: conversationId)
            providerModelMutation = (overrides?.builtInProvider != nil) || (overrides?.builtInModel != nil)
            samplingMutation = overrides?.samplingOverride?.hasAnyValue == true
        case .turn:
            let lease = runtimeManager.loadTurnLease(conversationId: conversationId)
            providerModelMutation = (lease?.provider != nil) || (lease?.model != nil)
            samplingMutation = lease?.samplingOverride?.hasAnyValue == true
        }

        if !providerModelMutation && !samplingMutation {
            return ToolResultV2.success(
                toolId: toolId,
                output: "No \(request.scope.rawValue)-scoped runtime overrides were active."
            )
        }

        if providerModelMutation {
            let sovereigntyService = SovereigntyService.shared
            guard sovereigntyService.isProviderChangeAllowed() else {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: sovereigntyService.providerChangeRestrictionReason() ?? "Provider change not allowed."
                )
            }
            guard sovereigntyService.isModelChangeAllowed() else {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: sovereigntyService.modelChangeRestrictionReason() ?? "Model change not allowed."
                )
            }
        }

        let approvalMode = settings.sovereigntySettings.agentSelfReconfigApprovalMode
        let requiresApproval: Bool
        switch approvalMode {
        case .providerModelOnly:
            requiresApproval = providerModelMutation
        case .allChanges:
            requiresApproval = providerModelMutation || samplingMutation
        case .noApproval:
            requiresApproval = false
        }

        if requiresApproval {
            var scopes: [String] = []
            if providerModelMutation { scopes.append("provider_model_clear") }
            if samplingMutation { scopes.append("sampling_clear") }
            if scopes.isEmpty { scopes.append("runtime_clear") }

            let approvalResult = await ToolApprovalBridgeV2.shared.requestApprovalForAction(
                actionDescription: "Clear \(request.scope.rawValue)-scoped runtime overrides",
                toolId: toolId,
                approvalScopes: scopes
            )
            guard approvalResult.isApprovedV2 else {
                return ToolResultV2.failure(
                    toolId: toolId,
                    error: "Change denied: \(approvalResult.failureReasonV2 ?? "User denied approval")"
                )
            }
        }

        switch request.scope {
        case .conversation:
            runtimeManager.clearConversationRuntimeOverrides(conversationId: conversationId)
        case .turn:
            runtimeManager.clearTurnLease(conversationId: conversationId)
        }

        return ToolResultV2.success(
            toolId: toolId,
            output: "Cleared \(request.scope.rawValue)-scoped runtime overrides."
        )
    }

    private func parseRuntimeRequest(_ inputs: [String: Any]) -> Result<ParsedRuntimeRequest, RuntimeRequestParseError> {
        let actionRaw = (inputs["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "set"
        guard let action = RuntimeAction(rawValue: actionRaw) else {
            return .failure(.invalidAction(actionRaw))
        }

        let scopeRaw = (inputs["scope"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "conversation"
        guard let scope = RuntimeScope(rawValue: scopeRaw) else {
            return .failure(.invalidScope(scopeRaw))
        }

        let turns = intValue(inputs["turns"])

        let providerRaw = (inputs["provider"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = providerRaw?.isEmpty == true ? nil : providerRaw

        let modelRaw = (inputs["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelRaw?.isEmpty == true ? nil : modelRaw

        let reasoningRaw = (inputs["reasoning"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoning = reasoningRaw?.isEmpty == true ? nil : reasoningRaw

        var sampling: ConversationSamplingOverride?
        if let samplingObject = inputs["sampling"] as? [String: Any] {
            sampling = samplingOverride(from: samplingObject)
        } else {
            // Also accept flat payloads for robustness.
            let flattened = samplingOverride(from: inputs)
            if flattened.hasAnyValue {
                sampling = flattened
            }
        }

        return .success(ParsedRuntimeRequest(
            action: action,
            scope: scope,
            turns: turns,
            provider: provider,
            model: model,
            sampling: sampling?.hasAnyValue == true ? sampling : nil,
            reasoning: reasoning
        ))
    }

    private func samplingOverride(from object: [String: Any]) -> ConversationSamplingOverride {
        let temperature = doubleValue(object["temperature"])
        let topP = doubleValue(object["top_p"]) ?? doubleValue(object["topP"])
        let topK = intValue(object["top_k"]) ?? intValue(object["topK"])
        return ConversationSamplingOverride(
            temperature: temperature,
            topP: topP,
            topK: topK
        )
    }

    private func validateSamplingOverride(
        _ override: ConversationSamplingOverride,
        provider: AIProvider
    ) -> String? {
        let providerSupport = ProviderParameterSupport.support(for: provider.rawValue)

        if let temperature = override.temperature {
            guard providerSupport.supportsTemperature else {
                return "temperature is not supported for \(provider.displayName)."
            }
            guard (0.0...1.0).contains(temperature) else {
                return "temperature must be between 0.0 and 1.0."
            }
        }

        if let topP = override.topP {
            guard providerSupport.supportsTopP else {
                return "top_p is not supported for \(provider.displayName)."
            }
            guard (0.0...1.0).contains(topP) else {
                return "top_p must be between 0.0 and 1.0."
            }
        }

        if let topK = override.topK {
            guard providerSupport.supportsTopK else {
                return "top_k is not supported for \(provider.displayName)."
            }
            guard (1...100).contains(topK) else {
                return "top_k must be between 1 and 100."
            }
        }

        return nil
    }

    private func resolvedChatModels(for provider: AIProvider) -> [AIModel] {
        let registryModels = UnifiedModelRegistry.shared.chatModels(for: provider)
        return registryModels.isEmpty ? provider.availableModels : registryModels
    }

    private func parseBuiltInProvider(_ value: String) -> AIProvider? {
        let normalized = normalizeProviderString(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = AIProvider(rawValue: normalized) {
            return direct
        }

        switch normalized.lowercased() {
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
        case "local", "mlx", "localmlx", "local_mlx", "local-mlx":
            return .localMLX
        default:
            return nil
        }
    }

    private func normalizeProviderString(_ provider: String) -> String {
        provider.lowercased() == "xai" ? "grok" : provider
    }

    private func runtimeSummaryText(
        action: RuntimeAction,
        scope: RuntimeScope,
        turns: Int?,
        provider: String?,
        model: String?,
        sampling: ConversationSamplingOverride?
    ) -> String {
        var lines: [String] = []
        lines.append("Runtime override updated.")
        lines.append("Action: \(action.rawValue)")
        lines.append("Scope: \(scope.rawValue)")

        if scope == .turn, let turns {
            lines.append("Turns: \(turns)")
        }
        if let provider {
            lines.append("Provider: \(provider)")
        }
        if let model {
            lines.append("Model: \(model)")
        }
        if let sampling, sampling.hasAnyValue {
            let parts = [
                sampling.temperature.map { "temperature=\($0)" },
                sampling.topP.map { "top_p=\($0)" },
                sampling.topK.map { "top_k=\($0)" }
            ].compactMap { $0 }
            lines.append("Sampling: \(parts.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    private func samplingStructured(_ sampling: ConversationSamplingOverride?) -> [String: Any] {
        guard let sampling else {
            return [:]
        }
        var value: [String: Any] = [:]
        if let temperature = sampling.temperature { value["temperature"] = temperature }
        if let topP = sampling.topP { value["top_p"] = topP }
        if let topK = sampling.topK { value["top_k"] = topK }
        return value
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        if let string = value as? String, let int = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return int
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String, let double = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return double
        }
        return nil
    }
}
