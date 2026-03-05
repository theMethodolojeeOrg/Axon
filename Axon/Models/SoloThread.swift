//
//  SoloThread.swift
//  Axon
//
//  Data models for solo thread sessions - autonomous AI work in visible conversation threads.
//  Solo threads allow Axon to work autonomously while users can observe and intervene.
//

import Foundation

// MARK: - Solo Thread Configuration

/// Configuration and state for a solo thread session
struct SoloThreadConfig: Codable, Equatable, Sendable {
    /// ID of the heartbeat that originated this session (if any)
    let originatingHeartbeatId: String?
    
    /// Current status of the solo session
    var status: SoloThreadStatus
    
    /// Number of turns allocated for this session
    var turnsAllocated: Int
    
    /// Number of turns used so far
    var turnsUsed: Int
    
    /// When the session started
    var startedAt: Date
    
    /// When the session completed (if applicable)
    var completedAt: Date?
    
    /// Why the session ended (if applicable)
    var completionReason: SoloCompletionReason?
    
    /// Which session number today (for daily limit tracking, 1-indexed)
    var sessionIndex: Int
    
    /// Number of times Axon has requested turn extensions this session
    var extensionCount: Int = 0
    
    /// The agenda item being worked on (if any)
    var currentAgendaItemId: String?
    
    // MARK: - Computed Properties
    
    /// Remaining turns in current allocation
    var turnsRemaining: Int {
        max(0, turnsAllocated - turnsUsed)
    }
    
    /// Whether this session has used all allocated turns
    var isAtTurnBoundary: Bool {
        turnsUsed >= turnsAllocated
    }
    
    /// Duration of the session so far
    var duration: TimeInterval {
        let endDate = completedAt ?? Date()
        return endDate.timeIntervalSince(startedAt)
    }
}

// MARK: - Solo Thread Status

/// Current status of a solo thread session
enum SoloThreadStatus: String, Codable, CaseIterable, Sendable {
    /// Currently executing turns
    case active
    
    /// User paused or awaiting next allocation decision
    case paused
    
    /// Axon concluded the session
    case completed
    
    /// User intervened and converted to normal conversation
    case userTookOver
    
    /// Daily budget exhausted
    case budgetExhausted
    
    /// An error occurred
    case error
    
    /// Awaiting biometric review approval
    case awaitingReview
    
    // MARK: - Computed Properties
    
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .userTookOver: return "User Took Over"
        case .budgetExhausted: return "Budget Exhausted"
        case .error: return "Error"
        case .awaitingReview: return "Awaiting Review"
        }
    }
    
    var icon: String {
        switch self {
        case .active: return "bolt.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .userTookOver: return "person.crop.circle.badge.checkmark"
        case .budgetExhausted: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .awaitingReview: return "hourglass.circle.fill"
        }
    }
    
    /// Whether the session is still potentially running
    var isTerminal: Bool {
        switch self {
        case .active, .paused, .awaitingReview:
            return false
        case .completed, .userTookOver, .budgetExhausted, .error:
            return true
        }
    }
}

// MARK: - Solo Completion Reason

/// Why a solo thread session ended
enum SoloCompletionReason: String, Codable, Sendable {
    /// Axon chose to conclude via solo_turn_action tool
    case axonConcluded
    
    /// Hit max turns and chose not to extend
    case turnLimitReached
    
    /// User took over the conversation
    case userIntervened
    
    /// Daily budget exhausted
    case budgetExhausted
    
    /// An error occurred during execution
    case errorOccurred
    
    /// User explicitly paused the session
    case userPaused
    
    /// User denied continuation at review checkpoint
    case reviewDenied
    
    /// Session timed out (device sleep, app backgrounded, etc.)
    case timeout
    
    var displayName: String {
        switch self {
        case .axonConcluded: return "Axon concluded"
        case .turnLimitReached: return "Turn limit reached"
        case .userIntervened: return "User took over"
        case .budgetExhausted: return "Budget exhausted"
        case .errorOccurred: return "Error occurred"
        case .userPaused: return "User paused"
        case .reviewDenied: return "Review denied"
        case .timeout: return "Timed out"
        }
    }
}

// MARK: - Turn Allocation Menu

/// The structured context presented to Axon at turn allocation boundaries
struct SoloTurnAllocationMenu: Codable, Sendable {
    /// Turns used in current session
    let turnsUsed: Int
    
    /// Turns originally allocated
    let turnsAllocated: Int
    
    /// Remaining sessions available today
    let remainingSessionsToday: Int
    
    /// Maximum sessions per day
    let maxSessionsPerDay: Int
    
    /// Daily budget in USD (if configured)
    let dailyBudgetUSD: Double?
    
    /// Amount spent today in USD (if tracking)
    let spentTodayUSD: Double?
    
    /// Estimated cost of extending (if known)
    let estimatedExtensionCostUSD: Double?
    
    /// Available actions with their descriptions
    let options: [SoloTurnOption]
    
    // MARK: - Computed Properties
    
    /// Budget usage percentage (0.0-1.0)
    var budgetUsagePercent: Double? {
        guard let budget = dailyBudgetUSD, let spent = spentTodayUSD, budget > 0 else {
            return nil
        }
        return spent / budget
    }
    
    /// Whether extending would exceed budget
    var wouldExceedBudget: Bool {
        guard let budget = dailyBudgetUSD,
              let spent = spentTodayUSD,
              let cost = estimatedExtensionCostUSD else {
            return false
        }
        return (spent + cost) > budget
    }
    
