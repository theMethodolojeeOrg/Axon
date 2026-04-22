//
//  AxonControlHandler.swift
//  Axon
//
//  Internal handler exposing native Axon app-control actions.
//

import Foundation
import os.log

@MainActor
final class AxonControlHandler: ToolHandlerV2 {

    let handlerId = "axon_control"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "AxonControlHandler"
    )

    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        switch manifest.tool.id {
        case "axon_discover_actions":
            return executeDiscoverActions(inputs: inputs)
        case "axon_invoke_action":
            return await executeInvokeAction(inputs: inputs, context: context)
        case "axon_get_state":
            return await executeGetState()
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown Axon control tool: \(manifest.tool.id)")
        }
    }

    private func executeDiscoverActions(inputs: [String: Any]) -> ToolResultV2 {
        let filter = stringValue("filter", from: inputs) ?? stringValue("query", from: inputs)
        let platform = stringValue("platform", from: inputs)
        let view = stringValue("view", from: inputs)

        let actions = AgentActionRegistry.shared.discoverActions(
            filter: filter,
            platform: platform,
            view: view
        )

        let lines = actions.map { descriptor in
            "- `\(descriptor.id)` (\(descriptor.group))\(descriptor.requiresApproval ? " [approval]" : "")"
        }

        let output = """
        Axon actions (\(actions.count)):
        \(lines.joined(separator: "\n"))
        """

        let structuredActions = actions.map { descriptor in
            [
                "id": descriptor.id,
                "title": descriptor.title,
                "group": descriptor.group,
                "requires_approval": descriptor.requiresApproval
            ] as [String: Any]
        }

        return ToolResultV2.success(
            toolId: "axon_discover_actions",
            output: output,
            structured: [
                "count": actions.count,
                "actions": structuredActions
            ]
        )
    }

    private func executeInvokeAction(
        inputs: [String: Any],
        context: ToolContextV2
    ) async -> ToolResultV2 {
        guard let actionId = resolveActionId(inputs: inputs) else {
            return ToolResultV2.failure(
                toolId: "axon_invoke_action",
                error: "Missing required parameter: action_id"
            )
        }

        let params = resolveActionParams(inputs: inputs)
        let actionContext = AgentActionContext(
            source: "internal_tool",
            sessionId: context.conversationId,
            actor: context.userId ?? "assistant",
            view: nil
        )

        logger.info("Invoking Axon action: \(actionId)")

        let result = await AgentActionRegistry.shared.invokeAction(
            id: actionId,
            params: params,
            context: actionContext
        )

        var structured: [String: Any] = [
            "action_id": actionId,
            "success": result.success,
            "message": result.message
        ]
        if let errorCode = result.errorCode {
            structured["error_code"] = errorCode
        }
        if let data = result.data {
            structured["data"] = data.mapValues { AgentActionRegistry.foundationValue(from: $0) }
        }

        if result.success {
            return ToolResultV2.success(
                toolId: "axon_invoke_action",
                output: result.message,
                structured: structured
            )
        }

        return ToolResultV2.failure(
            toolId: "axon_invoke_action",
            error: result.message
        )
    }

    private func executeGetState() async -> ToolResultV2 {
        let state = await AgentActionRegistry.shared.getState()

        let structuredState: [String: Any]? = {
            guard let data = try? JSONEncoder().encode(state),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }()

        let summary = """
        view=\(state.currentView ?? "unknown"), conversation=\(state.selectedConversationId ?? "none"), bridgeConnected=\(state.bridge.isConnected), tools=\(state.tools.enabledToolCount)/\(state.tools.loadedToolCount)
        """

        return ToolResultV2.success(
            toolId: "axon_get_state",
            output: summary,
            structured: structuredState
        )
    }

    private func resolveActionId(inputs: [String: Any]) -> String? {
        if let explicit = stringValue("action_id", from: inputs)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }

        if let fallback = stringValue("id", from: inputs)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            return fallback
        }

        if let query = stringValue("query", from: inputs),
           let queryData = query.data(using: .utf8),
           let queryObject = try? JSONSerialization.jsonObject(with: queryData) as? [String: Any] {
            if let parsed = queryObject["action_id"] as? String, !parsed.isEmpty {
                return parsed
            }
            if let parsed = queryObject["id"] as? String, !parsed.isEmpty {
                return parsed
            }
        }

        return nil
    }

    private func resolveActionParams(inputs: [String: Any]) -> [String: AnyCodable] {
        if let raw = inputs["params"] as? [String: Any] {
            return AgentActionRegistry.dictionaryToAnyCodable(raw)
        }

        if let rawCodable = inputs["params"] as? [String: AnyCodable] {
            return rawCodable
        }

        if let query = stringValue("query", from: inputs),
           let data = query.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let params = object["params"] as? [String: Any] {
            return AgentActionRegistry.dictionaryToAnyCodable(params)
        }

        return [:]
    }

    private func stringValue(_ key: String, from inputs: [String: Any]) -> String? {
        if let value = inputs[key] as? String {
            return value
        }
        return nil
    }
}
