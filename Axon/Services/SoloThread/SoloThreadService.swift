//
//  SoloThreadService.swift
//  Axon
//
//  Service for managing solo thread sessions - autonomous AI work in visible conversations.
//  Implements turn-based execution with allocation menus, pause/resume, and user takeover.
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "SoloThread")

// MARK: - Solo Thread Service

@MainActor
final class SoloThreadService: ObservableObject {
    static let shared = SoloThreadService()
    
    // MARK: - Published State
    
    /// ID of the currently active solo thread (nil if none)
    @Published private(set) var activeSoloThreadId: String?
    
    /// Current turn number in the active session
    @Published private(set) var currentTurn: Int = 0
    
    /// Current status of the solo session
    @Published private(set) var status: SoloSessionStatus = .idle
    
    /// Latest transcript from the solo session
    @Published private(set) var latestTranscript: String = ""
    
    // MARK: - Dependencies
    
    private let conversationService = ConversationService.shared
    private let settingsViewModel = SettingsViewModel.shared
    private var soloTask: Task<Void, Never>?
    
    // MARK: - Session Tracking
    
    /// Sessions completed today (for daily limit)
    private var sessionsCompletedToday: Int = 0
    
    /// Last reset date for daily count
    private var lastResetDate: Date?
    
    /// Total turns used today (for review triggers)
    private var totalTurnsToday: Int = 0
    
    /// Extensions requested this session
    private var extensionsThisSession: Int = 0
    
    /// In-memory solo thread configs (keyed by conversation ID)
    /// These are synced with the Conversation model when possible
    private var soloConfigs: [String: SoloThreadConfig] = [:]
    
    // MARK: - Initialization
    
    private init() {
        resetDailyCountsIfNeeded()
    }
    
    // MARK: - Public API
    
    /// Start a new solo thread session
    /// - Parameters:
    ///   - initialPrompt: The prompt to start the session with
    ///   - turnsAllocated: Number of turns to allocate
    ///   - agendaItemId: Optional agenda item being worked on
    ///   - heartbeatId: Optional originating heartbeat ID
    /// - Returns: The created conversation
    func startSoloSession(
        initialPrompt: String,
        turnsAllocated: Int? = nil,
        agendaItemId: String? = nil,
        heartbeatId: String? = nil
    ) async throws -> Conversation {
        // Check if already running
        guard activeSoloThreadId == nil else {
            throw SoloThreadError.sessionAlreadyActive
        }
        
        // Reset daily counts if needed
        resetDailyCountsIfNeeded()
        
        // Get settings
        let settings = settingsViewModel.settings
        let heartbeatSettings = settings.heartbeatSettings
        
        // Check daily session limit
        guard sessionsCompletedToday < heartbeatSettings.soloMaxSessionsPerDay else {
            throw SoloThreadError.dailyLimitReached
        }
        
        // Determine turns to allocate
        let turns = turnsAllocated ?? heartbeatSettings.soloTurnsPerSession
        
        logger.info("Starting solo session: turns=\(turns), agenda=\(agendaItemId ?? "none")")
        
        // Create the solo thread configuration
        let config = SoloThreadConfig.newSession(
            heartbeatId: heartbeatId,
            turnsAllocated: turns,
            sessionIndex: sessionsCompletedToday + 1,
            agendaItemId: agendaItemId
        )
        
        // Create a new conversation
        let conversation = try await conversationService.createConversation(
            title: "Solo Session \(sessionsCompletedToday + 1)"
        )
        
        // Store the solo config in memory (associated with conversation ID)
        soloConfigs[conversation.id] = config
        
        // Update state
        activeSoloThreadId = conversation.id
        currentTurn = 0
        extensionsThisSession = 0
        status = .active
        
        // Send notification if configured
        await sendNotificationIfEnabled(.sessionStarted, threadId: conversation.id)
        
        // Start the turn loop
        startTurnLoop(conversationId: conversation.id, initialPrompt: initialPrompt)
        
        return conversation
    }
    
    /// Pause the active solo session
    func pauseSession() {
        guard let threadId = activeSoloThreadId else { return }
        
        logger.info("Pausing solo session: \(threadId)")
        
        // Cancel the task
        soloTask?.cancel()
        soloTask = nil
        
        // Update config
        if var config = soloConfigs[threadId] {
            config.status = .paused
            soloConfigs[threadId] = config
        }
        
        status = .paused
    }
    
    /// Resume a paused solo session
    func resumeSession(threadId: String, prompt: String? = nil) async throws {
        guard activeSoloThreadId == nil || activeSoloThreadId == threadId else {
            throw SoloThreadError.sessionAlreadyActive
        }
        
        // Get the config
        guard let config = soloConfigs[threadId], config.status == .paused else {
            throw SoloThreadError.invalidSession
        }
        
        logger.info("Resuming solo session: \(threadId)")
        
        activeSoloThreadId = threadId
        currentTurn = config.turnsUsed
        status = .active
        
        // Update config status
        var updatedConfig = config
        updatedConfig.status = .active
        soloConfigs[threadId] = updatedConfig
        
        // Resume the turn loop
        let resumePrompt = prompt ?? "Continue from where you left off."
        startTurnLoop(conversationId: threadId, initialPrompt: resumePrompt)
    }
    
