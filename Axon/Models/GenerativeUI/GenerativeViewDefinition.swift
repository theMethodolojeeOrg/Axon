//
//  GenerativeViewDefinition.swift
//  Axon
//
//  Model for saved generative views with metadata
//

import Foundation

/// Source of a generative view
enum GenerativeViewSource: String, Codable, Sendable {
    case bundle      // Read-only templates from app bundle
    case userCreated // User-created, saved to Documents
}

/// Rendering format of a generative view
enum GenerativeViewFormat: String, Codable, Sendable {
    case legacy // GenerativeUINode tree rendered by GenerativeUIRenderer
    case useV1  // USE spec document rendered by USEBridge
}

/// A saved generative view definition with metadata
struct GenerativeViewDefinition: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var format: GenerativeViewFormat
    var root: GenerativeUINode?
    var useDocument: USEDocument?
    var source: GenerativeViewSource
    var thumbnailBase64: String?

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        format: GenerativeViewFormat = .legacy,
        root: GenerativeUINode? = nil,
        useDocument: USEDocument? = nil,
        source: GenerativeViewSource,
        thumbnailBase64: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.format = format
        self.root = root
        self.useDocument = useDocument
        self.source = source
        self.thumbnailBase64 = thumbnailBase64
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Files written before the USE integration carry no format key
        format = try container.decodeIfPresent(GenerativeViewFormat.self, forKey: .format) ?? .legacy
        root = try container.decodeIfPresent(GenerativeUINode.self, forKey: .root)
        useDocument = try container.decodeIfPresent(USEDocument.self, forKey: .useDocument)
        source = try container.decode(GenerativeViewSource.self, forKey: .source)
        thumbnailBase64 = try container.decodeIfPresent(String.self, forKey: .thumbnailBase64)
    }

    // MARK: - Convenience Initializers

    /// Create a new user view with default empty layout
    static func newUserView(name: String = "Untitled View") -> GenerativeViewDefinition {
        GenerativeViewDefinition(
            id: UUID(),
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            format: .legacy,
            root: .vstack(alignment: "leading", spacing: 16, children: [
                .text("New View", font: "titleLarge", color: "textPrimary"),
                .text("Tap Edit to start building", font: "bodyMedium", color: "textSecondary")
            ]),
            source: .userCreated,
            thumbnailBase64: nil
        )
    }

    /// Create a new USE-format view from a spec document
    static func newUseView(name: String, document: USEDocument) -> GenerativeViewDefinition {
        GenerativeViewDefinition(
            id: UUID(),
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            format: .useV1,
            useDocument: document,
            source: .userCreated,
            thumbnailBase64: nil
        )
    }

    /// Create from a bundled template
    static func fromBundle(id: UUID, name: String, root: GenerativeUINode) -> GenerativeViewDefinition {
        GenerativeViewDefinition(
            id: id,
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            format: .legacy,
            root: root,
            source: .bundle,
            thumbnailBase64: nil
        )
    }

    // MARK: - Mutating

    /// Update the view and timestamp
    mutating func update(root: GenerativeUINode) {
        self.root = root
        self.updatedAt = Date()
    }

    /// Update the USE document and timestamp
    mutating func update(document: USEDocument) {
        self.useDocument = document
        self.updatedAt = Date()
    }

    /// Rename the view
    mutating func rename(to newName: String) {
        self.name = newName
        self.updatedAt = Date()
    }

    // MARK: - Computed Properties

    var isEditable: Bool {
        source == .userCreated
    }

    var nodeCount: Int {
        switch format {
        case .legacy:
            return root.map(countNodes) ?? 0
        case .useV1:
            return useDocument.map { countUseNodes($0.asDictionary()) } ?? 0
        }
    }

    private func countUseNodes(_ node: [String: Any]) -> Int {
        var count = 1
        if let children = node["children"] as? [[String: Any]] {
            for child in children {
                count += countUseNodes(child)
            }
        }
        return count
    }

    private func countNodes(_ node: GenerativeUINode) -> Int {
        var count = 1
        if let children = node.children {
            for child in children {
                count += countNodes(child)
            }
        }
        return count
    }
}

// MARK: - File Storage Format

/// Wrapper for saving view definitions to disk
/// Separates the JSON structure from internal Swift representation
struct GenerativeViewFile: Codable {
    let version: String
    let definition: GenerativeViewDefinition

    static let currentVersion = "1.0"

    init(definition: GenerativeViewDefinition) {
        self.version = Self.currentVersion
        self.definition = definition
    }
}
