//
//  Memory.swift
//  Axon
//
//  Memory model for the intelligent memory system
//

import Foundation

struct Memory: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let content: String
    let type: MemoryType
    let confidence: Double
    let tags: [String]
    let context: String?
    let metadata: [String: AnyCodable]
    let source: MemorySource?
    let relatedMemories: [String]?
    let createdAt: Date
    let updatedAt: Date
    let lastAccessedAt: Date?
    let accessCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case content
        case type
        case confidence
        case tags
        case context
        case metadata
        case source
        case relatedMemories
        case createdAt
        case updatedAt
        case lastAccessedAt
        case accessCount

        #if DEBUG
        static var allCases: [CodingKeys] {
            [.id, .userId, .content, .type, .confidence, .tags, .context, .metadata, .source, .relatedMemories, .createdAt, .updatedAt, .lastAccessedAt, .accessCount]
        }

        static var debugDescription: String {
            "Expected keys: " + allCases.map { $0.stringValue }.sorted().joined(separator: ", ")
        }
        #endif
    }

    init(
        id: String = UUID().uuidString,
        userId: String,
        content: String,
        type: MemoryType,
        confidence: Double,
        tags: [String] = [],
        context: String? = nil,
        metadata: [String: AnyCodable] = [:],
        source: MemorySource? = nil,
        relatedMemories: [String]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAccessedAt: Date? = nil,
        accessCount: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.content = content
        self.type = type
        self.confidence = confidence
        self.tags = tags
        self.context = context
        self.metadata = metadata
        self.source = source
        self.relatedMemories = relatedMemories
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        #if DEBUG
        let availableKeys = container.allKeys.map { $0.stringValue }.sorted()
        let expectedKeys = CodingKeys.allCases.map { $0.stringValue }.sorted()
        print("[Memory.decode] 🔍 Available keys: \(availableKeys)")
        print("[Memory.decode] 📋 Expected keys: \(expectedKeys)")
        let missingKeys = Set(expectedKeys).subtracting(Set(availableKeys))
        if !missingKeys.isEmpty {
            print("[Memory.decode] ⚠️  Missing keys: \(missingKeys.sorted())")
        }
        let extraKeys = Set(availableKeys).subtracting(Set(expectedKeys))
        if !extraKeys.isEmpty {
            print("[Memory.decode] ➕ Extra keys: \(extraKeys.sorted())")
        }
        #endif

        id = try container.decode(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        content = try container.decode(String.self, forKey: .content)
        type = try container.decode(MemoryType.self, forKey: .type)
        confidence = try container.decode(Double.self, forKey: .confidence)
        tags = try container.decode([String].self, forKey: .tags)
        context = try container.decodeIfPresent(String.self, forKey: .context)
        // Handle missing metadata by defaulting to empty dictionary
        metadata = try container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata) ?? [:]
        source = try container.decodeIfPresent(MemorySource.self, forKey: .source)
        relatedMemories = try container.decodeIfPresent([String].self, forKey: .relatedMemories)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastAccessedAt = try container.decodeIfPresent(Date.self, forKey: .lastAccessedAt)
        accessCount = try container.decodeIfPresent(Int.self, forKey: .accessCount) ?? 0

        #if DEBUG
        print("[Memory.decode] ✅ Successfully decoded memory: \(id)")
        #endif
    }

    // MARK: - Computed Properties

    private func boolMetadata(_ key: String) -> Bool? {
        guard let any = metadata[key] else { return nil }
        do {
            let data = try JSONEncoder().encode(any)
            return try JSONDecoder().decode(Bool.self, from: data)
        } catch {
            #if DEBUG
            print("[Memory] Failed to decode Bool for metadata key \(key): \(error)")
            #endif
            return nil
        }
    }

    var isPinned: Bool {
        boolMetadata("isPinned") ?? false
    }

    var isArchived: Bool {
        boolMetadata("isArchived") ?? false
    }
}

enum MemoryType: String, Codable, CaseIterable {
    // New schema (primary)
    case allocentric = "allocentric"
    case egoic = "egoic"

    // Legacy types (for backward compatibility)
    case fact = "fact"
    case procedure = "procedure"
    case context = "context"
    case relationship = "relationship"
    case question = "question"
    case insight = "insight"
    case learning = "learning"
    case preference = "preference"

    var displayName: String {
        switch self {
        case .allocentric: return "Allocentric"
        case .egoic: return "Egoic"
        case .fact: return "Fact"
        case .procedure: return "Procedure"
        case .context: return "Context"
        case .relationship: return "Relationship"
        case .question: return "Question"
        case .insight: return "Insight"
        case .learning: return "Learning"
        case .preference: return "Preference"
        }
    }

    var icon: String {
        switch self {
        case .allocentric: return "brain.head.profile"
        case .egoic: return "person.fill"
        case .fact: return "lightbulb.fill"
        case .procedure: return "list.bullet"
        case .context: return "bubble.left.and.bubble.right.fill"
        case .relationship: return "link"
        case .question: return "questionmark.circle.fill"
        case .insight: return "sparkles"
        case .learning: return "book.fill"
        case .preference: return "heart.fill"
        }
    }

    /// Returns true if this is a new-schema type (allocentric/egoic)
    var isNewSchema: Bool {
        switch self {
        case .allocentric, .egoic:
            return true
        default:
            return false
        }
    }

    /// Maps legacy types to new schema
    var toNewSchema: MemoryType {
        switch self {
        case .allocentric, .egoic:
            return self
        case .fact, .preference, .context, .relationship:
            return .allocentric
        case .question, .insight, .learning, .procedure:
            return .egoic
        }
    }
}

struct MemorySource: Codable, Equatable {
    let conversationId: String?
    let messageId: String?
    let timestamp: Date

    init(conversationId: String? = nil, messageId: String? = nil, timestamp: Date = Date()) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.timestamp = timestamp
    }

    // Custom decoder to handle both object format and legacy string format
    init(from decoder: Decoder) throws {
        // Try to decode as object first
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
            messageId = try container.decodeIfPresent(String.self, forKey: .messageId)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
        } else {
            // If that fails, it might be a legacy string format (like "ai")
            // In this case, we'll just create an empty source
            #if DEBUG
            let container = try decoder.singleValueContainer()
            let legacyValue = try? container.decode(String.self)
            print("[MemorySource.decode] ⚠️  Legacy string source detected: \(legacyValue ?? "unknown"), creating empty source")
            #endif
            self.conversationId = nil
            self.messageId = nil
            self.timestamp = Date()
        }
    }

    enum CodingKeys: String, CodingKey {
        case conversationId
        case messageId
        case timestamp
    }
}

struct MemoryListResponse: Codable {
    let memories: [Memory]
    let pagination: PaginationMeta
}

struct MemorySearchRequest: Codable {
    let query: String
    let types: [MemoryType]?
    let limit: Int
    let minConfidence: Double?

    init(query: String, types: [MemoryType]? = nil, limit: Int = 10, minConfidence: Double? = nil) {
        self.query = query
        self.types = types
        self.limit = limit
        self.minConfidence = minConfidence
    }
}
