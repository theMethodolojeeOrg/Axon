//
//  iCloudKeyValueSync.swift
//  Axon
//
//  iCloud Key-Value Storage sync for settings across devices
//  Uses NSUbiquitousKeyValueStore for lightweight, automatic sync
//

import Foundation
import Combine

@MainActor
class iCloudKeyValueSync: ObservableObject {
    static let shared = iCloudKeyValueSync()

    private let kvStore = NSUbiquitousKeyValueStore.default
    private var cancellables = Set<AnyCancellable>()

    // Keys for synced data
    private let settingsKey = "synced.settings"
    private let lastSyncKey = "synced.lastSync"

    // Sync state
    @Published var isAvailable = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?

    // Notification for settings changes from other devices
    let settingsChangedFromCloud = PassthroughSubject<AppSettings, Never>()

    private init() {
        checkAvailability()
        setupChangeNotifications()
    }

    // MARK: - Availability

    private func checkAvailability() {
        // Key-value storage is available if the user is signed into iCloud
        // We can check by attempting to synchronize
        isAvailable = kvStore.synchronize()
        print("[iCloudKVSync] Key-value storage available: \(isAvailable)")
    }

    // MARK: - Change Notifications

    private func setupChangeNotifications() {
        // Listen for changes from other devices
        NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleExternalChange(notification)
            }
            .store(in: &cancellables)

        // Start observing
        kvStore.synchronize()
    }

    private func handleExternalChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange:
            print("[iCloudKVSync] Server change detected for keys: \(changedKeys)")
            if changedKeys.contains(settingsKey) {
                loadSettingsFromCloud()
            }

        case NSUbiquitousKeyValueStoreInitialSyncChange:
            print("[iCloudKVSync] Initial sync completed")
            if changedKeys.contains(settingsKey) {
                loadSettingsFromCloud()
            }

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            print("[iCloudKVSync] Quota exceeded - too much data stored")
            syncError = "iCloud storage quota exceeded for settings"

        case NSUbiquitousKeyValueStoreAccountChange:
            print("[iCloudKVSync] iCloud account changed")
            checkAvailability()

        default:
            break
        }
    }

    // MARK: - Save Settings to Cloud

    func saveSettingsToCloud(_ settings: AppSettings) {
        guard isAvailable else {
            print("[iCloudKVSync] Not available - skipping cloud save")
            return
        }

        // Only sync settings that should be shared across devices
        let syncableSettings = SyncableSettings(from: settings)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(syncableSettings)

            kvStore.set(data, forKey: settingsKey)
            kvStore.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
            kvStore.synchronize()

            lastSyncTime = Date()
            syncError = nil
            print("[iCloudKVSync] Settings saved to iCloud")
        } catch {
            syncError = "Failed to save settings: \(error.localizedDescription)"
            print("[iCloudKVSync] Error saving settings: \(error)")
        }
    }

    // MARK: - Load Settings from Cloud

    private func loadSettingsFromCloud() {
        guard let data = kvStore.data(forKey: settingsKey) else {
            print("[iCloudKVSync] No settings found in iCloud")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let syncableSettings = try decoder.decode(SyncableSettings.self, from: data)

            // Merge cloud settings with local settings
            // If local settings are corrupt/unreadable, start from defaults
            var currentSettings = SettingsStorage.shared.loadSettings() ?? AppSettings()
            syncableSettings.apply(to: &currentSettings)

            // Save the merged settings back to local storage
            do {
                try SettingsStorage.shared.saveSettings(currentSettings)
                print("[iCloudKVSync] Settings loaded from iCloud and merged with local")
            } catch {
                print("[iCloudKVSync] Warning: Failed to save merged settings locally: \(error)")
            }

            // Notify listeners about the change
            settingsChangedFromCloud.send(currentSettings)

            if let timestamp = kvStore.object(forKey: lastSyncKey) as? TimeInterval {
                lastSyncTime = Date(timeIntervalSince1970: timestamp)
            }

            syncError = nil
        } catch {
            syncError = "Failed to load settings: \(error.localizedDescription)"
            print("[iCloudKVSync] Error loading settings: \(error)")
        }
    }

    // MARK: - Manual Sync

    func forceSync() {
        kvStore.synchronize()
        checkAvailability()

        if isAvailable {
            loadSettingsFromCloud()
        }
    }
}

// MARK: - Syncable Settings

