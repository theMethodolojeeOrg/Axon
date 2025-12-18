//
//  InternalThreadEntry.swift
//  Axon
//
//  Persistent internal thread entry representing agent state.
//

import Foundation

enum InternalThreadEntryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case note = "note"
    case plan = "plan"
    case selfReflection = "self_reflection"
    case heartbeatSnapshot = "heartbeat_snapshot"
    case counter = "counter"
    case system = "system"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .note: return "Note"
        case .plan: return "Plan"
        case .selfReflection: return "Self-Reflection"
        case .heartbeatSnapshot: return "Heartbeat"
        case .counter: return "Counter"
        case .system: return "System"
        }
    }

    var icon: String {
        switch self {
        case .note: return "note.text"
        case .plan: return "checklist"
        case .selfReflection: return "sparkles"
        case .heartbeatSnapshot: return "heart.text.square"
        case .counter: return "number.circle"
        case .system: return "gearshape"
        }
    }
}

enum InternalThreadVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case userVisible = "userVisible"
    case aiOnly = "aiOnly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .userVisible: return "User Visible"
        case .aiOnly: return "AI Only"
        }
    }
}

enum InternalThreadOrigin: String, Codable, CaseIterable, Identifiable, Sendable {
    case ai = "ai"
    case user = "user"
    case system = "system"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ai: return "AI"
        case .user: return "User"
        case .system: return "System"
        }
    }
}

struct InternalThreadEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let kind: InternalThreadEntryKind
    let content: String
    let tags: [String]
    let visibility: InternalThreadVisibility
    let origin: InternalThreadOrigin
    let covenantId: String?
    let deviceId: String
    let encryptionContext: String?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        kind: InternalThreadEntryKind,
        content: String,
        tags: [String] = [],
        visibility: InternalThreadVisibility = .userVisible,
        origin: InternalThreadOrigin = .ai,
        covenantId: String? = nil,
        deviceId: String,
        encryptionContext: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.content = content
        self.tags = tags
        self.visibility = visibility
        self.origin = origin
        self.covenantId = covenantId
        self.deviceId = deviceId
        self.encryptionContext = encryptionContext
    }
}
