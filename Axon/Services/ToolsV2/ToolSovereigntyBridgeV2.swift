//
//  ToolSovereigntyBridgeV2.swift
//  Axon
//
//  Bridges V2 tools to the existing SovereigntyService for trust tier permissions.
//  Maps V2 tool categories and sovereignty config to the co-sovereignty permission system.
//

import Foundation
import Combine
import os.log

// MARK: - Sovereignty Bridge

/// Bridge for V2 tool sovereignty checks
///
/// Integrates V2 tools with the co-sovereignty system:
/// - Checks trust tier permissions before execution
/// - Handles AI consent requirements
/// - Respects deadlock state
/// - Maps V2 sovereignty config to V1 action types
@MainActor
final class ToolSovereigntyBridgeV2: ObservableObject {

    // MARK: - Singleton

    static let shared = ToolSovereigntyBridgeV2()

    // MARK: - Dependencies

    private let sovereigntyService = SovereigntyService.shared
    private let pluginLoader = ToolPluginLoader.shared

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ToolSovereigntyBridgeV2"
    )

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Check permission for a V2 tool
    /// - Parameters:
    ///   - manifest: The tool manifest to check
    ///   - scope: Optional action scope
    /// - Returns: Permission result from sovereignty service
    func checkPermission(
        manifest: ToolManifest,
        scope: ActionScope? = nil
    ) -> PermissionResult {
        let action = mapToSovereignAction(manifest: manifest)
        let result = sovereigntyService.checkActionPermission(action, scope: scope)

        logger.debug("Permission check for \(manifest.tool.id): \(String(describing: result))")

        return result
    }

    /// Check if a tool requires AI consent
    func requiresAIConsent(manifest: ToolManifest) -> Bool {
        guard let actionCategory = resolveActionCategory(manifest: manifest) else {
            return false
        }
        return sovereigntyService.requiresAIConsent(for: actionCategory)
    }

    /// Check if tool execution is currently blocked (e.g., deadlock)
    func isExecutionBlocked(manifest: ToolManifest) -> (blocked: Bool, reason: String?) {
        let permission = checkPermission(manifest: manifest)

        switch permission {
        case .blocked(let reason):
            switch reason {
            case .noCovenant:
                return (true, "No active covenant established")
            case .covenantSuspended:
                return (true, "Covenant is suspended pending resolution")
            case .deadlocked(let deadlockId):
                return (true, "Deadlock active: \(deadlockId)")
            case .integrityViolation:
                return (true, "Integrity violation detected")
            }
        case .preApproved, .requiresApproval, .requiresAIConsent:
            return (false, nil)
        }
    }

    /// Get effective trust tier for a tool, including category defaults
    func effectiveTrustTier(manifest: ToolManifest) -> String? {
        // 1. Check explicit trustTierCategory on the tool
        if let explicit = manifest.tool.trustTierCategory {
            return explicit
        }

        // 2. Check sovereignty actionCategory
        if let sovereignty = manifest.sovereignty?.actionCategory {
            return sovereignty
        }

        // 3. Fall back to category defaults from _index.json
        let categoryKey = manifest.tool.category.rawValue
        if let defaults = pluginLoader.defaultTrustTiers[categoryKey] {
            return defaults.trustTierCategory
        }

        return nil
    }

    /// Get effective trust tier for a loaded tool (convenience)
    func effectiveTrustTier(for tool: LoadedTool) -> String? {
        pluginLoader.effectiveTrustTierCategory(for: tool)
    }

    /// Check if tool can skip approval via trust tier
    func canSkipApproval(manifest: ToolManifest) -> Bool {
        let permission = checkPermission(manifest: manifest)

        switch permission {
        case .preApproved:
            return true
        default:
            return false
        }
    }

    // MARK: - Permission Result Helpers

    /// Convert sovereignty result to simple execution check
    func canExecute(permission: PermissionResult) -> (allowed: Bool, needsApproval: Bool, needsAIConsent: Bool, blockReason: String?) {
        switch permission {
        case .preApproved:
            return (true, false, false, nil)

        case .requiresApproval:
            return (true, true, false, nil)

        case .requiresAIConsent:
            return (true, true, true, nil)

        case .blocked(let reason):
            switch reason {
            case .deadlocked(let id):
                return (false, false, false, "Deadlock active: \(id)")
            case .noCovenant:
                // Allow execution but log warning
                logger.warning("No covenant - allowing execution with reduced trust")
                return (true, true, false, nil)
            case .covenantSuspended:
                return (false, false, false, "Covenant suspended")
            case .integrityViolation:
                return (false, false, false, "Integrity violation detected")
            }
        }
    }

    // MARK: - Private: Mapping

    /// Map V2 manifest to SovereignAction, using category defaults if needed
    private func mapToSovereignAction(manifest: ToolManifest) -> SovereignAction {
        // Use effective trust tier (includes category defaults)
        if let trustTier = effectiveTrustTier(manifest: manifest) {
            return .specific(.toolInvocation, action: trustTier)
        }

        // Fallback: use tool ID as action
        return .specific(.toolInvocation, action: manifest.tool.id)
    }

    /// Resolve the action category for AI consent checks
    private func resolveActionCategory(manifest: ToolManifest) -> ActionCategory? {
        // Map sovereignty config to ActionCategory
        guard let actionCategoryString = manifest.sovereignty?.actionCategory else {
            return nil
        }

        // Map common action categories
        switch actionCategoryString {
        case "memory_add":
            return ActionCategory.memoryAdd
        case "memory_delete":
            return ActionCategory.memoryDelete
        case "memory_modify":
            return ActionCategory.memoryModify
        case "system_settings":
            return ActionCategory.systemPromptChange
        case "system_execute":
            return ActionCategory.shellCommand
        case "provider_switch":
            return ActionCategory.providerSwitch
        case "capability_add":
            return ActionCategory.capabilityEnable
        case "capability_remove":
            return ActionCategory.capabilityDisable
        case "agent_state_write":
            return ActionCategory.agentStateWrite
        case "agent_state_delete":
            return ActionCategory.agentStateDelete
        case "heartbeat_control":
            return ActionCategory.heartbeatControl
        default:
            return ActionCategory.toolInvocation
        }
    }
}

// MARK: - V2 Permission Wrapper

/// Wrapper for V2-specific permission checks
struct ToolPermissionCheckV2 {
    let toolId: String
    let permission: PermissionResult
    let canExecute: Bool
    let needsApproval: Bool
    let needsAIConsent: Bool
    let blockReason: String?

    @MainActor
    init(toolId: String, permission: PermissionResult, bridge: ToolSovereigntyBridgeV2) {
        self.toolId = toolId
        self.permission = permission

        let check = bridge.canExecute(permission: permission)
        self.canExecute = check.allowed
        self.needsApproval = check.needsApproval
        self.needsAIConsent = check.needsAIConsent
        self.blockReason = check.blockReason
    }
}