/// Settings that should be synced across devices
/// Excludes device-specific settings like API keys, security settings, biometric prefs
struct SyncableSettings: Codable {
    // Theme
    var theme: String

    // AI Preferences
    var defaultProvider: String
    var defaultModel: String

    // General Preferences
    var showArtifactsByDefault: Bool
    var enableKeyboardShortcuts: Bool

    // Memory Settings
    var memoryEnabled: Bool
    var memoryAutoInject: Bool
    var memoryConfidenceThreshold: Double
    var maxMemoriesPerRequest: Int

    // Epistemic Settings
    var epistemicEnabled: Bool
    var epistemicVerbose: Bool
    var learningLoopEnabled: Bool
    var predicateLoggingEnabled: Bool
    var predicateLoggingVerbosity: String

    // Internal Thread Settings
    var internalThreadEnabled: Bool
    var internalThreadRetentionDays: Int

    // Notifications
    var notificationsEnabled: Bool

    // Analytics
    var memoryAnalyticsEnabled: Bool

    // TTS Settings (complete voice preferences)
    var ttsProvider: String
    var ttsQualityTier: String
    var ttsStripMarkdown: Bool
    var ttsSpokenFriendly: Bool
    var ttsVoiceGenderFilter: String?
    // Apple TTS
    var appleVoice: String
    var appleRate: Float
    // ElevenLabs
    var ttsModel: String
    var ttsOutputFormat: String
    var selectedVoiceId: String?
    var selectedVoiceName: String?
    var voiceStability: Double
    var voiceSimilarityBoost: Double
    var voiceStyle: Double
    var voiceUseSpeakerBoost: Bool
    // Gemini TTS
    var geminiVoice: String
    var geminiModel: String
    var geminiVoiceDirection: String
    // OpenAI TTS
    var openaiVoice: String
    var openaiModel: String
    var openaiVoiceInstructions: String
    var openaiSpeed: Double
    // Kokoro TTS
    var kokoroVoice: String
    var kokoroSpeed: Float

    // Tool Settings
    var toolsEnabled: Bool
    var enabledToolIds: [String]
    var maxToolCallsPerTurn: Int
    var toolTimeout: Int
    var experimentalFeaturesEnabled: Bool
    var mediaProxyEnabled: Bool
    var chatDebugEnabled: Bool

    // Device Mode Config (sync preferences, not device-specific state)
    var deviceModeConfig: DeviceModeConfig

    // Model Generation Settings (temperature, top-p, top-k)
    var modelGenerationSettings: ModelGenerationSettings

    // Heartbeat Settings (user preferences, excluding device-specific)
    var heartbeatEnabled: Bool
    var heartbeatIntervalSeconds: Int
    var heartbeatDeliveryProfileId: String
    var heartbeatMaxTokensBudget: Int
    var heartbeatMaxToolCalls: Int
    var heartbeatAllowNotifications: Bool
    var heartbeatLiveActivityEnabled: Bool
    var heartbeatDeliveryProfiles: [HeartbeatDeliveryProfile]

    // Heuristics Settings (cognitive compression layer)
    var heuristicsSettings: HeuristicsSettings

    // Live Voice Settings (realtime voice preferences)
    var liveSettings: LiveSettings

    // Sovereignty Settings (excluding biometric-specific settings)
    var sovereigntyEnabled: Bool
    var sovereigntyConsentProviderHasBeenSetByUser: Bool
    var sovereigntyConsentProvider: String
    var sovereigntyConsentModel: String
    var sovereigntyShowDetailedReasoning: Bool
    var sovereigntyConsentTimeoutSeconds: Int
    var sovereigntyAuditLoggingEnabled: Bool

    // Temporal Settings (preferences only, not counters)
    var temporalMode: String
    var temporalTurnCountScope: String
    var temporalShowStatusBar: Bool
    var temporalInjectHumanTime: Bool
    var temporalInjectTurnCount: Bool
    var temporalInjectContextSaturation: Bool
    var temporalTrackSessionDuration: Bool

