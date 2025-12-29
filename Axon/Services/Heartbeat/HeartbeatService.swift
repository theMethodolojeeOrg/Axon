//
//  HeartbeatService.swift
//  Axon
//
//  Foreground heartbeat loop that generates internal thread updates.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class HeartbeatService: ObservableObject {
    static let shared = HeartbeatService()

    @Published private(set) var lastHeartbeatAt: Date?
    @Published private(set) var lastHeartbeatSummary: String?
    @Published private(set) var isRunning: Bool = false

    private let settingsViewModel = SettingsViewModel.shared
    private lazy var orchestrator = OnDeviceConversationOrchestrator()
    private let agentStateService = AgentStateService.shared
    private let notificationService = NotificationService.shared
    private let sovereigntyService = SovereigntyService.shared
    private let liveActivityService = LiveActivityService.shared

    private var heartbeatTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isForeground = true

    private init() {
        let heartbeatSettingsPublisher = settingsViewModel.$settings.map { $0.heartbeatSettings }
        let internalThreadEnabledPublisher = settingsViewModel.$settings.map { $0.internalThreadEnabled }

        heartbeatSettingsPublisher
            .combineLatest(internalThreadEnabledPublisher)
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .sink { [weak self] _ in
                self?.restartIfNeeded()
            }
            .store(in: &cancellables)
    }

    func start() {
        restartIfNeeded()
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        isForeground = (phase == .active)
        restartIfNeeded()
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        isRunning = false
        Task {
            await liveActivityService.endHeartbeatActivity()
        }
    }

    private func restartIfNeeded() {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        let settings = settingsViewModel.settings
        let heartbeat = settings.heartbeatSettings
        guard settings.internalThreadEnabled, heartbeat.enabled else {
            isRunning = false
            Task {
                await liveActivityService.endHeartbeatActivity()
            }
            return
        }

        if !isForeground && !heartbeat.allowBackground {
            isRunning = false
            Task {
                await liveActivityService.endHeartbeatActivity()
            }
            return
        }

        let interval = max(60, heartbeat.intervalSeconds)
        let profileName = heartbeat.profile(for: heartbeat.deliveryProfileId)?.name ?? "Default"

        // Start Live Activity
        Task {
            try? await liveActivityService.startHeartbeatActivity(
                profileName: profileName,
                intervalSeconds: interval
            )
        }

        isRunning = true
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                let result = await self.runOnce(reason: "scheduled")

                // Update Live Activity with result (including mood icon from AI)
                let nextRunTime = Date().addingTimeInterval(Double(interval))
                await self.liveActivityService.updateHeartbeatActivity(
                    with: result,
                    nextRunTime: nextRunTime,
                    moodIcon: result.moodIcon,
                    moodReason: result.moodReason
                )
            }
        }
    }

    @discardableResult
    func runOnce(reason: String) async -> HeartbeatRunResult {
        let settings = settingsViewModel.settings
        let heartbeat = settings.heartbeatSettings

        guard settings.internalThreadEnabled else {
            return .skipped("Internal thread is disabled.")
        }

        if let quietHours = heartbeat.quietHours, !quietHours.isCurrentTimeAllowed() {
            return .skipped("Quiet hours active.")
        }

        // Route based on execution mode
        switch heartbeat.executionMode {
        case .soloThread:
            return await runSoloThreadMode(reason: reason, settings: settings)
        case .internalThread:
            // Continue with internal thread (silent) mode below
            break
        }

        // Signal Live Activity that we're running
        await liveActivityService.markHeartbeatRunning()

        do {
            let modules = await buildContextModules(settings: settings)
            let prompt = buildHeartbeatPrompt(modules: modules)
            let config = try await buildOrchestrationConfig(settings: settings)

            let (assistantMessage, _) = try await orchestrator.sendMessage(
                conversationId: "heartbeat",
                content: prompt,
                attachments: [],
                enabledTools: [],
                messages: [],
                config: config
            )

            let responseText = assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = decodePayload(from: responseText)

            let entryContent = payload?.entry?.content ?? responseText
            let kind = payload?.entry?.resolvedKind ?? .heartbeatSnapshot
            let visibility = payload?.entry?.resolvedVisibility ?? .userVisible
            let tags = payload?.entry?.tags ?? []

            let entry = try await agentStateService.appendEntry(
                kind: kind,
                content: entryContent,
                tags: tags,
                visibility: visibility,
                origin: .system
            )

            var notified = false
            if let notification = payload?.notifyUser,
               heartbeat.allowNotifications,
               settings.notificationsEnabled,
               isNotificationPreApproved() {
                do {
                    _ = try await notificationService.sendLocalNotification(
                        title: notification.title,
                        body: notification.body,
                        userInfo: ["source": "heartbeat"]
                    )
                    notified = true
                } catch {
                    notified = false
                }
            }

            // Extract mood icon for Live Activity
            let moodIcon = payload?.liveActivityMood?.resolvedIcon
            let moodReason = payload?.liveActivityMood?.reason

            lastHeartbeatAt = Date()
            lastHeartbeatSummary = entryContent

            return .success(entry: entry, notified: notified, moodIcon: moodIcon, moodReason: moodReason)
        } catch is CancellationError {
            return .skipped("Heartbeat cancelled.")
        } catch {
            // Check for "cancelled" in localized description as well (common in network tasks)
            let errorDesc = error.localizedDescription.lowercased()
            if errorDesc.contains("cancelled") || errorDesc.contains("task was cancelled") {
                return .skipped("Heartbeat cancelled.")
            }
            return .failed(error.localizedDescription)
        }
    }
    
    // MARK: - Solo Thread Mode
    
    /// Run heartbeat in solo thread mode - creates a visible conversation with tool access
    private func runSoloThreadMode(reason: String, settings: AppSettings) async -> HeartbeatRunResult {
        let soloService = SoloThreadService.shared
        
        // Check if a solo session is already active
        if soloService.activeSoloThreadId != nil {
            return .skipped("Solo session already active.")
        }
        
        // Build initial prompt from context modules
        let modules = await buildContextModules(settings: settings)
        let prompt = buildSoloPrompt(modules: modules, reason: reason)
        
        do {
            // Start solo session
            let conversation = try await soloService.startSoloSession(
                initialPrompt: prompt,
                turnsAllocated: settings.heartbeatSettings.soloTurnsPerSession,
                agendaItemId: nil, // TODO: Pick from agenda
                heartbeatId: UUID().uuidString
            )
            
            lastHeartbeatAt = Date()
            lastHeartbeatSummary = "Solo session started: \(conversation.id)"
            
            // Return success for solo mode (no InternalThreadEntry, uses conversation instead)
            return .soloStarted(conversationId: conversation.id)
        } catch {
            return .failed("Solo session failed: \(error.localizedDescription)")
        }
    }
    
    /// Build the initial prompt for a solo session
    private func buildSoloPrompt(modules: [HeartbeatModuleOutput], reason: String) -> String {
        let moduleLines = modules.map { "- \($0.title): \($0.content)" }.joined(separator: "\n")
        
        return """
        SOLO SESSION STARTED
        
        Context:
        \(moduleLines)
        
        Trigger: \(reason)
        
        Instructions:
        You are now in a solo work session. This is a visible conversation where you can:
        - Use tools to accomplish useful work
        - Access memories, internal thread, and other resources
        - Work autonomously on tasks that benefit the user
        
        You have been allocated turns to work. At the turn boundary, you'll be presented
        with a SOLO SESSION CHECKPOINT where you'll use the solo_turn_action tool to
        decide whether to extend, conclude, pause, or notify.
        
        Start by identifying what would be most valuable to work on right now.
        """
    }

    private func isNotificationPreApproved() -> Bool {
        let action = SovereignAction.category(.userNotify)
        let scope = ActionScope.toolId(ToolId.notifyUser.rawValue)
        let permission = sovereigntyService.checkActionPermission(action, scope: scope)
        switch permission {
        case .preApproved:
            return true
        default:
            return false
        }
    }

    private func buildHeartbeatPrompt(modules: [HeartbeatModuleOutput]) -> String {
        let moduleLines = modules.map { "- \($0.title): \($0.content)" }.joined(separator: "\n")
        let moodIconOptions = HeartbeatMoodIcon.allCases.map { $0.rawValue }.joined(separator: "|")
        return """
        HEARTBEAT

        Context Modules:
        \(moduleLines)

        Instructions:
        - Return ONLY a JSON object.
        - JSON schema:
          {
            "entry": {
              "kind": "note|plan|self_reflection|heartbeat_snapshot|counter|system",
              "content": "string",
              "tags": ["tag1", "tag2"],
              "visibility": "userVisible|aiOnly"
            },
            "notify_user": {
              "title": "string",
              "body": "string"
            },
            "live_activity_mood": {
              "icon": "\(moodIconOptions)",
              "reason": "short reason (max 50 chars)"
            }
          }
        - Omit "notify_user" if no notification is needed.
        - "live_activity_mood" sets the icon shown on the lock screen Live Activity. Pick an icon that reflects your current state/intent. The "reason" briefly explains why you chose it (shown to user).
        """
    }

    private func buildContextModules(settings: AppSettings) async -> [HeartbeatModuleOutput] {
        let profileId = settings.heartbeatSettings.deliveryProfileId
        let profile = settings.heartbeatSettings.profile(for: profileId)
            ?? HeartbeatDeliveryProfile.defaultProfiles.first

        let modules = profile?.moduleIds ?? []
        var outputs: [HeartbeatModuleOutput] = []

        for module in modules {
            if let output = await outputForModule(module, settings: settings) {
                outputs.append(output)
            }
        }

        return outputs
    }

    private func outputForModule(_ module: HeartbeatModuleId, settings: AppSettings) async -> HeartbeatModuleOutput? {
        switch module {
        case .systemStatus:
            let providerName = settings.selectedCustomProviderId != nil
                ? "Custom Provider"
                : settings.defaultProvider.displayName
            let content = "Time: \(Date().formatted(date: .abbreviated, time: .shortened)); Provider: \(providerName); Device Mode: \(settings.deviceMode.displayName)"
            return HeartbeatModuleOutput(title: module.displayName, content: content)

        case .recentMessages:
            let conversationService = ConversationService.shared
            let title = conversationService.currentConversation?.title ?? "No active conversation"
            let recentMessages = conversationService.messages.suffix(6)
            if recentMessages.isEmpty {
                return HeartbeatModuleOutput(title: module.displayName, content: "No recent messages. Active conversation: \(title)")
            }
            let lines = recentMessages.map { message in
                let role = message.role.rawValue.capitalized
                let snippet = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let clipped = snippet.count > 140 ? String(snippet.prefix(140)) + "..." : snippet
                return "\(role): \(clipped)"
            }
            return HeartbeatModuleOutput(title: module.displayName, content: "Active conversation: \(title)\n" + lines.joined(separator: "\n"))

        case .lastInternalThreadEntry:
            if let entry = agentStateService.latestEntry() {
                let snippet = entry.content.count > 160 ? String(entry.content.prefix(160)) + "..." : entry.content
                return HeartbeatModuleOutput(
                    title: module.displayName,
                    content: "\(entry.kind.displayName) at \(entry.timestamp.formatted(date: .abbreviated, time: .shortened)): \(snippet)"
                )
            }
            return HeartbeatModuleOutput(title: module.displayName, content: "No internal thread entries yet.")

        case .pendingApprovals:
            if let pending = ToolApprovalService.shared.pendingApproval {
                let content = "Pending approval: \(pending.tool.name)"
                return HeartbeatModuleOutput(title: module.displayName, content: content)
            }
            return HeartbeatModuleOutput(title: module.displayName, content: "No pending approvals.")

        case .lastHeartbeat:
            if let lastHeartbeatAt = lastHeartbeatAt, let lastSummary = lastHeartbeatSummary {
                let snippet = lastSummary.count > 160 ? String(lastSummary.prefix(160)) + "..." : lastSummary
                return HeartbeatModuleOutput(
                    title: module.displayName,
                    content: "Last heartbeat at \(lastHeartbeatAt.formatted(date: .abbreviated, time: .shortened)): \(snippet)"
                )
            }
            return HeartbeatModuleOutput(title: module.displayName, content: "No previous heartbeat recorded.")
        }
    }

    private func buildOrchestrationConfig(settings: AppSettings) async throws -> OrchestrationConfig {
        let apiKeys = APIKeysStorage.shared

        var providerString = settings.defaultProvider.rawValue
        var modelId = settings.defaultModel
        var providerDisplayName = settings.defaultProvider.displayName
        var customBaseUrl: String? = nil
        var customApiKey: String? = nil

        if let customProviderId = settings.selectedCustomProviderId,
           let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }),
           let customModelId = settings.selectedCustomModelId,
           let customModel = customProvider.models.first(where: { $0.id == customModelId }) {
            providerString = "openai-compatible"
            modelId = customModel.modelCode
            providerDisplayName = customProvider.providerName
            customBaseUrl = customProvider.apiEndpoint
            if let key = try? apiKeys.getCustomProviderAPIKey(providerId: customProviderId) {
                customApiKey = key
            }
        }

        if providerString == "xai" {
            providerString = "grok"
        }

        let contextWindowLimit = AIProvider.contextWindowForModel(modelId, settings: settings)

        return OrchestrationConfig(
            provider: providerString,
            model: modelId,
            providerName: providerDisplayName,
            contextWindowLimit: contextWindowLimit,
            anthropicKey: try? apiKeys.getAPIKey(for: .anthropic),
            openaiKey: try? apiKeys.getAPIKey(for: .openai),
            geminiKey: try? apiKeys.getAPIKey(for: .gemini),
            grokKey: try? apiKeys.getAPIKey(for: .xai),
            perplexityKey: try? apiKeys.getAPIKey(for: .perplexity),
            deepseekKey: try? apiKeys.getAPIKey(for: .deepseek),
            zaiKey: try? apiKeys.getAPIKey(for: .zai),
            minimaxKey: try? apiKeys.getAPIKey(for: .minimax),
            mistralKey: try? apiKeys.getAPIKey(for: .mistral),
            customBaseUrl: customBaseUrl,
            customApiKey: customApiKey,
            modelParams: settings.modelGenerationSettings
        )
    }

    private func decodePayload(from text: String) -> HeartbeatPayload? {
        if let data = text.data(using: .utf8),
           let payload = try? JSONDecoder().decode(HeartbeatPayload.self, from: data) {
            return payload
        }

        if let jsonString = extractJSON(from: text),
           let data = jsonString.data(using: .utf8),
           let payload = try? JSONDecoder().decode(HeartbeatPayload.self, from: data) {
            return payload
        }

        return nil
    }

    private func extractJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        let jsonRange = start...end
        return String(text[jsonRange])
    }
}

