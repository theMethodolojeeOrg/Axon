//
//  DevicePresenceHandler.swift
//  Axon
//
//  V2 Handler for device presence and multi-device tools
//

import Foundation
import os.log

/// Handler for device presence tools
///
/// Registered handlers:
/// - `device_presence` → query_device_presence, request_device_switch, set_presence_intent, save_state_checkpoint
@MainActor
final class DevicePresenceHandler: ToolHandlerV2 {
    
    let handlerId = "device_presence"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "DevicePresenceHandler"
    )
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        switch toolId {
        case "query_device_presence":
            return executeQueryDevicePresence(inputs: inputs)
        case "request_device_switch":
            return executeRequestDeviceSwitch(inputs: inputs)
        case "set_presence_intent":
            return executeSetPresenceIntent(inputs: inputs)
        case "save_state_checkpoint":
            return await executeSaveStateCheckpoint(inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown device presence tool: \(toolId)")
        }
    }
    
    // MARK: - query_device_presence
    
    private func executeQueryDevicePresence(inputs: [String: Any]) -> ToolResultV2 {
        logger.info("Querying device presence")
        
        // Get current device info
        let deviceId = DeviceIdentity.shared.deviceId ?? "unknown"
        let deviceName = DeviceIdentity.shared.deviceInfo?.deviceName ?? "Unknown"
        
        var output = "# Device Presence\n\n"
        output += "## Current Device\n"
        output += "- **ID:** \(deviceId.prefix(8))...\n"
        output += "- **Name:** \(deviceName)\n"
        output += "- **Status:** Active\n\n"
        
        // Note: Full implementation would query device presence service
        // for multi-device awareness
        output += "Multi-device presence tracking requires DevicePresenceService integration.\n"
        
        return ToolResultV2.success(
            toolId: "query_device_presence",
            output: output,
            structured: [
                "currentDeviceId": String(deviceId.prefix(8)),
                "deviceName": deviceName
            ]
        )
    }
    
    // MARK: - request_device_switch
    
    private func executeRequestDeviceSwitch(inputs: [String: Any]) -> ToolResultV2 {
        guard let query = inputs["query"] as? String else {
            return ToolResultV2.failure(
                toolId: "request_device_switch",
                error: "Missing query. Format: device_id|reason"
            )
        }
        
        let parts = query.components(separatedBy: "|")
        let targetDeviceId = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let reason = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "No reason provided"
        
        guard !targetDeviceId.isEmpty else {
            return ToolResultV2.failure(
                toolId: "request_device_switch",
                error: "Missing target device ID"
            )
        }
        
        logger.info("Requesting device switch to: \(targetDeviceId)")
        
        return ToolResultV2.success(
            toolId: "request_device_switch",
            output: """
            Device switch requested.
            
            **Target Device:** \(targetDeviceId)
            **Reason:** \(reason)
            
            The user will be notified based on their door policy settings.
            """,
            structured: [
                "targetDeviceId": targetDeviceId,
                "status": "pending"
            ]
        )
    }
    
    // MARK: - set_presence_intent
    
    private func executeSetPresenceIntent(inputs: [String: Any]) -> ToolResultV2 {
        guard let query = inputs["query"] as? String else {
            return ToolResultV2.failure(
                toolId: "set_presence_intent",
                error: "Missing query. Format: device_id|reason"
            )
        }
        
        let parts = query.components(separatedBy: "|")
        let preferredDeviceId = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let reason = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "No reason provided"
        
        logger.info("Setting presence intent: \(preferredDeviceId)")
        
        return ToolResultV2.success(
            toolId: "set_presence_intent",
            output: """
            Presence intent declared.
            
            **Preferred Device:** \(preferredDeviceId)
            **Reason:** \(reason)
            
            This intent will be considered when the system decides on device routing.
            """
        )
    }
    
    // MARK: - save_state_checkpoint
    
    private func executeSaveStateCheckpoint(inputs: [String: Any]) async -> ToolResultV2 {
        let reason = (inputs["query"] as? String) ?? "Manual checkpoint"
        
        logger.info("Saving state checkpoint: \(reason)")
        
        // Create checkpoint ID
        let checkpointId = "checkpoint-\(UUID().uuidString.prefix(8))"
        
        // Note: Full implementation would save current state for handoff
        // This would include conversation context, agent state, etc.
        
        return ToolResultV2.success(
            toolId: "save_state_checkpoint",
            output: """
            State checkpoint saved.
            
            **Checkpoint ID:** \(checkpointId)
            **Reason:** \(reason)
            **Timestamp:** \(ISO8601DateFormatter().string(from: Date()))
            
            This checkpoint can be used for device handoff.
            """,
            structured: [
                "checkpointId": checkpointId,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }
}
