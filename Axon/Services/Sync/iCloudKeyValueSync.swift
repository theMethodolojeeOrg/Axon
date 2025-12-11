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
            if var currentSettings = SettingsStorage.shared.loadSettings() {
                syncableSettings.apply(to: &currentSettings)

                // Notify listeners about the change
                settingsChangedFromCloud.send(currentSettings)
                print("[iCloudKVSync] Settings loaded from iCloud and merged")
            }

            if let timestamp = kvStore.object(forKey: lastSyncKey) as? TimeInterval {
                lastSyncTime = Date(timeIntervalSince1970: timestamp)
            }
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
/// Excludes device-specific settings like API keys, security settings
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
    var predicateLoggingVerbosity: String

    // TTS Settings (voice preferences sync nicely)
    var ttsModel: String
    var ttsOutputFormat: String
    var selectedVoiceId: String?
    var selectedVoiceName: String?

    // Tool Settings
    var toolsEnabled: Bool
    var enabledToolIds: [String]
    var maxToolCallsPerTurn: Int
    var toolTimeout: Int

    // Device Mode Config (sync preferences, not device-specific state)
    var deviceModeConfig: DeviceModeConfig

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
        self.predicateLoggingVerbosity = settings.predicateLoggingVerbosity.rawValue

        self.ttsModel = settings.ttsSettings.model.rawValue
        self.ttsOutputFormat = settings.ttsSettings.outputFormat.rawValue
        self.selectedVoiceId = settings.ttsSettings.selectedVoiceId
        self.selectedVoiceName = settings.ttsSettings.selectedVoiceName

        self.toolsEnabled = settings.toolSettings.toolsEnabled
        self.enabledToolIds = Array(settings.toolSettings.enabledToolIds)
        self.maxToolCallsPerTurn = settings.toolSettings.maxToolCallsPerTurn
        self.toolTimeout = settings.toolSettings.toolTimeout

        self.deviceModeConfig = settings.deviceModeConfig
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
        if let verbosity = PredicateVerbosity(rawValue: predicateLoggingVerbosity) {
            settings.predicateLoggingVerbosity = verbosity
        }

        if let model = TTSModel(rawValue: ttsModel) {
            settings.ttsSettings.model = model
        }
        if let format = TTSOutputFormat(rawValue: ttsOutputFormat) {
            settings.ttsSettings.outputFormat = format
        }
        settings.ttsSettings.selectedVoiceId = selectedVoiceId
        settings.ttsSettings.selectedVoiceName = selectedVoiceName

        settings.toolSettings.toolsEnabled = toolsEnabled
        settings.toolSettings.enabledToolIds = Set(enabledToolIds)
        settings.toolSettings.maxToolCallsPerTurn = maxToolCallsPerTurn
        settings.toolSettings.toolTimeout = toolTimeout

        settings.deviceModeConfig = deviceModeConfig
    }
}