    /// Format for display in the allocation prompt
    func formattedPrompt() -> String {
        var lines: [String] = []
        
        lines.append("SOLO SESSION CHECKPOINT")
        lines.append("")
        lines.append("Session Status:")
        lines.append("- Turns used: \(turnsUsed) / \(turnsAllocated) allocated")
        lines.append("- Remaining sessions today: \(remainingSessionsToday) of \(maxSessionsPerDay)")
        
        if let budget = dailyBudgetUSD, let spent = spentTodayUSD {
            let percent = Int((spent / budget) * 100)
            lines.append("- Daily budget used: $\(String(format: "%.2f", spent)) / $\(String(format: "%.2f", budget)) (\(percent)%)")
        }
        
        if let cost = estimatedExtensionCostUSD {
            lines.append("- Extending would use: ~$\(String(format: "%.2f", cost)) (estimated \(turnsAllocated) turns)")
        }
        
        lines.append("")
        lines.append("Available Actions:")
        for (index, option) in options.enumerated() {
            lines.append("\(index + 1). \(option.action.rawValue) - \(option.description)")
        }
        
        lines.append("")
        lines.append("Respond using the solo_turn_action tool with your choice and reasoning.")
        
        return lines.joined(separator: "\n")
    }
}

/// A single option in the turn allocation menu
struct SoloTurnOption: Codable, Sendable {
    /// The action this option represents
    let action: SoloTurnAction
    
    /// Human-readable description
    let description: String
    
    /// How many turns would be granted (for extend action)
    let turnsGranted: Int?
    
    /// Whether this action is currently available
    let isAvailable: Bool
    
    /// Reason why not available (if applicable)
    let unavailableReason: String?
}

/// Actions Axon can take at a turn allocation boundary
enum SoloTurnAction: String, Codable, Sendable {
    /// Request more turns to continue working
    case extend
    
    /// Mark session as complete
    case conclude
    
    /// Pause until next heartbeat trigger
    case pause
    
    /// Send notification to user and conclude
    case notify
    
    var displayName: String {
        switch self {
        case .extend: return "Extend"
        case .conclude: return "Conclude"
        case .pause: return "Pause"
        case .notify: return "Notify & Conclude"
        }
    }
}

// MARK: - Solo Turn Action Response

/// The response from Axon when calling the solo_turn_action tool
struct SoloTurnActionResponse: Codable, Sendable {
    /// The action chosen
    let action: SoloTurnAction
    
    /// Reasoning for the choice
    let reasoning: String
    
    /// What Axon plans to work on next (for extend action)
    let nextGoal: String?
    
    /// Optional summary of work completed (for conclude/notify actions)
    let sessionSummary: String?
}

// MARK: - Session Statistics

/// Statistics for a solo thread session (for review UI)
struct SoloSessionStatistics: Codable, Sendable {
    let sessionId: String
    let turnsCompleted: Int
    let extensionsRequested: Int
    let toolsUsed: [String: Int]  // Tool ID -> usage count
    let estimatedTokensUsed: Int?
    let estimatedCostUSD: Double?
    let duration: TimeInterval
    let completionReason: SoloCompletionReason?
}

// MARK: - Factory Methods

extension SoloThreadConfig {
    /// Create a new solo thread configuration for a fresh session
    static func newSession(
        heartbeatId: String? = nil,
        turnsAllocated: Int,
        sessionIndex: Int,
        agendaItemId: String? = nil
    ) -> SoloThreadConfig {
        SoloThreadConfig(
            originatingHeartbeatId: heartbeatId,
            status: .active,
            turnsAllocated: turnsAllocated,
            turnsUsed: 0,
            startedAt: Date(),
            completedAt: nil,
            completionReason: nil,
            sessionIndex: sessionIndex,
            extensionCount: 0,
            currentAgendaItemId: agendaItemId
        )
    }
}

extension SoloTurnAllocationMenu {
    /// Create a standard allocation menu with default options
    static func standard(
        config: SoloThreadConfig,
        remainingSessionsToday: Int,
        maxSessionsPerDay: Int,
        dailyBudgetUSD: Double? = nil,
        spentTodayUSD: Double? = nil,
        estimatedExtensionCostUSD: Double? = nil
    ) -> SoloTurnAllocationMenu {
        let canExtend = remainingSessionsToday > 0 &&
            (dailyBudgetUSD == nil || (spentTodayUSD ?? 0) + (estimatedExtensionCostUSD ?? 0) <= dailyBudgetUSD!)
        
        let options: [SoloTurnOption] = [
            SoloTurnOption(
                action: .extend,
                description: "Request \(config.turnsAllocated) more turns (within daily limits)",
                turnsGranted: config.turnsAllocated,
                isAvailable: canExtend,
                unavailableReason: canExtend ? nil : "Daily limit or budget reached"
            ),
            SoloTurnOption(
                action: .conclude,
                description: "Mark session complete, log summary",
                turnsGranted: nil,
                isAvailable: true,
                unavailableReason: nil
            ),
            SoloTurnOption(
                action: .pause,
                description: "Pause until next heartbeat trigger",
                turnsGranted: nil,
                isAvailable: true,
                unavailableReason: nil
            ),
            SoloTurnOption(
                action: .notify,
                description: "Send notification to user and conclude",
                turnsGranted: nil,
                isAvailable: true,
                unavailableReason: nil
            )
        ]
        
        return SoloTurnAllocationMenu(
            turnsUsed: config.turnsUsed,
            turnsAllocated: config.turnsAllocated,
            remainingSessionsToday: remainingSessionsToday,
            maxSessionsPerDay: maxSessionsPerDay,
            dailyBudgetUSD: dailyBudgetUSD,
            spentTodayUSD: spentTodayUSD,
            estimatedExtensionCostUSD: estimatedExtensionCostUSD,
            options: options
        )
    }
}
