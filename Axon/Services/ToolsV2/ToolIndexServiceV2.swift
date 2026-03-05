//
//  ToolIndexServiceV2.swift
//  Axon
//
//  Search index and system prompt generation for V2 tools.
//  Provides the primary interface for tool discovery and AI context building.
//

import Foundation
import Combine
import os.log

// MARK: - Tool Index Service

/// Service for indexing, searching, and generating prompts for V2 tools
@MainActor
final class ToolIndexServiceV2: ObservableObject {

    // MARK: - Singleton

    static let shared = ToolIndexServiceV2()

    // MARK: - Dependencies

    private let pluginLoader = ToolPluginLoader.shared

    // MARK: - Published State

    /// Cached search index (tool ID → searchable text)
    @Published private(set) var searchIndex: [String: String] = [:]

    /// Tools grouped by category
    @Published private(set) var toolsByCategory: [ToolCategoryV2: [LoadedTool]] = [:]

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ToolIndexServiceV2"
    )

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        // Rebuild index when loaded tools change
        pluginLoader.$loadedTools
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tools in
                self?.rebuildIndex(from: tools)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API: Search

    /// Search tools by query string
    /// - Parameters:
    ///   - query: Search query
    ///   - enabledOnly: If true, only return enabled tools
    /// - Returns: Matching tools sorted by relevance
    func searchTools(query: String, enabledOnly: Bool = false) -> [LoadedTool] {
        let lowercaseQuery = query.lowercased().trimmingCharacters(in: .whitespaces)

        if lowercaseQuery.isEmpty {
            return enabledOnly
                ? pluginLoader.loadedTools.filter { $0.isEnabled }
                : pluginLoader.loadedTools
        }

        return pluginLoader.loadedTools.filter { tool in
            if enabledOnly && !tool.isEnabled { return false }

            // Check the prebuilt search index
            if let searchText = searchIndex[tool.id],
               searchText.contains(lowercaseQuery) {
                return true
            }

            return false
        }
    }

    /// Filter tools by category
    func tools(for category: ToolCategoryV2, enabledOnly: Bool = false) -> [LoadedTool] {
        let categoryTools = toolsByCategory[category] ?? []
        return enabledOnly ? categoryTools.filter { $0.isEnabled } : categoryTools
    }

    /// Get all enabled tools
    var enabledTools: [LoadedTool] {
        pluginLoader.loadedTools.filter { $0.isEnabled }
    }

    /// Get tools by source
    func tools(from source: ToolSource) -> [LoadedTool] {
        pluginLoader.loadedTools.filter { $0.source == source }
    }

    /// Get tool count per category
    func categoryStats() -> [ToolCategoryV2: (total: Int, enabled: Int)] {
        var stats: [ToolCategoryV2: (total: Int, enabled: Int)] = [:]

        for (category, tools) in toolsByCategory {
            let enabledCount = tools.filter { $0.isEnabled }.count
            stats[category] = (total: tools.count, enabled: enabledCount)
        }

        return stats
    }

    // MARK: - Public API: System Prompt Generation

    /// Generate the full system prompt section for all enabled tools
    /// - Parameter categories: Optional filter for specific categories
    /// - Returns: Formatted system prompt string
    func generateSystemPrompt(for categories: [ToolCategoryV2]? = nil) -> String {
        let tools: [LoadedTool]
        if let categories = categories {
            tools = categories.flatMap { self.tools(for: $0, enabledOnly: true) }
        } else {
            tools = enabledTools
        }

        guard !tools.isEmpty else {
            return "<!-- No V2 tools enabled -->"
        }

        var sections: [String] = []
        sections.append("## Available Tools\n")

        // Group by category for organized output
        let grouped = Dictionary(grouping: tools) { $0.manifest.tool.category }

        for category in ToolCategoryV2.allCases {
            guard let categoryTools = grouped[category], !categoryTools.isEmpty else { continue }

            sections.append("### \(category.displayName)\n")

            for tool in categoryTools.sorted(by: { $0.id < $1.id }) {
                if let promptSection = tool.manifest.ai?.systemPromptSection {
                    sections.append(promptSection)
                } else {
                    // Generate fallback prompt from manifest
                    sections.append(generateFallbackPrompt(for: tool.manifest))
                }
                sections.append("")
            }
        }

        return sections.joined(separator: "\n")
    }

    /// Generate prompt for a single tool
    func generatePrompt(for toolId: String) -> String? {
        guard let tool = pluginLoader.loadedTools.first(where: { $0.id == toolId }) else {
            return nil
        }

        if let promptSection = tool.manifest.ai?.systemPromptSection {
            return promptSection
        }

        return generateFallbackPrompt(for: tool.manifest)
    }

    // MARK: - Public API: Tool Discovery (for handlers)

    /// Get tool details for discovery handler
    func getToolDetails(toolId: String) -> ToolDetailsV2? {
        guard let tool = pluginLoader.loadedTools.first(where: { $0.id == toolId }) else {
            return nil
        }

        return ToolDetailsV2(
            id: tool.id,
            name: tool.manifest.tool.name,
            description: tool.manifest.tool.description,
            category: tool.manifest.tool.category.displayName,
            icon: tool.manifest.tool.icon?.resolvedIcon ?? "questionmark.circle",
            isEnabled: tool.isEnabled,
            source: tool.source.displayName,
            parameters: tool.manifest.parameters?.mapValues { param in
                ToolParameterInfoV2(
                    type: param.type.rawValue,
                    required: param.required ?? false,
                    description: param.description
                )
            },
            examples: tool.manifest.ai?.usageExamples?.map { example in
                ToolExampleV2(description: example.description, input: example.input)
            }
        )
    }

    /// List all tools for discovery handler
    func listAllTools(enabledOnly: Bool = false) -> [ToolSummaryV2] {
        let tools = enabledOnly ? enabledTools : pluginLoader.loadedTools

        return tools.map { tool in
            ToolSummaryV2(
                id: tool.id,
                name: tool.manifest.tool.name,
                category: tool.manifest.tool.category.displayName,
                isEnabled: tool.isEnabled,
                requiresApproval: tool.manifest.tool.effectiveRequiresApproval
            )
        }.sorted { $0.id < $1.id }
    }

    // MARK: - Private: Index Building

    private func rebuildIndex(from tools: [LoadedTool]) {
        logger.debug("Rebuilding search index for \(tools.count) tools")

        var newIndex: [String: String] = [:]
        var newByCategory: [ToolCategoryV2: [LoadedTool]] = [:]

        for tool in tools {
            // Build searchable text
            var searchParts: [String] = [
                tool.id.lowercased(),
                tool.manifest.tool.name.lowercased(),
                tool.manifest.tool.description.lowercased(),
                tool.manifest.tool.category.rawValue.lowercased()
            ]

            // Add tags if present
            if let tags = tool.manifest.tool.tags {
                searchParts.append(contentsOf: tags.map { $0.lowercased() })
            }

            // Add parameter names
            if let params = tool.manifest.parameters {
                searchParts.append(contentsOf: params.keys.map { $0.lowercased() })
            }

            newIndex[tool.id] = searchParts.joined(separator: " ")

            // Group by category
            let category = tool.manifest.tool.category
            newByCategory[category, default: []].append(tool)
        }

        self.searchIndex = newIndex
        self.toolsByCategory = newByCategory

        logger.info("Search index rebuilt: \(tools.count) tools indexed")
    }

    // MARK: - Private: Prompt Generation

    private func generateFallbackPrompt(for manifest: ToolManifest) -> String {
        var lines: [String] = []
        lines.append("### \(manifest.tool.id)")
        lines.append(manifest.tool.description)

        if let params = manifest.parameters, !params.isEmpty {
            lines.append("\n**Parameters:**")
            for (name, param) in params.sorted(by: { $0.key < $1.key }) {
                let required = param.required == true ? " (required)" : ""
                let desc = param.description ?? ""
                lines.append("- `\(name)`: \(param.type.rawValue)\(required) — \(desc)")
            }
        }

        // Add format example
        let style = manifest.inputFormat?.style ?? .json
        switch style {
        case .pipeDelimited:
            if let fields = manifest.inputFormat?.fields {
                let example = fields.map { "{\($0)}" }.joined(separator: "|")
                lines.append("\n**Format:** `\(example)`")
            }
        case .json:
            lines.append("\n**Format:** JSON object with parameter keys")
        case .keyValue, .positional, .freeform:
            lines.append("\n**Format:** Natural language or custom format")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Discovery Types

/// Detailed tool information for discovery
struct ToolDetailsV2: Sendable {
    let id: String
    let name: String
    let description: String
    let category: String
    let icon: String
    let isEnabled: Bool
    let source: String
    let parameters: [String: ToolParameterInfoV2]?
    let examples: [ToolExampleV2]?
}

/// Parameter info for discovery
struct ToolParameterInfoV2: Sendable {
    let type: String
    let required: Bool
    let description: String?
}

/// Example usage for discovery
struct ToolExampleV2: Sendable {
    let description: String
    let input: String
}

/// Summary for tool listing
struct ToolSummaryV2: Sendable {
    let id: String
    let name: String
    let category: String
    let isEnabled: Bool
    let requiresApproval: Bool
}
