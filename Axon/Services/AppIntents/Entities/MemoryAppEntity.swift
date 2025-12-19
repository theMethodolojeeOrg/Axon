//
//  MemoryAppEntity.swift
//  Axon
//
//  AppEntity wrapper for Memory model - exposes memories to Siri/Shortcuts
//

import AppIntents
import Foundation

/// Memory exposed as an AppEntity for Siri and Shortcuts integration
struct MemoryAppEntity: AppEntity {

    // MARK: - Type Display

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Memory",
            numericFormat: "\(placeholder: .int) memories"
        )
    }

    // MARK: - Properties

    var id: String

    @Property(title: "Content")
    var content: String

    @Property(title: "Type")
    var type: String

    @Property(title: "Confidence")
    var confidence: Double

    @Property(title: "Tags")
    var tags: [String]

    @Property(title: "Created")
    var createdAt: Date

    // MARK: - Display Representation

    var displayRepresentation: DisplayRepresentation {
        let truncatedContent = content.count > 60
            ? String(content.prefix(60)) + "..."
            : content

        return DisplayRepresentation(
            title: "\(truncatedContent)",
            subtitle: "\(type) • \(Int(confidence * 100))% confidence",
            image: .init(systemName: iconForType(type))
        )
    }

    // MARK: - Default Query

    static var defaultQuery = MemoryEntityQuery()

    // MARK: - Initialization

    init(
        id: String,
        content: String,
        type: String,
        confidence: Double,
        tags: [String],
        createdAt: Date
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.confidence = confidence
        self.tags = tags
        self.createdAt = createdAt
    }

    // MARK: - Helpers

    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "allocentric": return "person.fill"
        case "egoic": return "brain.head.profile"
        case "fact": return "lightbulb.fill"
        case "preference": return "heart.fill"
        case "learning": return "book.fill"
        default: return "brain"
        }
    }
}

// MARK: - Memory Extension

extension Memory {
    /// Convert Memory model to AppEntity for Siri/Shortcuts
    func toAppEntity() -> MemoryAppEntity {
        MemoryAppEntity(
            id: id,
            content: content,
            type: type.rawValue,
            confidence: confidence,
            tags: tags,
            createdAt: createdAt
        )
    }
}