struct HeartbeatModuleOutput {
    let title: String
    let content: String
}

struct HeartbeatRunResult {
    let status: HeartbeatRunStatus
    let entry: InternalThreadEntry?
    let notified: Bool
    let message: String
    let moodIcon: HeartbeatMoodIcon?
    let moodReason: String?

    static func success(entry: InternalThreadEntry, notified: Bool, moodIcon: HeartbeatMoodIcon? = nil, moodReason: String? = nil) -> HeartbeatRunResult {
        HeartbeatRunResult(status: .success, entry: entry, notified: notified, message: "Heartbeat completed.", moodIcon: moodIcon, moodReason: moodReason)
    }
    
    static func soloStarted(conversationId: String) -> HeartbeatRunResult {
        HeartbeatRunResult(status: .success, entry: nil, notified: false, message: "Solo session started: \(conversationId)", moodIcon: nil, moodReason: nil)
    }

    static func skipped(_ message: String) -> HeartbeatRunResult {
        HeartbeatRunResult(status: .skipped, entry: nil, notified: false, message: message, moodIcon: nil, moodReason: nil)
    }

    static func failed(_ message: String) -> HeartbeatRunResult {
        HeartbeatRunResult(status: .failed, entry: nil, notified: false, message: message, moodIcon: nil, moodReason: nil)
    }
}

