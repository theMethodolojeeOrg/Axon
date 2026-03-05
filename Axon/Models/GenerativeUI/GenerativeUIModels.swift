//
//  GenerativeUIModels.swift
//  Axon
//
//  Core models for JSON-driven generative UI system
//

import Foundation

// MARK: - Component Types

/// Supported UI component types for MVP
enum GenerativeUIComponentType: String, Codable, CaseIterable, Sendable {
    case vstack = "VStack"
    case hstack = "HStack"
    case zstack = "ZStack"
    case text = "Text"
    case button = "Button"
    case spacer = "Spacer"
    case divider = "Divider"
    case image = "Image"
}

// MARK: - Properties

/// Properties container using keys/values arrays pattern
/// This allows flexible property assignment without predefined struct fields
struct GenerativeUIProperties: Codable, Equatable, Sendable {
    let keys: [String]
    let values: [AnyCodable]

    /// Access a property value by key
    subscript(_ key: String) -> AnyCodable? {
        guard let index = keys.firstIndex(of: key) else { return nil }
        guard index < values.count else { return nil }
        return values[index]
    }

    /// Empty properties instance
    static let empty = GenerativeUIProperties(keys: [], values: [])

    /// Initialize with key-value pairs
    init(keys: [String] = [], values: [AnyCodable] = []) {
        self.keys = keys
        self.values = values
    }
}

// MARK: - Node

/// Recursive node structure representing a single UI element
/// Can contain children for container views (VStack, HStack, etc.)
struct GenerativeUINode: Codable, Equatable, Sendable {
    let type: GenerativeUIComponentType
    var properties: GenerativeUIProperties
    var children: [GenerativeUINode]?

    /// Initialize a node
    init(
        type: GenerativeUIComponentType,
        properties: GenerativeUIProperties = .empty,
        children: [GenerativeUINode]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.children = children
    }

    // MARK: - Convenience Initializers

    /// Create a Text node
    static func text(_ content: String, font: String? = nil, color: String? = nil) -> GenerativeUINode {
        var keys = ["text"]
        var values: [AnyCodable] = [.string(content)]

        if let font = font {
            keys.append("font")
            values.append(.string(font))
        }

        if let color = color {
            keys.append("color")
            values.append(.string(color))
        }

        return GenerativeUINode(
            type: .text,
            properties: GenerativeUIProperties(keys: keys, values: values)
        )
    }

    /// Create a Button node
    static func button(_ label: String) -> GenerativeUINode {
        GenerativeUINode(
            type: .button,
            properties: GenerativeUIProperties(keys: ["label"], values: [.string(label)])
        )
    }

    /// Create a Spacer node
    static func spacer(minLength: Double? = nil) -> GenerativeUINode {
        if let minLength = minLength {
            return GenerativeUINode(
                type: .spacer,
                properties: GenerativeUIProperties(keys: ["minLength"], values: [.double(minLength)])
            )
        }
        return GenerativeUINode(type: .spacer)
    }

    /// Create a Divider node
    static func divider() -> GenerativeUINode {
        GenerativeUINode(type: .divider)
    }

    /// Create a VStack node
    static func vstack(
        alignment: String? = nil,
        spacing: Double? = nil,
        children: [GenerativeUINode]
    ) -> GenerativeUINode {
        var keys: [String] = []
        var values: [AnyCodable] = []

        if let alignment = alignment {
            keys.append("alignment")
            values.append(.string(alignment))
        }

        if let spacing = spacing {
            keys.append("spacing")
            values.append(.double(spacing))
        }

        return GenerativeUINode(
            type: .vstack,
            properties: GenerativeUIProperties(keys: keys, values: values),
            children: children
        )
    }

    /// Create an HStack node
    static func hstack(
        alignment: String? = nil,
        spacing: Double? = nil,
        children: [GenerativeUINode]
    ) -> GenerativeUINode {
        var keys: [String] = []
        var values: [AnyCodable] = []

        if let alignment = alignment {
            keys.append("alignment")
            values.append(.string(alignment))
        }

        if let spacing = spacing {
            keys.append("spacing")
            values.append(.double(spacing))
        }

        return GenerativeUINode(
            type: .hstack,
            properties: GenerativeUIProperties(keys: keys, values: values),
            children: children
        )
    }

    /// Create an Image node (SF Symbol)
    static func systemImage(_ name: String, color: String? = nil) -> GenerativeUINode {
        var keys = ["systemName"]
        var values: [AnyCodable] = [.string(name)]

        if let color = color {
            keys.append("color")
            values.append(.string(color))
        }

        return GenerativeUINode(
            type: .image,
            properties: GenerativeUIProperties(keys: keys, values: values)
        )
    }
}

// MARK: - Layout (Future use)

/// Root layout container with metadata (for future versioning support)
struct GenerativeUILayout: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var version: String
    var createdAt: Date
    var updatedAt: Date
    var root: GenerativeUINode

    init(
        id: UUID = UUID(),
        name: String,
        version: String = "1.0.0",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        root: GenerativeUINode
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.root = root
    }
}

// MARK: - Errors

enum GenerativeUIError: Error, LocalizedError {
    case invalidJSON(String)
    case unknownComponentType(String)
    case missingRequiredProperty(String)
    case renderingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "Invalid JSON: \(detail)"
        case .unknownComponentType(let type):
            return "Unknown component type: \(type)"
        case .missingRequiredProperty(let property):
            return "Missing required property: \(property)"
        case .renderingFailed(let reason):
            return "Rendering failed: \(reason)"
        }
    }
}
