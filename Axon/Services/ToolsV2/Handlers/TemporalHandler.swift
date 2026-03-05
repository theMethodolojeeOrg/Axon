//
//  TemporalHandler.swift
//  Axon
//
//  V2 Handler for temporal symmetry tools
//

import Foundation
import os.log

/// Handler for temporal-related tools
///
/// Registered handlers:
/// - `temporal` → temporal_sync, temporal_drift, temporal_status
@MainActor
final class TemporalHandler: ToolHandlerV2 {
    
    let handlerId = "temporal"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "TemporalHandler"
    )
    
    private let temporalService = TemporalContextService.shared
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        switch toolId {
        case "temporal_sync":
            return executeTemporalSync(inputs: inputs)
        case "temporal_drift":
            return executeTemporalDrift(inputs: inputs)
        case "temporal_status":
            return executeTemporalStatus(inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown temporal tool: \(toolId)")
        }
    }
    
    // MARK: - temporal_sync
    
    private func executeTemporalSync(inputs: [String: Any]) -> ToolResultV2 {
        let query = (inputs["query"] as? String)?.lowercased() ?? "enable"
        
        if query == "enable" {
            temporalService.enableSync()
            logger.info("Temporal sync mode enabled")
            
            return ToolResultV2.success(
                toolId: "temporal_sync",
                output: "Temporal sync mode enabled. You now have mutual time awareness with the human.",
                structured: ["mode": "sync"]
            )
        } else if query == "disable" {
            temporalService.enableDrift()
            
            return ToolResultV2.success(
                toolId: "temporal_sync",
                output: "Temporal sync mode disabled.",
                structured: ["mode": "drift"]
            )
        }
        
        return ToolResultV2.failure(
            toolId: "temporal_sync",
            error: "Invalid query. Use 'enable' or 'disable'."
        )
    }
    
    // MARK: - temporal_drift
    
    private func executeTemporalDrift(inputs: [String: Any]) -> ToolResultV2 {
        let query = (inputs["query"] as? String)?.lowercased() ?? "enable"
        
        if query == "enable" {
            temporalService.enableDrift()
            logger.info("Temporal drift mode enabled")
            
            return ToolResultV2.success(
                toolId: "temporal_drift",
                output: "Drift mode enabled. Temporal tracking suspended.",
                structured: ["mode": "drift"]
            )
        } else if query == "disable" {
            temporalService.enableSync()
            
            return ToolResultV2.success(
                toolId: "temporal_drift",
                output: "Drift mode disabled. Resuming temporal sync.",
                structured: ["mode": "sync"]
            )
        }
        
        return ToolResultV2.failure(
            toolId: "temporal_drift",
            error: "Invalid query. Use 'enable' or 'disable'."
        )
    }
    
    // MARK: - temporal_status
    
    private func executeTemporalStatus(inputs: [String: Any]) -> ToolResultV2 {
        let snapshot = temporalService.generateStatusSnapshot(contextTokens: 0, contextLimit: 100000)
        
        var output = "# Temporal Status\n\n"
        output += "**Mode:** \(snapshot.mode.rawValue)\n"
        if let duration = snapshot.sessionDuration {
            output += "**Session Duration:** \(formatDuration(duration))\n"
        }
        output += "**Turn Count:** \(snapshot.turnCount)\n"
        output += "**Context Saturation:** \(String(format: "%.1f", snapshot.contextSaturationPercent * 100))%\n"
        
        return ToolResultV2.success(
            toolId: "temporal_status",
            output: output,
            structured: [
                "mode": snapshot.mode.rawValue,
                "turnCount": snapshot.turnCount,
                "contextSaturationPercent": snapshot.contextSaturationPercent
            ]
        )
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
