//
//  AgentActionRegistry.swift
//  Axon
//
//  Curated native action registry for semantic app control.
//

import Foundation
import Combine

// MARK: - Action Models

enum AgentActionRiskLevel: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

struct AgentActionParameterDescriptor: Codable, Equatable, Sendable {
    let name: String
    let type: String
    let required: Bool
    let description: String
}

struct AgentActionDescriptor: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let description: String
    let group: String
    let viewRef: String?
    let handleRefs: [String]
    let platforms: [String]
    let tags: [String]
    let riskLevel: AgentActionRiskLevel
    let requiresApproval: Bool
    let parameters: [AgentActionParameterDescriptor]
}

struct AgentActionContext: Codable, Equatable, Sendable {
    let source: String?
    let sessionId: String?
    let actor: String?
    let view: String?

    init(source: String? = nil, sessionId: String? = nil, actor: String? = nil, view: String? = nil) {
        self.source = source
        self.sessionId = sessionId
        self.actor = actor
        self.view = view
    }
}

struct AgentActionResult: Codable, Equatable, Sendable {
    let success: Bool
    let message: String
    let errorCode: String?
    let data: [String: AnyCodable]?

    static func success(_ message: String, data: [String: AnyCodable]? = nil) -> AgentActionResult {
        AgentActionResult(success: true, message: message, errorCode: nil, data: data)
    }

    static func failure(_ message: String, code: String, data: [String: AnyCodable]? = nil) -> AgentActionResult {
        AgentActionResult(success: false, message: message, errorCode: code, data: data)
    }
}

struct AgentActionBridgeStateSnapshot: Codable, Equatable, Sendable {
    let enabled: Bool
    let mode: String
    let isRunning: Bool
    let isConnected: Bool
    let sessionCount: Int
}

struct AgentActionToolsSnapshot: Codable, Equatable, Sendable {
    let toolsV2Active: Bool
    let masterEnabled: Bool
    let loadedToolCount: Int
    let enabledToolCount: Int
}

struct AgentActionStateSnapshot: Codable, Equatable, Sendable {
    let currentView: String?
    let selectedConversationId: String?
    let selectedConversationTitle: String?
    let bridge: AgentActionBridgeStateSnapshot
    let tools: AgentActionToolsSnapshot
}

struct AgentActionUIRequest: Sendable {
    let requestId: String
    let actionId: String
    let params: [String: AnyCodable]
}

// MARK: - Registry

@MainActor
final class AgentActionRegistry: ObservableObject {
    static let shared = AgentActionRegistry()

    private let notificationCenter: NotificationCenter
    private let approvalBridge = ToolApprovalBridgeV2.shared

    private var pendingUIRequests: [String: CheckedContinuation<AgentActionResult, Never>] = [:]
    private var pendingUITimeouts: [String: Task<Void, Never>] = [:]

    private var currentViewRef: String?
    private var selectedConversationId: String?
    private var selectedConversationTitle: String?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    // MARK: Discover

    func discoverActions(
        filter: String? = nil,
        platform: String? = nil,
        view: String? = nil
    ) -> [AgentActionDescriptor] {
        let normalizedFilter = filter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPlatform = platform?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedView = view?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return Self.descriptors
            .filter { descriptor in
                guard let normalizedFilter, !normalizedFilter.isEmpty else { return true }
                let haystack: [String] = [
                    descriptor.id,
                    descriptor.title,
                    descriptor.description,
                    descriptor.group
                ] + descriptor.tags + descriptor.handleRefs
                return haystack.contains { $0.lowercased().contains(normalizedFilter) }
            }
            .filter { descriptor in
                guard let normalizedPlatform, !normalizedPlatform.isEmpty else { return true }
                return descriptor.platforms.contains { $0.lowercased() == normalizedPlatform }
            }
            .filter { descriptor in
                guard let normalizedView, !normalizedView.isEmpty else { return true }
                if let viewRef = descriptor.viewRef?.lowercased(), viewRef.contains(normalizedView) {
                    return true
                }
                return descriptor.handleRefs.contains { $0.lowercased().contains(normalizedView) }
            }
            .sorted { lhs, rhs in
                if lhs.group != rhs.group {
                    return lhs.group < rhs.group
                }
                return lhs.id < rhs.id
            }
    }