    /// User takes over - convert to normal conversation
    func userTakeOver(threadId: String) {
        guard activeSoloThreadId == threadId else { return }
        
        logger.info("User taking over solo session: \(threadId)")
        
        // Cancel the task
        soloTask?.cancel()
        soloTask = nil
        
        // Update config
        if var config = soloConfigs[threadId] {
            config.status = .userTookOver
            config.completionReason = .userIntervened
            config.completedAt = Date()
            soloConfigs[threadId] = config
        }
        
        sessionsCompletedToday += 1
        
        // Clear active session
        activeSoloThreadId = nil
        currentTurn = 0
        status = .idle
    }
    
    /// Get the solo config for a conversation
    func getSoloConfig(for conversationId: String) -> SoloThreadConfig? {
        return soloConfigs[conversationId]
    }
    
    /// Check if a conversation is a solo thread
    func isSoloThread(_ conversationId: String) -> Bool {
        return soloConfigs[conversationId] != nil
    }
    
    /// Get the current session statistics
    func getSessionStatistics() -> SoloSessionStatistics? {
        guard let threadId = activeSoloThreadId else { return nil }
        
        return SoloSessionStatistics(
            sessionId: threadId,
            turnsCompleted: currentTurn,
            extensionsRequested: extensionsThisSession,
            toolsUsed: [:],
            estimatedTokensUsed: nil,
            estimatedCostUSD: nil,
            duration: 0,
            completionReason: nil
        )
    }
    
    // MARK: - Private Methods
    
