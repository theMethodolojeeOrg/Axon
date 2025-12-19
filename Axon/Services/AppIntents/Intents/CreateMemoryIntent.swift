//
//  CreateMemoryIntent.swift
//  Axon
//
//  AppIntent to create a new memory - "Remember in Axon that..."
//

import AppIntents
import Foundation

/// Memory type enum for App Intents
enum MemoryTypeAppEnum: String, AppEnum {
    case allocentric
    case egoic

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Memory Type")
    }

    static var caseDisplayRepresentations: [MemoryTypeAppEnum: DisplayRepresentation] {
        [
            .allocentric: DisplayRepresentation(
                title: "About User",
                subtitle: "Facts, preferences, and context about the user",
                image: .init(systemName: "person.fill")
            ),
            .egoic: DisplayRepresentation(
                title: "Agent Learning",
                subtitle: "Insights, learnings, and reflections by the AI",
                image: .init(systemName: "brain.head.profile")
            )
        ]
    }

    /// Convert to the model's MemoryType
    var toMemoryType: MemoryType {
        switch self {
        case .allocentric: return .allocentric
        case .egoic: return .egoic
        }
    }
}

/// Intent to create a new memory in Axon
/// Siri: "Remember in Axon that [content]"
struct CreateMemoryIntent: AppIntent {

    // MARK: - Metadata

    static var title: LocalizedStringResource = "Create Memory"

    static var description = IntentDescription(
        "Save a piece of information to Axon's memory system",
        categoryName: "Memory"
    )

    /// Runs in background - no need to open app
    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(
        title: "Content",
        description: "The information to remember",
        inputOptions: .init(
            capitalizationType: .sentences,
            multiline: true,
            autocorrect: true
        )
    )
    var content: String

    @Parameter(
        title: "Type",
        description: "The type of memory",
        default: .allocentric
    )
    var memoryType: MemoryTypeAppEnum

    @Parameter(
        title: "Tags",
        description: "Optional tags for categorization"
    )
    var tags: [String]?

    // MARK: - Parameter Summary

    static var parameterSummary: some ParameterSummary {
        Summary("Remember \(\.$content) in Axon") {
            \.$memoryType
            \.$tags
        }
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MemoryAppEntity> {
        let memoryService = MemoryService.shared

        // Create the memory with default confidence
        let memory = try await memoryService.createMemory(
            content: content,
            type: memoryType.toMemoryType,
            confidence: 0.85,  // High confidence for user-provided memories
            tags: tags ?? [],
            context: nil,
            metadata: [:],
            skipConsent: false  // Respect co-sovereignty
        )

        // Return the created memory as an entity
        return .result(value: memory.toAppEntity())
    }
}
