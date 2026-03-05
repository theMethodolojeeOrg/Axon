//
//  SubAgentHandler.swift
//  Axon
//
//  V2 Handler for sub-agent spawning and management tools
//

import Foundation
import os.log

/// Handler for sub-agent tools
///
/// Registered handlers:
/// - `sub_agent` → spawn_scout, spawn_mechanic, spawn_designer, query_job_status, accept_job_result, terminate_job
@MainActor
final class SubAgentHandler: ToolHandlerV2 {
    
    let handlerId = "sub_agent"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "SubAgentHandler"
    )
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        switch toolId {
        case "spawn_scout":
            return try await executeSpawnAgent(type: .scout, inputs: inputs)
        case "spawn_mechanic":
            return try await executeSpawnAgent(type: .mechanic, inputs: inputs)
        case "spawn_designer":
            return try await executeSpawnAgent(type: .designer, inputs: inputs)
        case "query_job_status":
            return executeQueryJobStatus(inputs: inputs)
        case "accept_job_result":
            return executeAcceptJobResult(inputs: inputs)
        case "terminate_job":
            return executeTerminateJob(inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown sub-agent tool: \(toolId)")
        }
    }
    
    // MARK: - Agent Types
    
    enum AgentType: String {
        case scout = "scout"
        case mechanic = "mechanic"
        case designer = "designer"
        
        var displayName: String {
            switch self {
            case .scout: return "Scout"
            case .mechanic: return "Mechanic"
            case .designer: return "Designer"
            }
        }
        
        var description: String {
            switch self {
            case .scout: return "Read-only reconnaissance agent for exploration"
            case .mechanic: return "Read+write agent for modifications and fixes"
            case .designer: return "Meta-reasoning agent for planning and architecture"
            }
        }
    }
    
    // MARK: - Spawn Agent
    
    private func executeSpawnAgent(type: AgentType, inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsedInputs = parseJSONQuery(inputs)
        
        guard let task = parsedInputs["task"] as? String else {
            return ToolResultV2.failure(
                toolId: "spawn_\(type.rawValue)",
                error: "Missing 'task' parameter describing what the \(type.displayName) should do"
            )
        }
        
        let contextTags = (parsedInputs["context_tags"] as? [String]) ?? []
        let modelTier = (parsedInputs["model_tier"] as? String) ?? (type == .designer ? "capable" : "fast")
        
        logger.info("Spawning \(type.displayName): task=\(task.prefix(50))..., tier=\(modelTier)")
        
        // Generate a job ID
        let jobId = "job-\(UUID().uuidString.prefix(8))"
        
        // Note: Full implementation would integrate with an actual sub-agent orchestration system
        // For now, we return a job ID and status that can be tracked
        
        return ToolResultV2.success(
            toolId: "spawn_\(type.rawValue)",
            output: """
            \(type.displayName) spawned successfully.
            
            **Job ID:** \(jobId)
            **Task:** \(task)
            **Model Tier:** \(modelTier)
            **Context Tags:** \(contextTags.isEmpty ? "none" : contextTags.joined(separator: ", "))
            
            Use `query_job_status` with this job ID to check progress.
            Results will be available in the agent's isolated silo.
            """,
            structured: [
                "jobId": jobId,
                "agentType": type.rawValue,
                "status": "spawned"
            ]
        )
    }
    
    // MARK: - Query Job Status
    
    private func executeQueryJobStatus(inputs: [String: Any]) -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? "all"
        
        logger.info("Querying job status: \(query)")
        
        // Note: Full implementation would query actual job tracking
        // For now, return placeholder information
        
        return ToolResultV2.success(
            toolId: "query_job_status",
            output: """
            # Job Status
            
            No active jobs found.
            
            Use `spawn_scout`, `spawn_mechanic`, or `spawn_designer` to create new agent jobs.
            """,
            structured: [
                "activeJobs": 0,
                "completedJobs": 0
            ]
        )
    }
    
    // MARK: - Accept Job Result
    
    private func executeAcceptJobResult(inputs: [String: Any]) -> ToolResultV2 {
        let parsedInputs = parseJSONQuery(inputs)
        
        guard let jobId = parsedInputs["job_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "accept_job_result",
                error: "Missing 'job_id' parameter"
            )
        }
        
        let reasoning = (parsedInputs["reasoning"] as? String) ?? ""
        let qualityScore = (parsedInputs["quality_score"] as? Double) ?? 0.8
        let promoteToMemory = (parsedInputs["promote_to_memory"] as? Bool) ?? false
        
        logger.info("Accepting job result: \(jobId)")
        
        // Note: Full implementation would integrate with silo management
        
        return ToolResultV2.success(
            toolId: "accept_job_result",
            output: """
            Job result accepted.
            
            **Job ID:** \(jobId)
            **Quality Score:** \(String(format: "%.1f", qualityScore))
            **Promoted to Memory:** \(promoteToMemory ? "Yes" : "No")
            """,
            structured: [
                "jobId": jobId,
                "accepted": true
            ]
        )
    }
    
    // MARK: - Terminate Job
    
    private func executeTerminateJob(inputs: [String: Any]) -> ToolResultV2 {
        let parsedInputs = parseJSONQuery(inputs)
        
        guard let jobId = parsedInputs["job_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "terminate_job",
                error: "Missing 'job_id' parameter"
            )
        }
        
        let reason = (parsedInputs["reason"] as? String) ?? "User requested termination"
        
        logger.info("Terminating job: \(jobId) - \(reason)")
        
        return ToolResultV2.success(
            toolId: "terminate_job",
            output: "Job \(jobId) terminated.\nReason: \(reason)",
            structured: [
                "jobId": jobId,
                "terminated": true
            ]
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