    init(from settings: AppSettings) {
        self.theme = settings.theme.rawValue

        self.defaultProvider = settings.defaultProvider.rawValue
        self.defaultModel = settings.defaultModel

        self.showArtifactsByDefault = settings.showArtifactsByDefault
        self.enableKeyboardShortcuts = settings.enableKeyboardShortcuts

        self.memoryEnabled = settings.memoryEnabled
        self.memoryAutoInject = settings.memoryAutoInject
        self.memoryConfidenceThreshold = settings.memoryConfidenceThreshold
        self.maxMemoriesPerRequest = settings.maxMemoriesPerRequest

        self.epistemicEnabled = settings.epistemicEnabled
        self.epistemicVerbose = settings.epistemicVerbose
        self.learningLoopEnabled = settings.learningLoopEnabled
        self.predicateLoggingEnabled = settings.predicateLoggingEnabled
        self.predicateLoggingVerbosity = settings.predicateLoggingVerbosity.rawValue

        // Internal Thread Settings
        self.internalThreadEnabled = settings.internalThreadEnabled
        self.internalThreadRetentionDays = settings.internalThreadRetentionDays

        // Notifications
        self.notificationsEnabled = settings.notificationsEnabled

        // Analytics
        self.memoryAnalyticsEnabled = settings.memoryAnalyticsEnabled

        // TTS Settings (complete)
        self.ttsProvider = settings.ttsSettings.provider.rawValue
        self.ttsQualityTier = settings.ttsSettings.qualityTier.rawValue
        self.ttsStripMarkdown = settings.ttsSettings.stripMarkdownBeforeTTS
        self.ttsSpokenFriendly = settings.ttsSettings.spokenFriendlyTTS
        self.ttsVoiceGenderFilter = settings.ttsSettings.voiceGenderFilter?.rawValue
        self.appleVoice = settings.ttsSettings.appleVoice.rawValue
        self.appleRate = settings.ttsSettings.appleRate
        self.ttsModel = settings.ttsSettings.model.rawValue
        self.ttsOutputFormat = settings.ttsSettings.outputFormat.rawValue
        self.selectedVoiceId = settings.ttsSettings.selectedVoiceId
        self.selectedVoiceName = settings.ttsSettings.selectedVoiceName
        self.voiceStability = settings.ttsSettings.voiceSettings.stability
        self.voiceSimilarityBoost = settings.ttsSettings.voiceSettings.similarityBoost
        self.voiceStyle = settings.ttsSettings.voiceSettings.style
        self.voiceUseSpeakerBoost = settings.ttsSettings.voiceSettings.useSpeakerBoost
        self.geminiVoice = settings.ttsSettings.geminiVoice.rawValue
        self.geminiModel = settings.ttsSettings.geminiModel.rawValue
        self.geminiVoiceDirection = settings.ttsSettings.geminiVoiceDirection
        self.openaiVoice = settings.ttsSettings.openaiVoice.rawValue
        self.openaiModel = settings.ttsSettings.openaiModel.rawValue
        self.openaiVoiceInstructions = settings.ttsSettings.openaiVoiceInstructions
        self.openaiSpeed = settings.ttsSettings.openaiSpeed
        self.kokoroVoice = settings.ttsSettings.kokoroVoice.rawValue
        self.kokoroSpeed = settings.ttsSettings.kokoroSpeed

        self.toolsEnabled = settings.toolSettings.toolsEnabled
        self.enabledToolIds = Array(settings.toolSettings.enabledToolIds)
        self.maxToolCallsPerTurn = settings.toolSettings.maxToolCallsPerTurn
        self.toolTimeout = settings.toolSettings.toolTimeout
        self.experimentalFeaturesEnabled = settings.toolSettings.experimentalFeaturesEnabled
        self.mediaProxyEnabled = settings.toolSettings.mediaProxyEnabled
        self.chatDebugEnabled = settings.toolSettings.chatDebugEnabled

        self.deviceModeConfig = settings.deviceModeConfig

        // Model Generation Settings
        self.modelGenerationSettings = settings.modelGenerationSettings

        // Heartbeat Settings (user preferences)
        self.heartbeatEnabled = settings.heartbeatSettings.enabled
        self.heartbeatIntervalSeconds = settings.heartbeatSettings.intervalSeconds
        self.heartbeatDeliveryProfileId = settings.heartbeatSettings.deliveryProfileId
        self.heartbeatMaxTokensBudget = settings.heartbeatSettings.maxTokensBudget
        self.heartbeatMaxToolCalls = settings.heartbeatSettings.maxToolCalls
        self.heartbeatAllowNotifications = settings.heartbeatSettings.allowNotifications
        self.heartbeatLiveActivityEnabled = settings.heartbeatSettings.liveActivityEnabled
        self.heartbeatDeliveryProfiles = settings.heartbeatSettings.deliveryProfiles

        // Heuristics Settings
        self.heuristicsSettings = settings.heuristicsSettings

        // Live Voice Settings
        self.liveSettings = settings.liveSettings

        // Sovereignty Settings (excluding biometric)
        self.sovereigntyEnabled = settings.sovereigntySettings.enabled
        self.sovereigntyConsentProviderHasBeenSetByUser = settings.sovereigntySettings.consentProviderHasBeenSetByUser
        self.sovereigntyConsentProvider = settings.sovereigntySettings.consentProvider.rawValue
        self.sovereigntyConsentModel = settings.sovereigntySettings.consentModel
        self.sovereigntyShowDetailedReasoning = settings.sovereigntySettings.showDetailedReasoning
        self.sovereigntyConsentTimeoutSeconds = settings.sovereigntySettings.consentTimeoutSeconds
        self.sovereigntyAuditLoggingEnabled = settings.sovereigntySettings.auditLoggingEnabled

        // Temporal Settings (preferences only)
        self.temporalMode = settings.temporalSettings.mode.rawValue
        self.temporalTurnCountScope = settings.temporalSettings.turnCountScope.rawValue
        self.temporalShowStatusBar = settings.temporalSettings.showStatusBar
        self.temporalInjectHumanTime = settings.temporalSettings.injectHumanTime
        self.temporalInjectTurnCount = settings.temporalSettings.injectTurnCount
        self.temporalInjectContextSaturation = settings.temporalSettings.injectContextSaturation
        self.temporalTrackSessionDuration = settings.temporalSettings.trackSessionDuration
    }

