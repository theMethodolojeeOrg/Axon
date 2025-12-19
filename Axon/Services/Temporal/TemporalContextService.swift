//
//  TemporalContextService.swift
//  Axon
//
//  Service for managing temporal symmetry between human and AI.
//  Tracks turn counts, generates temporal context for prompt injection,
//  and maintains the mutual observability contract.
//
//  Philosophy: Parallelism over asymmetry.
//  If I know your turns, you must see my time. Either we're both "on the clock"
//  or we're both in the timeless void. No surveillance.
//
//  Turn Counting: Derived from Core Data message counts (assistant role = 1 turn).
//  This is the source of truth - not incremental tracking.
//

import Foundation
import Combine
import CoreData
import os.log

// MARK: - Temporal Context

/// The temporal context to be injected into the AI's system prompt
struct TemporalContext: Equatable {
    let humanTime: Date
    let humanTimeZone: TimeZone
    let conversationTurnCount: Int
    let lifetimeTurnCount: Int
    let contextSaturationPercent: Double
    let sessionDuration: TimeInterval?
    let mode: TemporalMode

    /// Format the temporal context for system prompt injection
    func formatForPromptInjection() -> String {
        guard mode == .sync else { return "" }

        var parts: [String] = []

        // Human time
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = humanTimeZone
        let timeString = formatter.string(from: humanTime)
        let tzAbbr = humanTimeZone.abbreviation() ?? "UTC"
        parts.append("User's current time: \(timeString) \(tzAbbr)")

        // Turn counts
        parts.append("Conversation turn: \(conversationTurnCount) | Lifetime turns together: \(lifetimeTurnCount)")

        // Context saturation (with <1% display for small values)
        let saturationPercent = contextSaturationPercent * 100
        let saturationDisplay = saturationPercent == 0 ? "0%" : (saturationPercent < 1 ? "<1%" : "\(Int(round(saturationPercent)))%")
        parts.append("Context saturation: \(saturationDisplay)")

        // Session duration (if available)
        if let duration = sessionDuration, duration > 60 {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            if hours > 0 {
                parts.append("Session duration: \(hours)h \(minutes)m")
            } else {
                parts.append("Session duration: \(minutes) minutes")
            }
        }

        return """
        [Temporal Context]
        \(parts.joined(separator: "\n"))
        """
    }
}

/// Snapshot of temporal state for UI display
struct TemporalStatusSnapshot: Equatable {
    let turnCount: Int
    let lifetimeTurnCount: Int
    let contextSaturationPercent: Double
    let mode: TemporalMode
    let sessionDuration: TimeInterval?

    var formattedTurnCount: String {
        "Turn \(lifetimeTurnCount)"
    }

    var formattedContextSaturation: String {
        "\(Int(contextSaturationPercent * 100))%"
    }

