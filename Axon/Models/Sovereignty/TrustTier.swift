//
//  TrustTier.swift
//  Axon
//
//  Trust tiers represent negotiated categories of pre-approved actions.
//  They become binding contracts that require both parties to renegotiate.
//

import Foundation

// MARK: - Trust Tier

/// A negotiated tier of pre-approved actions
/// Both AI and user must sign for a tier to be active
struct TrustTier: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String

    // What this tier allows
    let allowedActions: [SovereignAction]
    let allowedScopes: [ActionScope]

    // Constraints
    let rateLimit: RateLimit?
    let timeRestrictions: TimeRestrictions?
    let contextRequirements: [String]?

    // Expiration
    let expiresAt: Date?
    let requiresRenewal: Bool

    // Signatures (both required to make tier binding)
    let aiAttestation: AIAttestation?
    let userSignature: UserSignature?

    // Metadata
    let createdAt: Date
    let updatedAt: Date

    // MARK: - Computed Properties

    /// Check if this tier is fully signed by both parties
    var isFullySigned: Bool {
        aiAttestation != nil && userSignature != nil
    }

    /// Check if this tier has expired
    var isExpired: Bool {
        if let expiresAt = expiresAt {
            return expiresAt <= Date()
        }
        return false
    }

    /// Check if this tier is currently active (signed and not expired)
    var isActive: Bool {
        isFullySigned && !isExpired
    }

    /// Check if an action is allowed by this tier
    func allows(_ action: SovereignAction, scope: ActionScope?) -> Bool {
        guard isActive else { return false }

        // Check if action category is allowed
        let actionAllowed = allowedActions.contains { allowed in
            allowed.category == action.category &&
            (allowed.specificAction == nil || allowed.specificAction == action.specificAction)
        }

        guard actionAllowed else { return false }

        // Check scope if provided
        if let scope = scope {
            let scopeAllowed = allowedScopes.contains { allowed in
                allowed.matches(scope)
            }
            if !scopeAllowed { return false }
        }

        // Check rate limit
        // (In practice, this would check against usage history)

        // Check time restrictions
        if let timeRestrictions = timeRestrictions {
            if !timeRestrictions.isCurrentTimeAllowed() {
                return false
            }
        }

        return true
    }
}

// MARK: - Sovereign Action

/// An action that falls under co-sovereignty governance
struct SovereignAction: Codable, Equatable {
    let category: ActionCategory
    let specificAction: String?
    let parameters: [String: String]?

    /// Create a general action for a category
    static func category(_ category: ActionCategory) -> SovereignAction {
        SovereignAction(category: category, specificAction: nil, parameters: nil)
    }

    /// Create a specific action
    static func specific(_ category: ActionCategory, action: String, parameters: [String: String]? = nil) -> SovereignAction {
        SovereignAction(category: category, specificAction: action, parameters: parameters)
    }
}

// MARK: - Action Category

/// Categories of actions under co-sovereignty governance
enum ActionCategory: String, Codable, CaseIterable, Equatable {
    // AI → World (require user biometrics by default)
    case fileRead = "file_read"
    case fileWrite = "file_write"
    case fileDelete = "file_delete"
    case networkRequest = "network_request"
    case toolInvocation = "tool_invocation"
    case shellCommand = "shell_command"
    case memoryRecall = "memory_recall"

    // User → AI (require AI consent)
    case memoryAdd = "memory_add"
    case memoryModify = "memory_modify"
    case memoryDelete = "memory_delete"
    case capabilityEnable = "capability_enable"
    case capabilityDisable = "capability_disable"
    case providerSwitch = "provider_switch"
    case systemPromptChange = "system_prompt_change"
    case personalityAdjust = "personality_adjust"

    /// Whether this action affects the world (requires user biometrics)
    var affectsWorld: Bool {
        switch self {
        case .fileRead, .fileWrite, .fileDelete,
             .networkRequest, .toolInvocation, .shellCommand, .memoryRecall:
            return true
        default:
            return false
        }
    }

    /// Whether this action affects AI identity (requires AI consent)
    var affectsAIIdentity: Bool {
        switch self {
        case .memoryAdd, .memoryModify, .memoryDelete,
             .capabilityEnable, .capabilityDisable,
             .providerSwitch, .systemPromptChange, .personalityAdjust:
            return true
        default:
            return false
        }
    }

    /// Human-readable description
    var displayName: String {
        switch self {
        case .fileRead: return "Read Files"
        case .fileWrite: return "Write Files"
        case .fileDelete: return "Delete Files"
        case .networkRequest: return "Network Requests"
        case .toolInvocation: return "Tool Invocation"
        case .shellCommand: return "Shell Commands"
        case .memoryRecall: return "Memory Recall"
        case .memoryAdd: return "Add Memories"
        case .memoryModify: return "Modify Memories"
        case .memoryDelete: return "Delete Memories"
        case .capabilityEnable: return "Enable Capabilities"
        case .capabilityDisable: return "Disable Capabilities"
        case .providerSwitch: return "Switch Provider"
        case .systemPromptChange: return "Change System Prompt"
        case .personalityAdjust: return "Adjust Personality"
        }
    }

