//
//  SearchMemoriesIntent.swift
//  Axon
//
//  AppIntent to search memories - "What does Axon know about..."
//

import AppIntents
import Foundation

/// Intent to search Axon's memories
/// Siri: "What does Axon know about [query]"
struct SearchMemoriesIntent: AppIntent {

    // MARK: - Metadata

    static var title: LocalizedStringResource = "Search Memories"

    static var description = IntentDescription(
        "Search Axon's memory for information",
        categoryName: "Memory"
    )

    /// Runs in background - no need to open app
    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(
        title: "Search Query",
        description: "What to search for in memories"
    )
    var query: String

    @Parameter(
        title: "Memory Type",
        description: "Filter by memory type (optional)"
    )
    var memoryType: MemoryTypeAppEnum?

    @Parameter(
        title: "Limit",
        description: "Maximum number of results",
        default: 5
    )
    var limit: Int

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        Summary("Search Axon memories for \(\.$query)") {
            \.$memoryType
            \.$limit
        }
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[MemoryAppEntity]> {
        let memoryService = MemoryService.shared

        // Determine types to filter
        let types: [MemoryType]?
        if let selectedType = memoryType {
            types = [selectedType.toMemoryType]
        } else {
            types = nil
        }

        // Search memories
        let results = try await memoryService.searchMemories(
            query: query,
            types: types,
            limit: limit,
            minConfidence: nil
        )

        // Convert to app entities
        let entities = results.map { $0.toAppEntity() }

        return .result(value: entities)
    }
}