    // MARK: Invoke

    func invokeAction(
        id: String,
        params: [String: AnyCodable] = [:]
    ) async -> AgentActionResult {
        await invokeAction(
            id: id,
            params: params,
            context: AgentActionContext(source: nil, sessionId: nil, actor: nil, view: nil)
        )
    }

    func invokeAction(
        id: String,
        params: [String: AnyCodable],
        context: AgentActionContext
    ) async -> AgentActionResult {
        guard let descriptor = Self.descriptor(for: id) else {
            return .failure("Unknown action: \(id)", code: "unknown_action")
        }

        if descriptor.requiresApproval {
            let approvalResult = await requestApproval(for: descriptor)
            if !approvalResult.isApprovedV2 {
                return .failure(
                    approvalResult.failureReasonV2 ?? "Approval denied",
                    code: "approval_denied"
                )
            }
        }

        switch id {
        case "open_chat", "open_cognition", "open_settings", "open_create":
            return await dispatchUIAction(actionId: id, params: params)

        case "new_chat":
            return await dispatchUIAction(actionId: id, params: params)

        case "select_conversation":
            return await dispatchUIAction(actionId: id, params: params)

        case "send_message":
            return await invokeSendMessage(params: params)

        case "toggle_bridge":
            return await invokeToggleBridge(params: params, context: context)

        case "query_tools_status":
            return await invokeQueryToolsStatus()

        default:
            return .failure("Action is not implemented: \(id)", code: "not_implemented")
        }
    }

    // MARK: State

    func getState() async -> AgentActionStateSnapshot {
        let pluginLoader = ToolPluginLoader.shared
        if pluginLoader.loadedTools.isEmpty {
            await pluginLoader.loadAllTools()
        }

        let bridgeManager = BridgeConnectionManager.shared
        let bridgeSettings = BridgeSettingsStorage.shared.settings
        let conversation = ConversationService.shared.currentConversation

        let fallbackConversationId = selectedConversationId ?? conversation?.id
        let fallbackConversationTitle = selectedConversationTitle ?? conversation?.title
        let fallbackView = currentViewRef ?? "chat"

        return AgentActionStateSnapshot(
            currentView: fallbackView,
            selectedConversationId: fallbackConversationId,
            selectedConversationTitle: fallbackConversationTitle,
            bridge: AgentActionBridgeStateSnapshot(
                enabled: bridgeSettings.enabled,
                mode: bridgeManager.mode.rawValue,
                isRunning: bridgeManager.isRunning,
                isConnected: bridgeManager.isConnected,
                sessionCount: bridgeManager.sessionCount
            ),
            tools: AgentActionToolsSnapshot(
                toolsV2Active: ToolsV2Toggle.shared.isV2Active,
                masterEnabled: pluginLoader.masterToolsEnabled,
                loadedToolCount: pluginLoader.loadedTools.count,
                enabledToolCount: pluginLoader.enabledTools.count
            )
        )
    }

    func updateUIState(currentView: String, selectedConversation: Conversation?) {
        currentViewRef = currentView
        selectedConversationId = selectedConversation?.id
        selectedConversationTitle = selectedConversation?.title
    }

    // MARK: UI Request Completion

    func completeUIRequest(requestId: String, result: AgentActionResult) {
        guard let continuation = pendingUIRequests.removeValue(forKey: requestId) else { return }
        pendingUITimeouts.removeValue(forKey: requestId)?.cancel()
        continuation.resume(returning: result)
    }

    // MARK: Private - Invocation Helpers

