//
//  MemoryHandler.swift
//  Axon
//
//  V2 Handler for memory tools: create_memory, conversation_search, reflect_on_conversation
//

import Foundation
import os.log

/// Handler for memory-related tools
///
/// Registered handlers:
/// - `memory` → create_memory, conversation_search, reflect_on_conversation
@MainActor
final class MemoryHandler: ToolHandlerV2 {

    let handlerId = "memory"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "MemoryHandler"
    )

    private let memoryService = MemoryService.shared
    private let conversationService = ConversationService.shared
    private let reflectionService = ConversationReflectionService.shared

    // MARK: - ToolHandlerV2

    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id

        switch toolId {
        case "create_memory":
            return try await executeCreateMemory(inputs: inputs, context: context)
        case "conversation_search":
            return try await executeConversationSearch(inputs: inputs, context: context)
        case "reflect_on_conversation":
            return try await executeReflectOnConversation(inputs: inputs, context: context)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown memory tool: \(toolId)")
        }
    }
    
    // MARK: - create_memory
    
    /// Create a new memory from pipe-delimited input
    /// Format: TYPE|CONFIDENCE|TAGS|CONTENT
    private func executeCreateMemory(
        inputs: [String: Any],
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        // Extract parameters - either from parsed inputs or from raw query
        let type: MemoryType
        let confidence: Double
        let tags: [String]
        let content: String
        
        if let typeStr = inputs["type"] as? String {
            // Structured inputs (already parsed)
            type = MemoryType(rawValue: typeStr) ?? .allocentric
            confidence = (inputs["confidence"] as? Double) ?? 0.8
            tags = (inputs["tags"] as? [String]) ?? []
            content = (inputs["content"] as? String) ?? ""
        } else if let query = inputs["query"] as? String {
            // Parse pipe-delimited format: TYPE|CONFIDENCE|TAGS|CONTENT
            let parts = query.components(separatedBy: "|")
            guard parts.count >= 4 else {
                return ToolResultV2.failure(
                    toolId: "create_memory",
                    error: "Invalid format. Expected: TYPE|CONFIDENCE|TAGS|CONTENT"
                )
            }
            
            type = MemoryType(rawValue: parts[0].trimmingCharacters(in: .whitespaces)) ?? .allocentric
            confidence = Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0.8
            tags = parts[2].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            content = parts[3...].joined(separator: "|").trimmingCharacters(in: .whitespaces)
        } else {
            return ToolResultV2.failure(
                toolId: "create_memory",
                error: "Missing required parameters: type, confidence, tags, content"
            )
        }
        
        // Validate
        guard !content.isEmpty else {
            return ToolResultV2.failure(
                toolId: "create_memory",
                error: "Memory content cannot be empty"
            )
        }
        
        logger.info("Creating memory: type=\(type.rawValue), confidence=\(confidence), tags=\(tags.joined(separator: ","))")
        
        do {
            let memory = try await memoryService.createMemory(
                content: content,
                type: type,
                confidence: confidence,
                tags: tags
            )
            
            return ToolResultV2.success(
                toolId: "create_memory",
                output: "Memory created successfully.\nID: \(memory.id)\nType: \(memory.type.rawValue)\nTags: \(memory.tags.joined(separator: ", "))",
                structured: [
                    "id": memory.id,
                    "type": memory.type.rawValue,
                    "content": memory.content,
                    "confidence": memory.confidence,
                    "tags": memory.tags
                ]
            )
        } catch {
            logger.error("Failed to create memory: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: "create_memory",
                error: "Failed to create memory: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - conversation_search
    
    /// Search through conversation history
    private func executeConversationSearch(
        inputs: [String: Any],
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? ""
        
        guard !query.isEmpty else {
            return ToolResultV2.failure(
                toolId: "conversation_search",
                error: "Search query cannot be empty"
            )
        }
        
        logger.info("Searching conversations: \(query)")
        
        // Use memory service's search functionality
        // This searches through stored memories with semantic matching
        let matchingMemories = memoryService.memories.filter { memory in
            memory.content.localizedCaseInsensitiveContains(query) ||
            memory.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        
        let limitedResults = Array(matchingMemories.prefix(10))
        
        if limitedResults.isEmpty {
            return ToolResultV2.success(
                toolId: "conversation_search",
                output: "No matching memories found for: \(query)"
            )
        }
        
        var output = "Found \(limitedResults.count) relevant memories:\n\n"
        for (index, memory) in limitedResults.enumerated() {
            output += "\(index + 1). [\(memory.type.rawValue)] \(memory.content.prefix(200))\n"
            output += "   Tags: \(memory.tags.joined(separator: ", "))\n\n"
        }
        
        return ToolResultV2.success(
            toolId: "conversation_search",
            output: output,
            structured: [
                "count": limitedResults.count,
                "query": query
            ]
        )
    }

    // MARK: - reflect_on_conversation

    /// Perform meta-analysis on the current conversation
    /// Analyzes model timeline, task distribution, memory usage, and pivots
    private func executeReflectOnConversation(
        inputs: [String: Any],
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        guard let conversationId = context.conversationId else {
            return ToolResultV2.failure(
                toolId: "reflect_on_conversation",
                error: "No conversation context available. This tool requires an active conversation."
            )
        }

        logger.info("Reflecting on conversation: \(conversationId)")

        // Fetch messages for this conversation
        let messages: [Message]
        do {
            messages = try await conversationService.getMessages(conversationId: conversationId, limit: 1000)
        } catch {
            logger.error("Failed to fetch messages for reflection: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: "reflect_on_conversation",
                error: "Failed to fetch conversation messages: \(error.localizedDescription)"
            )
        }

        guard !messages.isEmpty else {
            return ToolResultV2.success(
                toolId: "reflect_on_conversation",
                output: "No messages found in this conversation to reflect on."
            )
        }

        // Configure reflection options
        let options = ReflectionOptions(
            showModelTimeline: true,
            showTaskDistribution: true,
            showMemoryUsage: true,
            showPivots: true,
            showInsights: true
        )

        // Generate reflection
        let reflection = reflectionService.reflect(
            on: messages,
            conversationId: conversationId,
            options: options
        )

        // Format the reflection as readable output
        let output = reflectionService.formatReflection(reflection, options: options)

        logger.info("Reflection complete: \(reflection.messageCount) messages analyzed, \(reflection.pivots.count) pivots detected")

        return ToolResultV2.success(
            toolId: "reflect_on_conversation",
            output: output,
            structured: [
                "messageCount": reflection.messageCount,
                "pivotCount": reflection.pivots.count,
                "insightCount": reflection.insights.count,
                "modelCount": reflection.timeline.modelBreakdown.count
            ]
        )
    }
}
