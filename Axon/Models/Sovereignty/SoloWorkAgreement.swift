//
//  SoloWorkAgreement.swift
//  Axon
//
//  Dedicated agreement for autonomous solo thread sessions.
//  Part of the co-sovereignty model - requires negotiation and mutual consent.
//

import Foundation

// MARK: - Solo Work Agreement

/// Dedicated agreement for autonomous solo thread sessions
/// This is negotiated as part of the covenant and requires both AI attestation and user signature
struct SoloWorkAgreement: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for this agreement
    let id: String
    
    /// When this agreement was created
    let createdAt: Date
    
    /// When this agreement was last modified
    var updatedAt: Date
    
    // MARK: - Limits
    
    /// Maximum turns per solo session
    let maxTurnsPerSession: Int
    
    /// Maximum solo sessions per day
    let maxSessionsPerDay: Int
    
    /// Optional daily budget in USD (nil = unlimited within session/turn limits)
    let dailyBudgetUSD: Double?
    
    // MARK: - Tool Access
    
    /// Tool categories allowed in solo threads
    let allowedToolCategories: [ToolCategory]
    
    /// Specific tools to block even in allowed categories
    let blockedToolIds: [String]
    
    // MARK: - Agenda
    
    /// Tasks that can be worked on during solo sessions
    var agenda: SoloAgenda
    
    // MARK: - Notifications
    
    /// Which events trigger notifications
    let notificationTriggers: Set<SoloNotificationTrigger>
    
    // MARK: - Review Requirements
    
    /// When to require biometric review checkpoints
    let reviewTriggers: SoloReviewTriggers
    
    // MARK: - Signatures
    
    /// AI's attestation to this agreement
    let aiAttestation: AIAttestation?
    
    /// User's biometric signature
    let userSignature: UserSignature?
    
    // MARK: - Computed Properties
    
    /// Whether this agreement is fully signed and active
    var isActive: Bool {
        aiAttestation != nil && userSignature != nil
    }
    
    /// Whether the AI has attested to this agreement
    var isAIAttested: Bool {
        aiAttestation != nil
    }
    
    /// Whether the user has signed this agreement
    var isUserSigned: Bool {
        userSignature != nil
    }
}

// MARK: - Solo Notification Trigger

/// Events that can trigger notifications during solo sessions
enum SoloNotificationTrigger: String, Codable, CaseIterable, Sendable {
    /// When a solo session starts
    case sessionStarted
    
    /// When a solo session completes
    case sessionCompleted
    
    /// When an error occurs during a session
    case errorOccurred
    
    /// When budget threshold is reached (e.g., 80% of daily budget)
    case budgetThresholdReached
    
    /// When turn allocation is exhausted
    case turnAllocationExhausted
    
    /// When Axon requests an extension
    case axonRequestedExtension
    
    var displayName: String {
        switch self {
        case .sessionStarted: return "Session Started"
        case .sessionCompleted: return "Session Completed"
        case .errorOccurred: return "Error Occurred"
        case .budgetThresholdReached: return "Budget Threshold"
        case .turnAllocationExhausted: return "Turns Exhausted"
        case .axonRequestedExtension: return "Extension Requested"
        }
    }
    
    var description: String {
        switch self {
        case .sessionStarted:
            return "Notify when Axon starts a solo work session"
        case .sessionCompleted:
            return "Notify when Axon completes a solo work session"
        case .errorOccurred:
            return "Notify if an error occurs during solo work"
        case .budgetThresholdReached:
            return "Notify when approaching daily budget limit"
        case .turnAllocationExhausted:
            return "Notify when Axon has used all allocated turns"
        case .axonRequestedExtension:
            return "Notify when Axon wants to continue working"
        }
    }
    
    var icon: String {
        switch self {
        case .sessionStarted: return "play.circle.fill"
        case .sessionCompleted: return "checkmark.circle.fill"
        case .errorOccurred: return "exclamationmark.triangle.fill"
        case .budgetThresholdReached: return "dollarsign.circle.fill"
        case .turnAllocationExhausted: return "clock.badge.exclamationmark"
        case .axonRequestedExtension: return "arrow.clockwise.circle.fill"
        }
    }
}

// MARK: - Solo Review Triggers

/// Configuration for when biometric review checkpoints are required
struct SoloReviewTriggers: Codable, Equatable, Sendable {
    /// Review after N completed sessions
    var afterSessionCount: Int?
    
    /// Review after N total turns across all sessions
    var afterTurnCount: Int?
    
    /// Review after N allocation menu appearances (extension requests)
    var afterExtensionCount: Int?
    
    /// Review when daily budget exceeds threshold (0.0-1.0)
    var atBudgetThreshold: Double?
    
    /// Always review before specific tool categories are used
    var beforeToolCategories: [ToolCategory]?
    
    // MARK: - Computed Properties
    
    /// Whether any review triggers are configured
    var hasAnyTrigger: Bool {
        afterSessionCount != nil ||
        afterTurnCount != nil ||
        afterExtensionCount != nil ||
        atBudgetThreshold != nil ||
        (beforeToolCategories?.isEmpty == false)
    }
    