enum HeartbeatRunStatus: String {
    case success
    case skipped
    case failed
}

struct HeartbeatPayload: Decodable {
    struct Entry: Decodable {
        let kind: String?
        let content: String?
        let tags: [String]
        let visibility: String?

        var resolvedKind: InternalThreadEntryKind {
            InternalThreadEntryKind(rawValue: kind ?? "") ?? .heartbeatSnapshot
        }

        var resolvedVisibility: InternalThreadVisibility {
            InternalThreadVisibility(rawValue: visibility ?? "") ?? .userVisible
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decodeIfPresent(String.self, forKey: .kind)
            content = try container.decodeIfPresent(String.self, forKey: .content)
            visibility = try container.decodeIfPresent(String.self, forKey: .visibility)

            if let tagArray = try? container.decode([String].self, forKey: .tags) {
                tags = tagArray
            } else if let tagString = try? container.decode(String.self, forKey: .tags) {
                tags = tagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                tags = []
            }
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case content
            case tags
            case visibility
        }
    }

    struct NotifyUser: Decodable {
        let title: String
        let body: String
    }

    struct LiveActivityMood: Decodable {
        let icon: String?
        let reason: String?

        var resolvedIcon: HeartbeatMoodIcon? {
            guard let icon = icon else { return nil }
            return HeartbeatMoodIcon(rawValue: icon)
        }
    }

    let entry: Entry?
    let notifyUser: NotifyUser?
    let liveActivityMood: LiveActivityMood?

    private enum CodingKeys: String, CodingKey {
        case entry
        case notifyUser = "notify_user"
        case liveActivityMood = "live_activity_mood"
    }
}
