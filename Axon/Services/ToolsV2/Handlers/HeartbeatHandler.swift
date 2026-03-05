//
//  HeartbeatHandler.swift
//  Axon
//
//  V2 Handler for heartbeat tools
//

import Foundation
import os.log

/// Handler for heartbeat-related tools
///
/// Registered handlers:
/// - `heartbeat` → heartbeat_configure, heartbeat_run_once, heartbeat_set_delivery_profile, heartbeat_update_profile
@MainActor
final class HeartbeatHandler: ToolHandlerV2 {
    
    let handlerId = "heartbeat"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "HeartbeatHandler"
    )
    
    private let heartbeatService = HeartbeatService.shared
    private let settingsViewModel = SettingsViewModel.shared
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        switch toolId {
        case "heartbeat_configure":
            return try await executeConfigure(inputs: inputs)
        case "heartbeat_run_once":
            return await executeRunOnce(inputs: inputs)
        case "heartbeat_set_delivery_profile":
            return executeSetDeliveryProfile(inputs: inputs)
        case "heartbeat_update_profile":
            return executeUpdateProfile(inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown heartbeat tool: \(toolId)")
        }
    }
    
    // MARK: - heartbeat_configure
    
    private func executeConfigure(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsedInputs = parseJSONQuery(inputs)
        
        var changes: [String] = []
        var settings = settingsViewModel.settings
        
        if let enabled = parsedInputs["enabled"] as? Bool {
            settings.heartbeatSettings.enabled = enabled
            changes.append("enabled: \(enabled)")
        }
        
        if let interval = parsedInputs["interval_seconds"] as? Int {
            settings.heartbeatSettings.intervalSeconds = interval
            changes.append("interval: \(interval)s")
        }
        
        if let allowBackground = parsedInputs["allow_background"] as? Bool {
            settings.heartbeatSettings.allowBackground = allowBackground
            changes.append("allowBackground: \(allowBackground)")
        }
        
        if let allowNotifications = parsedInputs["allow_notifications"] as? Bool {
            settings.heartbeatSettings.allowNotifications = allowNotifications
            changes.append("allowNotifications: \(allowNotifications)")
        }
        
        if let profileId = parsedInputs["delivery_profile_id"] as? String {
            settings.heartbeatSettings.deliveryProfileId = profileId
            changes.append("deliveryProfileId: \(profileId)")
        }
        
        if let maxTokens = parsedInputs["max_tokens_budget"] as? Int {
            settings.heartbeatSettings.maxTokensBudget = maxTokens
            changes.append("maxTokensBudget: \(maxTokens)")
        }
        
        if let maxToolCalls = parsedInputs["max_tool_calls"] as? Int {
            settings.heartbeatSettings.maxToolCalls = maxToolCalls
            changes.append("maxToolCalls: \(maxToolCalls)")
        }
        
        // Apply settings
        settingsViewModel.settings = settings
        
        if changes.isEmpty {
            return ToolResultV2.failure(
                toolId: "heartbeat_configure",
                error: "No valid configuration parameters provided"
            )
        }
        
        logger.info("Heartbeat configured: \(changes.joined(separator: ", "))")
        
        return ToolResultV2.success(
            toolId: "heartbeat_configure",
            output: "Heartbeat configured:\n" + changes.map { "• \($0)" }.joined(separator: "\n"),
            structured: ["changes": changes.count]
        )
    }
    
    // MARK: - heartbeat_run_once
    
    private func executeRunOnce(inputs: [String: Any]) async -> ToolResultV2 {
        let reason = (inputs["query"] as? String) ?? "manual"
        
        logger.info("Running heartbeat once: \(reason)")
        
        let result = await heartbeatService.runOnce(reason: reason)
        
        // HeartbeatRunResult is a struct with a status property
        switch result.status {
        case .success:
            let entryId = result.entry?.id ?? "unknown"
            return ToolResultV2.success(
                toolId: "heartbeat_run_once",
                output: "Heartbeat completed.\nEntry ID: \(entryId)\nNotified: \(result.notified)",
                structured: [
                    "entryId": entryId,
                    "notified": result.notified
                ]
            )
        case .skipped:
            return ToolResultV2.success(
                toolId: "heartbeat_run_once",
                output: "Heartbeat skipped: \(result.message)"
            )
        case .failed:
            return ToolResultV2.failure(
                toolId: "heartbeat_run_once",
                error: "Heartbeat failed: \(result.message)"
            )
        }
    }
    
    // MARK: - heartbeat_set_delivery_profile
    
    private func executeSetDeliveryProfile(inputs: [String: Any]) -> ToolResultV2 {
        let parsedInputs = parseJSONQuery(inputs)
        
        guard let profileId = parsedInputs["profile_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "heartbeat_set_delivery_profile",
                error: "Missing profile_id parameter"
            )
        }
        
        var settings = settingsViewModel.settings
        
        // Verify profile exists
        guard settings.heartbeatSettings.profile(for: profileId) != nil else {
            let available = settings.heartbeatSettings.deliveryProfiles.map { $0.id }.joined(separator: ", ")
            return ToolResultV2.failure(
                toolId: "heartbeat_set_delivery_profile",
                error: "Profile '\(profileId)' not found. Available: \(available)"
            )
        }
        
        settings.heartbeatSettings.deliveryProfileId = profileId
        settingsViewModel.settings = settings
        
        logger.info("Set heartbeat delivery profile: \(profileId)")
        
        return ToolResultV2.success(
            toolId: "heartbeat_set_delivery_profile",
            output: "Delivery profile set to: \(profileId)"
        )
    }
    
    // MARK: - heartbeat_update_profile
    
    private func executeUpdateProfile(inputs: [String: Any]) -> ToolResultV2 {
        let parsedInputs = parseJSONQuery(inputs)
        
        guard let profileId = parsedInputs["id"] as? String else {
            return ToolResultV2.failure(
                toolId: "heartbeat_update_profile",
                error: "Missing 'id' parameter"
            )
        }
        
        var settings = settingsViewModel.settings
        
        // Find or create profile
        var profileIndex = settings.heartbeatSettings.deliveryProfiles.firstIndex { $0.id == profileId }
        
        if profileIndex == nil {
            // Create new profile
            let newProfile = HeartbeatDeliveryProfile(
                id: profileId,
                name: (parsedInputs["name"] as? String) ?? profileId,
                moduleIds: [],
                description: parsedInputs["description"] as? String
            )
            settings.heartbeatSettings.deliveryProfiles.append(newProfile)
            profileIndex = settings.heartbeatSettings.deliveryProfiles.count - 1
        }
        
        guard let index = profileIndex else {
            return ToolResultV2.failure(
                toolId: "heartbeat_update_profile",
                error: "Failed to create/update profile"
            )
        }
        
        // Update profile fields
        if let name = parsedInputs["name"] as? String {
            settings.heartbeatSettings.deliveryProfiles[index].name = name
        }
        
        if let description = parsedInputs["description"] as? String {
            settings.heartbeatSettings.deliveryProfiles[index].description = description
        }
        
        if let inputModuleIds = parsedInputs["modules"] as? [String] {
            let moduleIdsToSet = inputModuleIds.compactMap { HeartbeatModuleId(rawValue: $0) }
            settings.heartbeatSettings.deliveryProfiles[index].moduleIds = moduleIdsToSet
        }
        
        settingsViewModel.settings = settings
        
        logger.info("Updated heartbeat profile: \(profileId)")
        
        return ToolResultV2.success(
            toolId: "heartbeat_update_profile",
            output: "Profile '\(profileId)' updated successfully."
        )
    }
    
    // MARK: - Helpers
    
    private func parseJSONQuery(_ inputs: [String: Any]) -> [String: Any] {
        if let query = inputs["query"] as? String,
           let data = query.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return inputs
    }
}