    private func requestApproval(for descriptor: AgentActionDescriptor) async -> ToolApprovalResult {
        await approvalBridge.requestApprovalForAction(
            actionDescription: descriptor.description,
            toolId: "axon_action_\(descriptor.id)",
            approvalScopes: ["axon.action.\(descriptor.id)"]
        )
    }

    private func dispatchUIAction(
        actionId: String,
        params: [String: AnyCodable],
        timeout: TimeInterval = 3.0
    ) async -> AgentActionResult {
        let requestId = UUID().uuidString
        let request = AgentActionUIRequest(requestId: requestId, actionId: actionId, params: params)

        return await withCheckedContinuation { continuation in
            pendingUIRequests[requestId] = continuation

            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    self?.completeUIRequest(
                        requestId: requestId,
                        result: .failure(
                            "UI action timed out. Ensure Axon is on the main app screen.",
                            code: "ui_timeout"
                        )
                    )
                }
            }
            pendingUITimeouts[requestId] = timeoutTask

            notificationCenter.post(
                name: .axonUIActionRequest,
                object: nil,
                userInfo: ["request": request]
            )
        }
    }

    private func invokeSendMessage(params: [String: AnyCodable]) async -> AgentActionResult {
        let message = (params["message"]?.stringValue ?? params["content"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return .failure("Missing required parameter: message", code: "invalid_params")
        }

        let requestedConversationId = params["conversation_id"]?.stringValue ?? params["conversationId"]?.stringValue

        do {
            let conversation = try await resolveConversation(
                requestedConversationId: requestedConversationId,
                seedContent: message
            )

            _ = await dispatchUIAction(
                actionId: "select_conversation",
                params: ["conversation_id": .string(conversation.id)],
                timeout: 1.5
            )

            let enabledTools = enabledToolsForConversation(conversationId: conversation.id)
            let assistant = try await ConversationService.shared.sendMessage(
                conversationId: conversation.id,
                content: message,
                enabledTools: enabledTools
            )

            return .success(
                "Message sent to conversation \(conversation.id)",
                data: [
                    "conversation_id": .string(conversation.id),
                    "assistant_message_id": .string(assistant.id),
                    "assistant_preview": .string(String(assistant.content.prefix(200)))
                ]
            )
        } catch {
            return .failure("Failed to send message: \(error.localizedDescription)", code: "execution_failed")
        }
    }

    private func invokeToggleBridge(
        params: [String: AnyCodable],
        context: AgentActionContext
    ) async -> AgentActionResult {
        let storage = BridgeSettingsStorage.shared
        let manager = BridgeConnectionManager.shared

        let requested = params["enabled"]?.boolValue
        let nextEnabled = requested ?? !storage.settings.enabled

        storage.setEnabled(nextEnabled)
        if nextEnabled {
            await manager.start()
        } else {
            await manager.stop()
        }

        return .success(
            "Bridge \(nextEnabled ? "enabled" : "disabled")",
            data: [
                "enabled": .bool(storage.settings.enabled),
                "mode": .string(manager.mode.rawValue),
                "is_running": .bool(manager.isRunning),
                "is_connected": .bool(manager.isConnected),
                "source": .string(context.source ?? "unknown")
            ]
        )
    }

    private func invokeQueryToolsStatus() async -> AgentActionResult {
        let state = await getState()
        return .success(
            "Loaded \(state.tools.loadedToolCount) tools (\(state.tools.enabledToolCount) enabled)",
            data: [
                "tools_v2_active": .bool(state.tools.toolsV2Active),
                "master_enabled": .bool(state.tools.masterEnabled),
                "loaded_tool_count": .int(state.tools.loadedToolCount),
                "enabled_tool_count": .int(state.tools.enabledToolCount),
                "bridge_enabled": .bool(state.bridge.enabled),
                "bridge_connected": .bool(state.bridge.isConnected)
            ]
        )
    }

    private func resolveConversation(
        requestedConversationId: String?,
        seedContent: String
    ) async throws -> Conversation {
        let conversationService = ConversationService.shared

        if let requestedConversationId, !requestedConversationId.isEmpty {
            if let local = conversationService.conversations.first(where: { $0.id == requestedConversationId }) {
                return try materializeConversationIfNeeded(local, seedContent: seedContent)
            }

            try await conversationService.listConversations(limit: 200, offset: 0)
            if let refreshed = conversationService.conversations.first(where: { $0.id == requestedConversationId }) {
                return try materializeConversationIfNeeded(refreshed, seedContent: seedContent)
            }

            throw NSError(
                domain: "AgentActionRegistry",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Conversation not found: \(requestedConversationId)"]
            )
        }

        if let current = conversationService.currentConversation {
            return try materializeConversationIfNeeded(current, seedContent: seedContent)
        }

        let title = String(seedContent.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
        let created = try await conversationService.createConversation(
            title: title.isEmpty ? "New Chat" : title,
            firstMessage: nil
        )
        return created
    }

    private func materializeConversationIfNeeded(
        _ conversation: Conversation,
        seedContent: String
    ) throws -> Conversation {
        let conversationService = ConversationService.shared
        guard conversationService.isEphemeral(conversation.id) else { return conversation }

        let title = String(seedContent.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
        return try conversationService.persistEphemeralConversation(
            conversation.id,
            title: title.isEmpty ? conversation.title : title
        )
    }

    private func enabledToolsForConversation(conversationId: String) -> [String] {
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        guard settings.toolSettings.toolsEnabled else { return [] }

        let overridesKey = "conversation_overrides_\(conversationId)"
        if let data = UserDefaults.standard.data(forKey: overridesKey),
           let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data),
           let perConversation = overrides.enabledToolIds {
            return Array(perConversation)
        }

        return Array(settings.toolSettings.enabledToolIds)
    }

    // MARK: Shared Serialization Helpers

    static func anyCodable(from value: Any) -> AnyCodable? {
        switch value {
        case is NSNull:
            return .null
        case let value as AnyCodable:
            return value
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .int(value)
        case let value as Double:
            return .double(value)
        case let value as Float:
            return .double(Double(value))
        case let value as String:
            return .string(value)
        case let value as [Any]:
            return .array(value.compactMap { anyCodable(from: $0) })
        case let value as [String: Any]:
            return .object(dictionaryToAnyCodable(value))
        case let value as [String: AnyCodable]:
            return .object(value)
        default:
            return nil
        }
    }

    static func dictionaryToAnyCodable(_ dictionary: [String: Any]) -> [String: AnyCodable] {
        dictionary.reduce(into: [String: AnyCodable]()) { partialResult, entry in
            if let converted = anyCodable(from: entry.value) {
                partialResult[entry.key] = converted
            }
        }
    }

    static func foundationValue(from value: AnyCodable) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .array(let array):
            return array.map { foundationValue(from: $0) }
        case .object(let object):
            return object.mapValues { foundationValue(from: $0) }
        }
    }

    // MARK: Descriptor Catalog

    private static func descriptor(for id: String) -> AgentActionDescriptor? {
        descriptors.first { $0.id == id }
    }

    private static let descriptors: [AgentActionDescriptor] = [
        AgentActionDescriptor(
            id: "open_chat",
            title: "Open Chat",
            description: "Navigate to the chat surface.",
            group: "navigation",
            viewRef: "main.chat",
            handleRefs: ["root.nav.chat", "sidebar.chat", "tab.chat"],
            platforms: ["ios", "macos"],
            tags: ["navigation", "chat", "view"],
            riskLevel: .low,
            requiresApproval: false,
            parameters: []
        ),
        AgentActionDescriptor(
            id: "open_cognition",
            title: "Open Cognition",
            description: "Navigate to cognition (memory/internal-thread surface).",
            group: "navigation",
            viewRef: "main.cognition",
            handleRefs: ["root.nav.cognition", "sidebar.cognition", "tab.cognition"],
            platforms: ["ios", "macos"],
            tags: ["navigation", "cognition", "memory"],
            riskLevel: .low,
            requiresApproval: false,
            parameters: []
        ),
        AgentActionDescriptor(
            id: "open_settings",
            title: "Open Settings",
            description: "Navigate to application settings.",
            group: "navigation",
            viewRef: "main.settings",
            handleRefs: ["root.nav.settings", "sidebar.settings", "tab.settings"],
            platforms: ["ios", "macos"],
            tags: ["navigation", "settings"],
            riskLevel: .low,
            requiresApproval: false,
            parameters: []
        ),
        AgentActionDescriptor(
            id: "open_create",
            title: "Open Create",
            description: "Navigate to create/gallery.",
            group: "navigation",
            viewRef: "main.create",
            handleRefs: ["root.nav.create", "sidebar.create", "tab.create"],
            platforms: ["ios", "macos"],
            tags: ["navigation", "create", "gallery"],
            riskLevel: .low,
            requiresApproval: false,
            parameters: []
        ),
        AgentActionDescriptor(
            id: "new_chat",
            title: "New Chat",
            description: "Start a new chat thread.",
            group: "chat",
            viewRef: "chat.thread",
            handleRefs: ["chat.new", "toolbar.new_chat", "composer.new_chat"],
            platforms: ["ios", "macos"],
            tags: ["chat", "thread", "create"],
            riskLevel: .low,
            requiresApproval: false,
            parameters: []
        ),
        AgentActionDescriptor(
            id: "select_conversation",
            title: "Select Conversation",
            description: "Select an existing conversation by ID.",
            group: "chat",
            viewRef: "chat.thread",
            handleRefs: ["chat.select_conversation", "sidebar.conversation_list"],
            platforms: ["ios", "macos"],
            tags: ["chat", "conversation", "selection"],
            riskLevel: .low,
            requiresApproval: false,
            parameters: [
                AgentActionParameterDescriptor(
                    name: "conversation_id",
                    type: "string",
                    required: true,
                    description: "Target conversation ID."
                )
            ]
        ),
        AgentActionDescriptor(
            id: "send_message",
            title: "Send Message",
            description: "Send a user message into a conversation.",
            group: "chat",
            viewRef: "chat.composer",
            handleRefs: ["chat.send_message", "composer.send"],
            platforms: ["ios", "macos"],
            tags: ["chat", "message", "orchestration"],
            riskLevel: .medium,
            requiresApproval: true,
            parameters: [
                AgentActionParameterDescriptor(
                    name: "message",
                    type: "string",
                    required: true,
                    description: "Message content."
                ),
                AgentActionParameterDescriptor(
                    name: "conversation_id",
                    type: "string",
                    required: false,
                    description: "Optional existing conversation ID."
                )
            ]
        ),
        AgentActionDescriptor(
            id: "toggle_bridge",
            title: "Toggle Bridge",
            description: "Enable/disable bridge connectivity.",
            group: "ops",
            viewRef: "settings.bridge",
            handleRefs: ["bridge.toggle", "settings.connectivity.bridge_enabled"],
            platforms: ["ios", "macos"],
            tags: ["bridge", "connectivity", "operations"],
            riskLevel: .high,
            requiresApproval: true,
            parameters: [
                AgentActionParameterDescriptor(
                    name: "enabled",
                    type: "boolean",
                    required: false,
                    description: "Optional explicit enabled flag. If omitted, action toggles."
                )
            ]
        ),
        AgentActionDescriptor(
            id: "query_tools_status",
            title: "Query Tools Status",
            description: "Return current V2 tools and bridge status.",
            group: "ops",
            viewRef: "system.tools",
            handleRefs: ["tools.status", "bridge.status"],
            platforms: ["ios", "macos"],
            tags: ["tools", "status", "bridge"],
            riskLevel: .low,
            requiresApproval: false,
            parameters: []
        )
    ]
}

extension Notification.Name {
    static let axonUIActionRequest = Notification.Name("AxonUIActionRequest")
}