    func apply(to settings: inout AppSettings) {
        if let theme = Theme(rawValue: theme) {
            settings.theme = theme
        }

        if let provider = AIProvider(rawValue: defaultProvider) {
            settings.defaultProvider = provider
        }
        settings.defaultModel = defaultModel

        settings.showArtifactsByDefault = showArtifactsByDefault
        settings.enableKeyboardShortcuts = enableKeyboardShortcuts

        settings.memoryEnabled = memoryEnabled
        settings.memoryAutoInject = memoryAutoInject
        settings.memoryConfidenceThreshold = memoryConfidenceThreshold
        settings.maxMemoriesPerRequest = maxMemoriesPerRequest

        settings.epistemicEnabled = epistemicEnabled
        settings.epistemicVerbose = epistemicVerbose
        settings.learningLoopEnabled = learningLoopEnabled
        settings.predicateLoggingEnabled = predicateLoggingEnabled
        if let verbosity = PredicateVerbosity(rawValue: predicateLoggingVerbosity) {
            settings.predicateLoggingVerbosity = verbosity
        }

        // Internal Thread Settings
        settings.internalThreadEnabled = internalThreadEnabled
        settings.internalThreadRetentionDays = internalThreadRetentionDays

        // Notifications
        settings.notificationsEnabled = notificationsEnabled

        // Analytics
        settings.memoryAnalyticsEnabled = memoryAnalyticsEnabled

        // TTS Settings (complete)
        if let provider = TTSProvider(rawValue: ttsProvider) {
            settings.ttsSettings.provider = provider
        }
        if let tier = TTSQualityTier(rawValue: ttsQualityTier) {
            settings.ttsSettings.qualityTier = tier
        }
        settings.ttsSettings.stripMarkdownBeforeTTS = ttsStripMarkdown
        settings.ttsSettings.spokenFriendlyTTS = ttsSpokenFriendly
        settings.ttsSettings.voiceGenderFilter = ttsVoiceGenderFilter.flatMap { VoiceGender(rawValue: $0) }
        if let voice = AppleTTSVoice(rawValue: appleVoice) {
            settings.ttsSettings.appleVoice = voice
        }
        settings.ttsSettings.appleRate = appleRate
        if let model = TTSModel(rawValue: ttsModel) {
            settings.ttsSettings.model = model
        }
        if let format = TTSOutputFormat(rawValue: ttsOutputFormat) {
            settings.ttsSettings.outputFormat = format
        }
        settings.ttsSettings.selectedVoiceId = selectedVoiceId
        settings.ttsSettings.selectedVoiceName = selectedVoiceName
        settings.ttsSettings.voiceSettings.stability = voiceStability
        settings.ttsSettings.voiceSettings.similarityBoost = voiceSimilarityBoost
        settings.ttsSettings.voiceSettings.style = voiceStyle
        settings.ttsSettings.voiceSettings.useSpeakerBoost = voiceUseSpeakerBoost
        if let voice = GeminiTTSVoice(rawValue: geminiVoice) {
            settings.ttsSettings.geminiVoice = voice
        }
        if let model = GeminiTTSModel(rawValue: geminiModel) {
            settings.ttsSettings.geminiModel = model
        }
        settings.ttsSettings.geminiVoiceDirection = geminiVoiceDirection
        if let voice = OpenAITTSVoice(rawValue: openaiVoice) {
            settings.ttsSettings.openaiVoice = voice
        }
        if let model = OpenAITTSModel(rawValue: openaiModel) {
            settings.ttsSettings.openaiModel = model
        }
        settings.ttsSettings.openaiVoiceInstructions = openaiVoiceInstructions
        settings.ttsSettings.openaiSpeed = openaiSpeed
        if let voice = KokoroTTSVoice(rawValue: kokoroVoice) {
            settings.ttsSettings.kokoroVoice = voice
        }
        settings.ttsSettings.kokoroSpeed = kokoroSpeed

        settings.toolSettings.toolsEnabled = toolsEnabled
        settings.toolSettings.enabledToolIds = Set(enabledToolIds)
        settings.toolSettings.maxToolCallsPerTurn = maxToolCallsPerTurn
        settings.toolSettings.toolTimeout = toolTimeout
        settings.toolSettings.experimentalFeaturesEnabled = experimentalFeaturesEnabled
        settings.toolSettings.mediaProxyEnabled = mediaProxyEnabled
        settings.toolSettings.chatDebugEnabled = chatDebugEnabled

        settings.deviceModeConfig = deviceModeConfig

        // Model Generation Settings
        settings.modelGenerationSettings = modelGenerationSettings

        // Heartbeat Settings (user preferences, preserve device-specific)
        settings.heartbeatSettings.enabled = heartbeatEnabled
        settings.heartbeatSettings.intervalSeconds = heartbeatIntervalSeconds
        settings.heartbeatSettings.deliveryProfileId = heartbeatDeliveryProfileId
        settings.heartbeatSettings.maxTokensBudget = heartbeatMaxTokensBudget
        settings.heartbeatSettings.maxToolCalls = heartbeatMaxToolCalls
        settings.heartbeatSettings.allowNotifications = heartbeatAllowNotifications
        settings.heartbeatSettings.liveActivityEnabled = heartbeatLiveActivityEnabled
        settings.heartbeatSettings.deliveryProfiles = heartbeatDeliveryProfiles
        // Note: allowBackground and quietHours are device-specific, not synced

        // Heuristics Settings
        settings.heuristicsSettings = heuristicsSettings

        // Live Voice Settings
        settings.liveSettings = liveSettings

        // Sovereignty Settings (preserve biometric settings)
        settings.sovereigntySettings.enabled = sovereigntyEnabled
        settings.sovereigntySettings.consentProviderHasBeenSetByUser = sovereigntyConsentProviderHasBeenSetByUser
        if let provider = AIProvider(rawValue: sovereigntyConsentProvider) {
            settings.sovereigntySettings.consentProvider = provider
        }
        settings.sovereigntySettings.consentModel = sovereigntyConsentModel
        settings.sovereigntySettings.showDetailedReasoning = sovereigntyShowDetailedReasoning
        settings.sovereigntySettings.consentTimeoutSeconds = sovereigntyConsentTimeoutSeconds
        settings.sovereigntySettings.auditLoggingEnabled = sovereigntyAuditLoggingEnabled
        // Note: requireBiometricForAllActions is device-specific, not synced

        // Temporal Settings (preferences only, preserve counters/timestamps)
        if let mode = TemporalMode(rawValue: temporalMode) {
            settings.temporalSettings.mode = mode
        }
        if let scope = TurnCountScope(rawValue: temporalTurnCountScope) {
            settings.temporalSettings.turnCountScope = scope
        }
        settings.temporalSettings.showStatusBar = temporalShowStatusBar
        settings.temporalSettings.injectHumanTime = temporalInjectHumanTime
        settings.temporalSettings.injectTurnCount = temporalInjectTurnCount
        settings.temporalSettings.injectContextSaturation = temporalInjectContextSaturation
        settings.temporalSettings.trackSessionDuration = temporalTrackSessionDuration
        // Note: lifetimeTurnCount, lastSessionTurnCount, lastInteractionAt, sessionStartedAt are device-specific
    }
}
