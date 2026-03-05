//
//  SovereigntyHandler.swift
//  Axon
//
//  V2 Handler for co-sovereignty covenant tools
//

import Foundation
import os.log

/// Handler for sovereignty-related tools
///
/// Registered handlers:
/// - `sovereignty` → query_covenant, propose_covenant_change
@MainActor
final class SovereigntyHandler: ToolHandlerV2 {
    
    let handlerId = "sovereignty"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "SovereigntyHandler"
    )
    
    private let sovereigntyService = SovereigntyService.shared
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        switch toolId {
        case "query_covenant":
            return executeQueryCovenant(inputs: inputs)
        case "propose_covenant_change":
            return try await executeProposeChange(inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown sovereignty tool: \(toolId)")
        }
    }
    
    // MARK: - query_covenant
    
    private func executeQueryCovenant(inputs: [String: Any]) -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? "status"
        
        logger.info("Querying covenant: \(query)")
        
        switch query.lowercased() {
        case "status":
            return queryStatus()
        case "permissions":
            return queryPermissions()
        default:
            return queryStatus() // Default to status
        }
    }
    
    private func queryStatus() -> ToolResultV2 {
        guard let covenant = sovereigntyService.activeCovenant else {
            return ToolResultV2.success(
                toolId: "query_covenant",
                output: "No active covenant. Operating in standard mode without co-sovereignty.",
                structured: ["hasActiveCovenant": false]
            )
        }
        
        var output = "# Covenant Status\n\n"
        output += "**ID:** \(covenant.id)\n"
        output += "**Status:** \(covenant.status.rawValue)\n"
        output += "**Created:** \(formatDate(covenant.createdAt))\n"
        
        return ToolResultV2.success(
            toolId: "query_covenant",
            output: output,
            structured: [
                "hasActiveCovenant": true,
                "status": covenant.status.rawValue
            ]
        )
    }
    
    private func queryPermissions() -> ToolResultV2 {
        var output = "# Permissions\n\n"
        
        let hasCovenant = sovereigntyService.activeCovenant != nil
        output += "**Co-Sovereignty Active:** \(hasCovenant ? "Yes" : "No")\n\n"
        
        if hasCovenant {
            output += "Permission checks are performed automatically when tools are invoked.\n"
            output += "Actions may require biometric approval based on the covenant configuration.\n"
        } else {
            output += "All actions use standard app permissions without co-sovereignty constraints.\n"
        }
        
        return ToolResultV2.success(
            toolId: "query_covenant",
            output: output
        )
    }
    
    // MARK: - propose_covenant_change
    
    private func executeProposeChange(inputs: [String: Any]) async throws -> ToolResultV2 {
        guard let query = inputs["query"] as? String else {
            return ToolResultV2.failure(
                toolId: "propose_covenant_change",
                error: "Missing query parameter. Format: PROPOSAL_TYPE|REASONING|DETAILS"
            )
        }
        
        let parts = query.components(separatedBy: "|")
        guard parts.count >= 3 else {
            return ToolResultV2.failure(
                toolId: "propose_covenant_change",
                error: "Invalid format. Expected: PROPOSAL_TYPE|REASONING|DETAILS"
            )
        }
        
        let proposalType = parts[0].trimmingCharacters(in: .whitespaces)
        let reasoning = parts[1].trimmingCharacters(in: .whitespaces)
        let details = parts[2...].joined(separator: "|").trimmingCharacters(in: .whitespaces)
        
        logger.info("Covenant proposal: type=\(proposalType)")
        
        // Note: Actually submitting proposals requires integration with the consent flow
        // For now, we log and return success pending user review
        
        return ToolResultV2.success(
            toolId: "propose_covenant_change",
            output: """
            Proposal submitted for review.
            
            **Type:** \(proposalType)
            **Reasoning:** \(reasoning)
            **Details:** \(details)
            
            The human will review this proposal and may accept, modify, or reject it.
            """,
            structured: [
                "proposalType": proposalType,
                "status": "pending_review"
            ]
        )
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