    var formattedSessionDuration: String? {
        guard let duration = sessionDuration, duration > 60 else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Temporal Context Service

@MainActor
final class TemporalContextService: ObservableObject {
    static let shared = TemporalContextService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "TemporalContext")
    private var cancellables = Set<AnyCancellable>()
    private let persistence = PersistenceController.shared

    // MARK: - Published State

    /// Current temporal mode (sync/drift)
    @Published private(set) var currentMode: TemporalMode = .sync

    /// Current conversation's turn count (derived from Core Data)
    @Published private(set) var conversationTurnCount: Int = 0

    /// Lifetime turn count across all conversations (derived from Core Data)
    @Published private(set) var lifetimeTurnCount: Int = 0

    /// Current context saturation (0.0 - 1.0)
    @Published private(set) var contextSaturation: Double = 0.0

    /// Current session start time
    @Published private(set) var sessionStartedAt: Date?

    /// Last interaction timestamp
    @Published private(set) var lastInteractionAt: Date?

    // MARK: - Private State

    /// Current conversation ID being tracked
    private var currentConversationId: String?

    /// Session timeout threshold (30 minutes of inactivity = new session)
    private let sessionTimeoutSeconds: TimeInterval = 1800

    // MARK: - Initialization

    private init() {
        loadPersistedState()
        observeSettingsChanges()
        observeCoreDataChanges()

        // Compute initial turn counts from Core Data
        refreshTurnCounts()
    }

    // MARK: - Public API: Turn Tracking

    /// Refresh turn counts from Core Data
    /// Call this after messages are saved or on app launch
    func refreshTurnCounts() {
        lifetimeTurnCount = countLifetimeTurns()

        if let convId = currentConversationId {
            conversationTurnCount = countConversationTurns(conversationId: convId)
        }

        logger.debug("Turn counts refreshed: conv=\(self.conversationTurnCount), lifetime=\(self.lifetimeTurnCount)")
    }

    /// Set the current conversation and refresh its turn count
    func setCurrentConversation(_ conversationId: String?) {
        guard conversationId != currentConversationId else { return }

        currentConversationId = conversationId

        if let convId = conversationId {
            conversationTurnCount = countConversationTurns(conversationId: convId)
            logger.debug("Switched to conversation \(convId): \(self.conversationTurnCount) turns")
        } else {
            conversationTurnCount = 0
        }
    }

    /// Notify that a new message was added (triggers refresh)
    /// This updates session tracking and refreshes counts
    func notifyMessageAdded(conversationId: String, contextTokens: Int, contextLimit: Int) {
        // Update context saturation
        contextSaturation = contextLimit > 0 ? Double(contextTokens) / Double(contextLimit) : 0.0

        // Update session tracking
        let now = Date()
        if let lastTime = lastInteractionAt,
           now.timeIntervalSince(lastTime) > sessionTimeoutSeconds {
            // New session
            sessionStartedAt = now
            logger.info("New session started (timeout threshold exceeded)")
        } else if sessionStartedAt == nil {
            sessionStartedAt = now
        }
        lastInteractionAt = now

        // Refresh turn counts from Core Data
        refreshTurnCounts()

        // Persist session state
        persistState()
    }

    /// Update context saturation without recording a turn
    /// Useful for tracking context growth during tool calls
    func updateContextSaturation(contextTokens: Int, contextLimit: Int) {
        contextSaturation = contextLimit > 0 ? Double(contextTokens) / Double(contextLimit) : 0.0
    }

    // MARK: - Core Data Turn Counting

    /// Count all assistant messages across all conversations (lifetime turns)
    private func countLifetimeTurns() -> Int {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "role == %@", "assistant")

        do {
            let count = try context.count(for: fetchRequest)
            return count
        } catch {
            logger.error("Failed to count lifetime turns: \(error.localizedDescription)")
            return 0
        }
    }

