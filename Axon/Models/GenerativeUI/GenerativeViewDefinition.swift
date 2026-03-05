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

/// A saved generative view definition with metadata
struct GenerativeViewDefinition: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var root: GenerativeUINode
    var source: GenerativeViewSource
    var thumbnailBase64: String?

    // MARK: - Convenience Initializers

    /// Create a new user view with default empty layout
    static func newUserView(name: String = "Untitled View") -> GenerativeViewDefinition {
        GenerativeViewDefinition(
            id: UUID(),
            name: name,
            createdAt: Date(),
            updatedAt: Date(),
            root: .vstack(alignment: "leading", spacing: 16, children: [
                .text("New View", font: "titleLarge", color: "textPrimary"),
                .text("Tap Edit to start building", font: "bodyMedium", color: "textSecondary")
            ]),
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
        countNodes(root)
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