    /// Start the turn-based execution loop
    private func startTurnLoop(conversationId: String, initialPrompt: String) {
        soloTask = Task { [weak self] in
            guard let self = self else { return }
            
            var prompt = initialPrompt
            
            while !Task.isCancelled {
                // Get current config
                guard var config = self.soloConfigs[conversationId],
                      config.status == .active else {
                    break
                }
                
                // Check if we've hit the turn boundary
                if config.turnsUsed >= config.turnsAllocated {
                    logger.info("Turn boundary reached: \(config.turnsUsed)/\(config.turnsAllocated)")
                    
                    // Present allocation menu
                    let action = await self.presentAllocationMenu(conversationId: conversationId, config: config)
                    
                    switch action {
                    case .extend:
                        // Grant more turns
                        config.turnsAllocated += self.settingsViewModel.settings.heartbeatSettings.soloTurnsPerSession
                        config.extensionCount += 1
                        self.extensionsThisSession += 1
                        self.soloConfigs[conversationId] = config
                        prompt = "Continue with your next goal."
                        
                    case .conclude:
                        await self.concludeSession(threadId: conversationId, reason: .axonConcluded)
                        return
                        
                    case .pause:
                        config.status = .paused
                        self.soloConfigs[conversationId] = config
                        self.status = .paused
                        return
                        
                    case .notify:
                        await self.sendNotificationIfEnabled(.sessionCompleted, threadId: conversationId)
                        await self.concludeSession(threadId: conversationId, reason: .axonConcluded)
                        return
                    }
                }
                
                // Execute a turn
                do {
                    let response = try await self.executeSoloTurn(conversationId: conversationId, prompt: prompt)
                    
                    // Update counters
                    self.currentTurn += 1
                    self.totalTurnsToday += 1
                    config.turnsUsed += 1
                    self.soloConfigs[conversationId] = config
                    
                    // Update transcript
                    self.latestTranscript = response
                    
                    // Next prompt is continuation
                    prompt = "Continue."
                    
                } catch {
                    logger.error("Turn execution failed: \(error.localizedDescription)")
                    await self.sendNotificationIfEnabled(.errorOccurred, threadId: conversationId, context: ["error": error.localizedDescription])
                    config.status = .error
                    config.completionReason = .errorOccurred
                    self.soloConfigs[conversationId] = config
                    self.status = .error
                    return
                }
                
                // Small delay between turns
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
    }
    
    /// Execute a single turn in solo mode
    private func executeSoloTurn(conversationId: String, prompt: String) async throws -> String {
        let settings = settingsViewModel.settings
        let heartbeatSettings = settings.heartbeatSettings
        
        // Get enabled tools for solo mode
        let enabledTools = heartbeatSettings.soloAllowedToolCategories.flatMap { category in
            ToolCategory.tools(for: category).map { $0.rawValue }
        }
        
        // Send the message through ConversationService
        let response = try await conversationService.sendMessage(
            conversationId: conversationId,
            content: prompt,
            attachments: [],
            enabledTools: enabledTools
        )
        
        return response.content
    }
    
    /// Present the turn allocation menu and get Axon's response
    private func presentAllocationMenu(conversationId: String, config: SoloThreadConfig) async -> SoloTurnAction {
        let settings = settingsViewModel.settings
        let heartbeatSettings = settings.heartbeatSettings
        
        // Build the menu
        let menu = SoloTurnAllocationMenu.standard(
            config: config,
            remainingSessionsToday: heartbeatSettings.soloMaxSessionsPerDay - sessionsCompletedToday,
            maxSessionsPerDay: heartbeatSettings.soloMaxSessionsPerDay,
            dailyBudgetUSD: nil,
            spentTodayUSD: nil,
            estimatedExtensionCostUSD: nil
        )
        
        // Send menu as a system message and get response
        let menuPrompt = menu.formattedPrompt()
        
        do {
            let response = try await executeSoloTurn(conversationId: conversationId, prompt: menuPrompt)
            
            // Parse response for action
            // TODO: Use solo_turn_action tool instead of parsing text
            if response.lowercased().contains("extend") {
                return .extend
            } else if response.lowercased().contains("pause") {
                return .pause
            } else if response.lowercased().contains("notify") {
                return .notify
            } else {
                return .conclude
            }
        } catch {
            logger.error("Failed to present allocation menu: \(error.localizedDescription)")
            return .conclude
        }
    }
    
    /// Conclude the session
    private func concludeSession(threadId: String, reason: SoloCompletionReason) async {
        logger.info("Concluding solo session: \(threadId), reason: \(reason.rawValue)")
        
        if var config = soloConfigs[threadId] {
            config.status = .completed
            config.completionReason = reason
            config.completedAt = Date()
            soloConfigs[threadId] = config
        }
        
        sessionsCompletedToday += 1
        
        // Send completion notification
        await sendNotificationIfEnabled(.sessionCompleted, threadId: threadId)
        
        // Clear active session
        activeSoloThreadId = nil
        currentTurn = 0
        status = .idle
    }
    
    /// Reset daily counts if it's a new day
    private func resetDailyCountsIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if let lastReset = lastResetDate {
            if calendar.startOfDay(for: lastReset) < today {
                sessionsCompletedToday = 0
                totalTurnsToday = 0
                lastResetDate = Date()
            }
        } else {
            lastResetDate = Date()
        }
    }
    
    /// Send notification if trigger is enabled
    private func sendNotificationIfEnabled(_ trigger: SoloNotificationTrigger, threadId: String, context: [String: String] = [:]) async {
        do {
            try await NotificationService.shared.sendSoloTriggerNotification(
                trigger: trigger,
                threadId: threadId,
                context: context
            )
        } catch {
            logger.warning("Failed to send solo notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - Tool Category Helper Extension

extension ToolCategory {
    /// Get the tools in this category
    static func tools(for category: ToolCategory) -> [ToolId] {
        switch category {
        case .geminiTools:
            return [.googleSearch, .codeExecution, .urlContext, .googleMaps]
        case .openaiTools:
            return [.openaiWebSearch, .openaiImageGeneration]
        case .memoryReflection:
            return [.createMemory, .conversationSearch, .reflectOnConversation]
        case .internalThread:
            return [.agentStateAppend, .agentStateQuery, .agentStateClear]
        case .heartbeat:
            return [.heartbeatConfigure, .heartbeatRunOnce]
        case .coSovereignty:
            return [.queryCovenant, .proposeCovenantChange]
        case .systemState:
            return [.querySystemState, .changeSystemState]
        case .toolDiscovery:
            return [.listTools, .getToolDetails]
        case .multiDevice:
            return [.queryDevicePresence, .requestDeviceSwitch, .setPresenceIntent]
        case .subAgentOrchestration:
            return [.spawnScout, .spawnMechanic, .spawnDesigner, .queryJobStatus]
        case .systemControl:
            return [.persistenceDisable, .notifyUser]
        case .debugging:
            return [.debugBridge]
        case .temporalSymmetry:
            return [.temporalSync, .temporalDrift, .temporalStatus]
        case .externalApps:
            return [.discoverPorts, .invokePort]
        }
    }
}

// MARK: - Solo Session Status

enum SoloSessionStatus: String, Sendable {
    case idle
    case active
    case paused
    case error
}

// MARK: - Solo Thread Errors

enum SoloThreadError: Error, LocalizedError {
    case sessionAlreadyActive
    case dailyLimitReached
    case invalidSession
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return "A solo session is already active"
        case .dailyLimitReached:
            return "Daily solo session limit reached"
        case .invalidSession:
            return "Invalid or expired solo session"
        case .executionFailed(let message):
            return "Solo turn execution failed: \(message)"
        }
    }
}
