//
//  ToolApprovalBridgeV2.swift
//  Axon
//
//  Bridges V2 tools to the existing ToolApprovalService for biometric approval flows.
//  Converts between V2 manifests and V1 types to leverage existing infrastructure.
//

import Foundation
import Combine
import os.log

// MARK: - Approval Bridge

/// Bridge for V2 tool approval flows
///
/// Converts V2 tool manifests to the format expected by ToolApprovalService,
/// allowing V2 tools to use the existing biometric authentication and
/// session approval tracking infrastructure.
@MainActor
final class ToolApprovalBridgeV2: ObservableObject {

    // MARK: - Singleton

    static let shared = ToolApprovalBridgeV2()

    // MARK: - Dependencies

    private let approvalService = ToolApprovalService.shared

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ToolApprovalBridgeV2"
    )

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Request approval for a V2 tool
    /// - Parameters:
    ///   - manifest: The V2 tool manifest
    ///   - inputs: Parsed input values
    ///   - timeoutSeconds: Optional timeout for approval
    /// - Returns: The approval result
    func requestApproval(
        manifest: ToolManifest,
        inputs: [String: Any],
        timeoutSeconds: Int? = nil
    ) async -> ToolApprovalResult {
        // Convert V2 manifest to V1 DynamicToolConfig for approval service
        let v1Config = convertToV1Config(manifest: manifest)

        logger.info("Requesting approval for V2 tool: \(manifest.tool.id)")

        // Use the existing approval service with sovereignty integration
        return await approvalService.requestApprovalWithSovereignty(
            tool: v1Config,
            inputs: inputs,
            timeoutSeconds: timeoutSeconds
        )
    }

    /// Request approval for a custom action without a full manifest
    /// Use this for internal actions like model/provider changes that need biometric approval
    /// - Parameters:
    ///   - actionDescription: Human-readable description for the approval prompt
    ///   - toolId: Tool ID for logging/tracking
    ///   - approvalScopes: Optional scopes for the approval
    /// - Returns: The approval result
    func requestApprovalForAction(
        actionDescription: String,
        toolId: String,
        approvalScopes: [String]? = nil
    ) async -> ToolApprovalResult {
        logger.info("Requesting approval for action: \(toolId) - \(actionDescription)")

        // Create a minimal config for the approval service
        let config = DynamicToolConfig(
            id: toolId,
            name: toolId.replacingOccurrences(of: "_", with: " ").capitalized,
            description: actionDescription,
            category: .utility,
            enabled: true,
            icon: "gearshape.fill",
            requiredSecrets: [],
            pipeline: [],
            parameters: [:],
            outputTemplate: nil,
            requiresApproval: true,
            approvalScopes: approvalScopes
        )

        return await approvalService.requestApprovalWithSovereignty(
            tool: config,
            inputs: ["action": actionDescription],
            timeoutSeconds: nil
        )
    }

    /// Check if a tool requires approval
    /// - Parameter manifest: The tool manifest to check
    /// - Returns: True if approval is required
    func requiresApproval(manifest: ToolManifest) -> Bool {
        // First check if sovereignty pre-approves this tool via trust tiers
        // If pre-approved, skip the manual approval requirement
        let sovereigntyPermission = ToolSovereigntyBridgeV2.shared.checkPermission(manifest: manifest)
        if case .preApproved = sovereigntyPermission {
            logger.debug("Tool \(manifest.tool.id) pre-approved by sovereignty, skipping manual approval")
            return false
        }

        // Check explicit flag in manifest
        if manifest.tool.effectiveRequiresApproval {
            return true
        }

        // Check sovereignty risk level
        if let riskLevel = manifest.sovereignty?.riskLevel {
            switch riskLevel {
            case .high, .critical:
                return true
            case .low, .medium:
                return false
            }
        }

        return false
    }

    /// Check if a tool is approved for the current session
    func isApprovedForSession(toolId: String) -> ToolApprovalRecord? {
        approvalService.isApprovedForSession(toolId: toolId)
    }

    /// Set the current conversation ID for session tracking
    func setConversationContext(_ conversationId: UUID) {
        approvalService.setCurrentConversation(conversationId)
    }

    // MARK: - Conversion

    /// Convert a V2 ToolManifest to V1 DynamicToolConfig for approval service
    private func convertToV1Config(manifest: ToolManifest) -> DynamicToolConfig {
        // Build minimal V1 config for approval flow
        let parameters = manifest.parameters?.mapValues { param -> ToolParameter in
            // Extract string value from AnyCodableV2 if present
            let defaultValueString: String? = {
                guard let anyDefault = param.defaultValue else { return nil }
                if let strVal = anyDefault.value as? String {
                    return strVal
                }
                return String(describing: anyDefault.value)
            }()
            
            return ToolParameter(
                type: convertParameterType(param.type),
                required: param.required ?? false,
                description: param.description ?? "",
                defaultValue: defaultValueString
            )
        } ?? [:]

        // Determine approval scopes from V2 sovereignty config
        let approvalScopes: [String]?
        if let scopes = manifest.sovereignty?.scopes {
            approvalScopes = scopes
        } else {
            // Fallback: derive from action category
            if let actionCategory = manifest.sovereignty?.actionCategory {
                approvalScopes = [actionCategory]
            } else {
                approvalScopes = nil
            }
        }

        return DynamicToolConfig(
            id: manifest.tool.id,
            name: manifest.tool.name,
            description: manifest.tool.description,
            category: convertCategory(manifest.tool.category),
            enabled: true,
            icon: manifest.tool.icon?.resolvedIcon ?? "questionmark.circle",
            requiredSecrets: [],
            pipeline: [],
            parameters: parameters,
            outputTemplate: nil,
            requiresApproval: manifest.tool.effectiveRequiresApproval,
            approvalScopes: approvalScopes
        )
    }

    /// Convert V2 parameter type to V1
    private func convertParameterType(_ v2Type: ParameterTypeV2) -> ParameterType {
        switch v2Type {
        case .string: return .string
        case .number: return .number
        case .integer: return .number
        case .boolean: return .boolean
        case .array: return .array
        case .object: return .object
        case .enum: return .string
        }
    }

    /// Convert V2 category to V1
    private func convertCategory(_ v2Category: ToolCategoryV2) -> DynamicToolCategory {
        switch v2Category {
        case .memory, .agentState, .heartbeat, .sovereignty, .subAgents, .temporal, .discovery, .notification:
            return .utility
        case .system:
            return .integration
        case .provider:
            return .composite
        case .port:
            return .integration
        case .custom:
            return .custom
        }
    }
}

// MARK: - Result Conversion

extension ToolApprovalResult {
    /// Convert approval result to V2 format check
    var isApprovedV2: Bool {
        switch self {
        case .approved, .approvedForSession, .approvedViaTrustTier:
            return true
        case .denied, .blocked, .timeout, .cancelled, .stop, .error:
            return false
        }
    }

    /// Get failure reason if not approved
    var failureReasonV2: String? {
        switch self {
        case .approved, .approvedForSession, .approvedViaTrustTier:
            return nil
        case .denied:
            return "User denied approval"
        case .blocked(let reason):
            return reason
        case .timeout:
            return "Approval request timed out"
        case .cancelled:
            return "Approval request was cancelled"
        case .stop:
            return "Execution stopped by user"
        case .error(let message):
            return message
        }
    }
}