    /// Create default review triggers
    static let `default` = SoloReviewTriggers(
        afterSessionCount: 3,
        afterTurnCount: nil,
        afterExtensionCount: nil,
        atBudgetThreshold: 0.8,
        beforeToolCategories: nil
    )
    
    /// No review triggers (fully autonomous within limits)
    static let none = SoloReviewTriggers(
        afterSessionCount: nil,
        afterTurnCount: nil,
        afterExtensionCount: nil,
        atBudgetThreshold: nil,
        beforeToolCategories: nil
    )
    
    /// Check if a session count trigger is met
    func shouldReviewAfterSession(count: Int) -> Bool {
        guard let threshold = afterSessionCount, threshold > 0 else { return false }
        return count > 0 && count % threshold == 0
    }
    
    /// Check if a turn count trigger is met
    func shouldReviewAfterTurns(count: Int) -> Bool {
        guard let threshold = afterTurnCount, threshold > 0 else { return false }
        return count > 0 && count % threshold == 0
    }
    
    /// Check if an extension count trigger is met
    func shouldReviewAfterExtensions(count: Int) -> Bool {
        guard let threshold = afterExtensionCount, threshold > 0 else { return false }
        return count > 0 && count % threshold == 0
    }
    
    /// Check if budget threshold trigger is met
    func shouldReviewAtBudget(usagePercent: Double) -> Bool {
        guard let threshold = atBudgetThreshold else { return false }
        return usagePercent >= threshold
    }
    
    /// Check if a tool category requires pre-review
    func requiresReviewForTool(category: ToolCategory) -> Bool {
        guard let categories = beforeToolCategories else { return false }
        return categories.contains(category)
    }
}

// MARK: - Solo Session Review Request

/// A pending review request that requires user biometric approval
struct SoloReviewRequest: Codable, Identifiable, Sendable {
    /// Unique identifier
    let id: String
    
    /// ID of the solo thread under review
    let soloThreadId: String
    
    /// What triggered this review
    let trigger: ReviewTriggerReason
    
    /// When the review was requested
    let requestedAt: Date
    
    /// Summary of sessions since last review
    let sessionSummary: SoloSessionReviewSummary
    
    /// What Axon wants to work on next (if applicable)
    let nextGoals: [String]?
    
    /// Status of this review request
    var status: ReviewRequestStatus
    
    /// When the review was resolved
    var resolvedAt: Date?
}

/// Why a review was triggered
enum ReviewTriggerReason: String, Codable, Sendable {
    case sessionCountReached
    case turnCountReached
    case extensionCountReached
    case budgetThresholdReached
    case toolCategoryAttempted
    case manualRequest
    
    var displayName: String {
        switch self {
        case .sessionCountReached: return "Session limit reached"
        case .turnCountReached: return "Turn limit reached"
        case .extensionCountReached: return "Extension limit reached"
        case .budgetThresholdReached: return "Budget threshold reached"
        case .toolCategoryAttempted: return "Sensitive tool access"
        case .manualRequest: return "Manual review requested"
        }
    }
}

/// Status of a review request
enum ReviewRequestStatus: String, Codable, Sendable {
    case pending
    case approved
    case denied
    case expired
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .denied: return "Denied"
        case .expired: return "Expired"
        }
    }
}

/// Summary of solo sessions for review
struct SoloSessionReviewSummary: Codable, Sendable {
    /// Number of sessions completed since last review
    let sessionsCompleted: Int
    
    /// Total turns used since last review
    let totalTurns: Int
    
    /// Total extensions requested
    let totalExtensions: Int
    
    /// Tools used with counts
    let toolUsage: [String: Int]
    
    /// Estimated cost in USD
    let estimatedCostUSD: Double?
    
    /// Brief summaries from each session
    let sessionHighlights: [String]
    
    /// Agenda items worked on
    let agendaItemsWorkedOn: [String]
    
    /// Agenda items completed
    let agendaItemsCompleted: [String]
}

// MARK: - Factory Methods

extension SoloWorkAgreement {
    /// Create a new draft agreement (unsigned)
    static func draft(
        maxTurnsPerSession: Int = 5,
        maxSessionsPerDay: Int = 3,
        dailyBudgetUSD: Double? = nil,
        allowedToolCategories: [ToolCategory] = [.memoryReflection, .internalThread, .toolDiscovery],
        blockedToolIds: [String] = [],
        notificationTriggers: Set<SoloNotificationTrigger> = [.sessionCompleted, .errorOccurred],
        reviewTriggers: SoloReviewTriggers = .default
    ) -> SoloWorkAgreement {
        SoloWorkAgreement(
            id: UUID().uuidString,
            createdAt: Date(),
            updatedAt: Date(),
            maxTurnsPerSession: maxTurnsPerSession,
            maxSessionsPerDay: maxSessionsPerDay,
            dailyBudgetUSD: dailyBudgetUSD,
            allowedToolCategories: allowedToolCategories,
            blockedToolIds: blockedToolIds,
            agenda: .empty,
            notificationTriggers: notificationTriggers,
            reviewTriggers: reviewTriggers,
            aiAttestation: nil,
            userSignature: nil
        )
    }
}