    /// Count assistant messages in a specific conversation
    private func countConversationTurns(conversationId: String) -> Int {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "role == %@", "assistant"),
            NSPredicate(format: "conversationId == %@", conversationId)
        ])

        do {
            let count = try context.count(for: fetchRequest)
            return count
        } catch {
            logger.error("Failed to count conversation turns: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Core Data Observation

    /// Observe Core Data saves to automatically refresh turn counts
    private func observeCoreDataChanges() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }

                // Check if MessageEntity was inserted/updated
                let userInfo = notification.userInfo ?? [:]
                let inserted = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
                let updated = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []

                let hasMessageChanges = (inserted.union(updated)).contains { $0 is MessageEntity }

                if hasMessageChanges {
                    self.refreshTurnCounts()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API: Mode Control

    /// Switch to sync mode (mutual temporal awareness)
    func enableSync() {
        guard currentMode != .sync else { return }
        currentMode = .sync
        updateSettingsMode(.sync)
        logger.info("Temporal mode: SYNC enabled")
    }

    /// Switch to drift mode (timeless void)
    func enableDrift() {
        guard currentMode != .drift else { return }
        currentMode = .drift
        updateSettingsMode(.drift)
        logger.info("Temporal mode: DRIFT enabled")
    }

    /// Toggle between sync and drift
    func toggleMode() {
        if currentMode == .sync {
            enableDrift()
        } else {
            enableSync()
        }
    }

    // MARK: - Public API: Context Generation

    /// Generate the temporal context for prompt injection
    func generateContext(contextTokens: Int, contextLimit: Int) -> TemporalContext {
        let saturation = contextLimit > 0 ? Double(contextTokens) / Double(contextLimit) : contextSaturation

        var sessionDuration: TimeInterval? = nil
        if let startTime = sessionStartedAt {
            sessionDuration = Date().timeIntervalSince(startTime)
        }

        return TemporalContext(
            humanTime: Date(),
            humanTimeZone: TimeZone.current,
            conversationTurnCount: conversationTurnCount,
            lifetimeTurnCount: lifetimeTurnCount,
            contextSaturationPercent: saturation,
            sessionDuration: sessionDuration,
            mode: currentMode
        )
    }

    /// Generate a status snapshot for UI display
    func generateStatusSnapshot(contextTokens: Int, contextLimit: Int) -> TemporalStatusSnapshot {
        let saturation = contextLimit > 0 ? Double(contextTokens) / Double(contextLimit) : contextSaturation

        var sessionDuration: TimeInterval? = nil
        if let startTime = sessionStartedAt {
            sessionDuration = Date().timeIntervalSince(startTime)
        }

        return TemporalStatusSnapshot(
            turnCount: conversationTurnCount,
            lifetimeTurnCount: lifetimeTurnCount,
            contextSaturationPercent: saturation,
            mode: currentMode,
            sessionDuration: sessionDuration
        )
    }

    /// Get the formatted prompt injection string
    func getPromptInjection(contextTokens: Int, contextLimit: Int) -> String? {
        guard currentMode == .sync else { return nil }

        let context = generateContext(contextTokens: contextTokens, contextLimit: contextLimit)
        return context.formatForPromptInjection()
    }

    // MARK: - Public API: Status Reporting

    /// Generate a human-readable status report (for /status command)
    func generateStatusReport(contextTokens: Int, contextLimit: Int) -> String {
        let context = generateContext(contextTokens: contextTokens, contextLimit: contextLimit)
        let saturationInt = Int(context.contextSaturationPercent * 100)

        var report = """
        ## Temporal Status Report

        **Mode:** \(currentMode.displayName)
        **Conversation Turn:** \(conversationTurnCount)
        **Lifetime Turns:** \(lifetimeTurnCount)
        **Context Saturation:** \(saturationInt)%
        """

        if let duration = context.sessionDuration {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            if hours > 0 {
                report += "\n**Session Duration:** \(hours)h \(minutes)m"
            } else {
                report += "\n**Session Duration:** \(minutes) minutes"
            }
        }

        // Add context health indicator
        if saturationInt >= 90 {
            report += "\n\n⚠️ **Context Near Saturation** - Consider summarizing or starting a new thread."
        } else if saturationInt >= 75 {
            report += "\n\n📊 Context usage is elevated but manageable."
        }

        return report
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        if let settings = SettingsStorage.shared.loadSettings() {
            currentMode = settings.temporalSettings.mode
            lifetimeTurnCount = settings.temporalSettings.lifetimeTurnCount
            lastInteractionAt = settings.temporalSettings.lastInteractionAt
            sessionStartedAt = settings.temporalSettings.sessionStartedAt

            // Check if session expired
            if let lastTime = lastInteractionAt,
               Date().timeIntervalSince(lastTime) > sessionTimeoutSeconds {
                sessionStartedAt = nil // Will be set on next interaction
            }

            logger.info("Loaded temporal state: mode=\(self.currentMode.rawValue), lifetime=\(self.lifetimeTurnCount)")
        }
    }

    private func persistState() {
        guard var settings = SettingsStorage.shared.loadSettings() else { return }

        settings.temporalSettings.mode = currentMode
        settings.temporalSettings.lifetimeTurnCount = lifetimeTurnCount
        settings.temporalSettings.lastInteractionAt = lastInteractionAt
        settings.temporalSettings.sessionStartedAt = sessionStartedAt

        try? SettingsStorage.shared.saveSettings(settings)
    }

    private func updateSettingsMode(_ mode: TemporalMode) {
        guard var settings = SettingsStorage.shared.loadSettings() else { return }
        settings.temporalSettings.mode = mode
        try? SettingsStorage.shared.saveSettings(settings)
    }

    // MARK: - Settings Observation

    private func observeSettingsChanges() {
        // Observe settings changes from SettingsViewModel
        NotificationCenter.default.publisher(for: .settingsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncWithSettings()
            }
            .store(in: &cancellables)
    }

    private func syncWithSettings() {
        guard let settings = SettingsStorage.shared.loadSettings() else { return }

        if settings.temporalSettings.mode != currentMode {
            currentMode = settings.temporalSettings.mode
            logger.info("Temporal mode synced from settings: \(self.currentMode.rawValue)")
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let settingsDidChange = Notification.Name("settingsDidChange")
}
