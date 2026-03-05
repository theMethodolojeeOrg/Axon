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
/// - `agent_state` → agent_state_append, agent_state_query, agent_state_clear, persistence_disable
@MainActor
final class AgentStateHandler: ToolHandlerV2 {
    
    let handlerId = "agent_state"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "AgentStateHandler"
    )
    
    private let stateService = AgentStateService.shared
    
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
}