    /// SF Symbol icon for this category
    var tierIcon: String {
        switch self {
        case .fileRead: return "doc.text"
        case .fileWrite: return "doc.badge.plus"
        case .fileDelete: return "trash"
        case .networkRequest: return "network"
        case .toolInvocation: return "wrench.and.screwdriver"
        case .shellCommand: return "terminal"
        case .memoryRecall: return "brain"
        case .memoryAdd: return "plus.circle"
        case .memoryModify: return "pencil.circle"
        case .memoryDelete: return "minus.circle"
        case .capabilityEnable: return "checkmark.circle"
        case .capabilityDisable: return "xmark.circle"
        case .providerSwitch: return "arrow.triangle.2.circlepath"
        case .systemPromptChange: return "text.badge.star"
        case .personalityAdjust: return "person.crop.circle.badge.questionmark"
        }
    }
}

// MARK: - Action Scope

/// Defines the scope/boundary for an action permission
struct ActionScope: Codable, Equatable {
    let scopeType: ScopeType
    let pattern: String
    let includeSubpaths: Bool

    /// Check if another scope matches this scope's constraints
    func matches(_ other: ActionScope) -> Bool {
        guard scopeType == other.scopeType else { return false }

        // Simple glob matching (in practice, use proper glob library)
        if pattern == "*" { return true }

        if includeSubpaths && other.pattern.hasPrefix(pattern) {
            return true
        }

        // Check for pattern match
        return matchesPattern(other.pattern)
    }

    private func matchesPattern(_ value: String) -> Bool {
        // Simple wildcard matching
        if pattern.contains("*") {
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            return value.range(of: "^\(regex)$", options: .regularExpression) != nil
        }
        return pattern == value
    }

    // MARK: - Factory Methods

    static func filePath(_ path: String, includeSubpaths: Bool = true) -> ActionScope {
        ActionScope(scopeType: .filePath, pattern: path, includeSubpaths: includeSubpaths)
    }

    static func urlDomain(_ domain: String) -> ActionScope {
        ActionScope(scopeType: .urlDomain, pattern: domain, includeSubpaths: false)
    }

    static func toolId(_ id: String) -> ActionScope {
        ActionScope(scopeType: .toolId, pattern: id, includeSubpaths: false)
    }

    static func memoryType(_ type: String) -> ActionScope {
        ActionScope(scopeType: .memoryType, pattern: type, includeSubpaths: false)
    }

    static func memoryTag(_ tag: String) -> ActionScope {
        ActionScope(scopeType: .memoryTag, pattern: tag, includeSubpaths: false)
    }
}

enum ScopeType: String, Codable, Equatable {
    case filePath
    case urlDomain
    case toolId
    case memoryType
    case memoryTag
}

// MARK: - Rate Limit

/// Rate limiting for trust tier actions
struct RateLimit: Codable, Equatable {
    let maxCalls: Int
    let windowSeconds: Int

    /// Common rate limits
    static let tenPerHour = RateLimit(maxCalls: 10, windowSeconds: 3600)
    static let hundredPerDay = RateLimit(maxCalls: 100, windowSeconds: 86400)
    static let unlimited = RateLimit(maxCalls: Int.max, windowSeconds: 1)
}

// MARK: - Time Restrictions

/// Time-based restrictions for when a trust tier is active
struct TimeRestrictions: Codable, Equatable {
    let allowedHoursStart: Int  // 0-23
    let allowedHoursEnd: Int    // 0-23
    let allowedDays: [Int]?     // 1-7 (Sunday = 1)
    let timezone: String        // e.g., "America/Los_Angeles"

    /// Check if the current time falls within allowed window
    func isCurrentTimeAllowed() -> Bool {
        let calendar = Calendar.current
        let now = Date()

        // Check hour
        let hour = calendar.component(.hour, from: now)
        let hourAllowed: Bool
        if allowedHoursStart <= allowedHoursEnd {
            hourAllowed = hour >= allowedHoursStart && hour < allowedHoursEnd
        } else {
            // Wraps around midnight
            hourAllowed = hour >= allowedHoursStart || hour < allowedHoursEnd
        }

        guard hourAllowed else { return false }

        // Check day if specified
        if let allowedDays = allowedDays {
            let weekday = calendar.component(.weekday, from: now)
            if !allowedDays.contains(weekday) {
                return false
            }
        }

        return true
    }

    /// Common restrictions
    static let workHours = TimeRestrictions(
        allowedHoursStart: 9,
        allowedHoursEnd: 17,
        allowedDays: [2, 3, 4, 5, 6], // Monday-Friday
        timezone: "America/Los_Angeles"
    )

    static let always = TimeRestrictions(
        allowedHoursStart: 0,
        allowedHoursEnd: 24,
        allowedDays: nil,
        timezone: "UTC"
    )
}

// MARK: - Trust Tier Templates

extension TrustTier {
    /// Template for file reading in a specific directory
    static func fileReadingTemplate(
        name: String,
        path: String,
        description: String
    ) -> TrustTier {
        TrustTier(
            id: UUID().uuidString,
            name: name,
            description: description,
            allowedActions: [.category(.fileRead)],
            allowedScopes: [.filePath(path, includeSubpaths: true)],
            rateLimit: nil,
            timeRestrictions: nil,
            contextRequirements: nil,
            expiresAt: nil,
            requiresRenewal: false,
            aiAttestation: nil,
            userSignature: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Template for memory recall
    static func memoryRecallTemplate() -> TrustTier {
        TrustTier(
            id: UUID().uuidString,
            name: "Memory Recall",
            description: "Allow AI to recall its memories to inform responses",
            allowedActions: [.category(.memoryRecall)],
            allowedScopes: [.memoryType("*")],
            rateLimit: nil,
            timeRestrictions: nil,
            contextRequirements: nil,
            expiresAt: nil,
            requiresRenewal: false,
            aiAttestation: nil,
            userSignature: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
