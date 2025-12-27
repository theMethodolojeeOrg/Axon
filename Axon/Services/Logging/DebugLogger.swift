//
//  DebugLogger.swift
//  Axon
//
//  Centralized debug logging with category filtering.
//  Uses toggles from Developer Settings to control output.
//

import Foundation
import Combine

// MARK: - Log Category

/// Categories for debug logging
enum LogCategory: String, CaseIterable, Identifiable, Codable {
    // Security & Auth
    case secureVault = "SecureVault"
    case biometricAuth = "BiometricAuth"
    case deviceIdentity = "DeviceIdentity"
    
    // Data & Persistence
    case persistence = "Persistence"
    case coreDataCloudKit = "CoreDataCloudKitStack"
    case localConversationStore = "LocalConversationStore"
    case conversationService = "ConversationService"
    
    // Sync
    case iCloudKVSync = "iCloudKVSync"
    case cloudKitSync = "CloudKitSync"
    case autoSyncOrchestrator = "AutoSyncOrchestrator"
    
    // Settings & Config
    case settingsViewModel = "SettingsViewModel"
    case appDelegate = "AppDelegate"
    
    // Services
    case memoryService = "MemoryService"
    case widgetData = "WidgetDataService"
    case devicePresence = "DevicePresenceService"
    case draftMessage = "DraftMessageService"
    
    // Media
    case ttsPlayback = "TTSPlaybackService"
    case mlxModel = "MLXModelService"
    case liveSession = "LiveSession"
    
    // Tools
    case toolPluginLoader = "ToolPluginLoader"
    case toolExecution = "ToolExecution"

    // Chat
    case attachments = "Attachments"
    case providerResolution = "ProviderResolution"

    // Developer
    case developerSettings = "DeveloperSettings"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .secureVault: return "Secure Vault"
        case .biometricAuth: return "Biometric Auth"
        case .deviceIdentity: return "Device Identity"
        case .persistence: return "Persistence"
        case .coreDataCloudKit: return "Core Data CloudKit"
        case .localConversationStore: return "Local Conversation Store"
        case .conversationService: return "Conversation Service"
        case .iCloudKVSync: return "iCloud KV Sync"
        case .cloudKitSync: return "CloudKit Sync"
        case .autoSyncOrchestrator: return "Auto Sync Orchestrator"
        case .settingsViewModel: return "Settings ViewModel"
        case .appDelegate: return "App Delegate"
        case .memoryService: return "Memory Service"
        case .widgetData: return "Widget Data"
        case .devicePresence: return "Device Presence"
        case .draftMessage: return "Draft Message"
        case .ttsPlayback: return "TTS Playback"
        case .mlxModel: return "MLX Models"
        case .liveSession: return "Live Session"
        case .toolPluginLoader: return "Tool Plugin Loader"
        case .toolExecution: return "Tool Execution"
        case .attachments: return "Attachments"
        case .providerResolution: return "Provider Resolution"
        case .developerSettings: return "Developer Settings"
        }
    }

    var icon: String {
        switch self {
        case .secureVault: return "lock.shield"
        case .biometricAuth: return "faceid"
        case .deviceIdentity: return "person.crop.circle.badge.checkmark"
        case .persistence: return "externaldrive"
        case .coreDataCloudKit: return "link.icloud.fill"
        case .localConversationStore: return "bubble.left.and.bubble.right"
        case .conversationService: return "text.bubble"
        case .iCloudKVSync: return "key.icloud"
        case .cloudKitSync: return "icloud"
        case .autoSyncOrchestrator: return "arrow.triangle.2.circlepath.icloud"
        case .settingsViewModel: return "gearshape"
        case .appDelegate: return "app"
        case .memoryService: return "brain"
        case .widgetData: return "widget.small"
        case .devicePresence: return "iphone.radiowaves.left.and.right"
        case .draftMessage: return "doc.text"
        case .ttsPlayback: return "speaker.wave.2"
        case .mlxModel: return "cpu"
        case .liveSession: return "waveform.circle"
        case .toolPluginLoader: return "shippingbox"
        case .toolExecution: return "wrench.and.screwdriver"
        case .attachments: return "paperclip"
        case .providerResolution: return "arrow.triangle.branch"
        case .developerSettings: return "hammer"
        }
    }

    /// Group for UI organization
    var group: LogCategoryGroup {
        switch self {
        case .secureVault, .biometricAuth, .deviceIdentity:
            return .security
        case .persistence, .coreDataCloudKit, .localConversationStore, .conversationService:
            return .data
        case .iCloudKVSync, .cloudKitSync, .autoSyncOrchestrator:
            return .sync
        case .settingsViewModel, .appDelegate:
            return .config
        case .memoryService, .widgetData, .devicePresence, .draftMessage:
            return .services
        case .ttsPlayback, .mlxModel, .liveSession:
            return .media
        case .toolPluginLoader, .toolExecution:
            return .tools
        case .attachments, .providerResolution:
            return .chat
        case .developerSettings:
            return .developer
        }
    }
}

// MARK: - Log Category Group

enum LogCategoryGroup: String, CaseIterable, Identifiable {
    case security = "Security & Auth"
    case data = "Data & Persistence"
    case sync = "Cloud Sync"
    case config = "Settings & Config"
    case services = "Services"
    case media = "Media"
    case tools = "Tools"
    case chat = "Chat"
    case developer = "Developer"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .security: return "lock.shield.fill"
        case .data: return "externaldrive.fill"
        case .sync: return "icloud.fill"
        case .config: return "gearshape.fill"
        case .services: return "square.grid.2x2.fill"
        case .media: return "waveform"
        case .tools: return "wrench.and.screwdriver.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .developer: return "hammer.fill"
        }
    }

    var categories: [LogCategory] {
        LogCategory.allCases.filter { $0.group == self }
    }
}

// MARK: - Debug Logger

/// A single log entry for the console view
struct DebugLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let message: String

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// Centralized debug logger with category-based filtering
@MainActor
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    /// Master toggle for all logging
    @Published var loggingEnabled: Bool = false {
        didSet { saveSettings() }
    }

    /// Individual category toggles
    @Published var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases) {
        didSet { saveSettings() }
    }

    /// In-memory log buffer for console view
    @Published var logEntries: [DebugLogEntry] = []

    /// Maximum log entries to keep in memory
    let maxLogEntries: Int = 500

    /// Developer console visibility toggle
    @Published var consoleEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(consoleEnabled, forKey: "developer.consoleEnabled")
        }
    }

    private let userDefaultsKey = "developer.logSettings"

    private init() {
        loadSettings()
        consoleEnabled = UserDefaults.standard.bool(forKey: "developer.consoleEnabled")
    }

    // MARK: - Logging

    /// Log a message if the category is enabled
    func log(_ category: LogCategory, _ message: String) {
        guard loggingEnabled && enabledCategories.contains(category) else { return }

        // Print to console
        print("[\(category.rawValue)] \(message)")

        // Store in buffer for in-app console
        let entry = DebugLogEntry(timestamp: Date(), category: category, message: message)
        logEntries.append(entry)

        // Trim if over capacity
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }

    /// Log with formatted values
    func log(_ category: LogCategory, _ message: String, _ values: [String: Any]) {
        guard loggingEnabled && enabledCategories.contains(category) else { return }
        let formatted = values.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let fullMessage = "\(message): \(formatted)"

        // Print to console
        print("[\(category.rawValue)] \(fullMessage)")

        // Store in buffer
        let entry = DebugLogEntry(timestamp: Date(), category: category, message: fullMessage)
        logEntries.append(entry)

        // Trim if over capacity
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }

    /// Clear all log entries
    func clearLogs() {
        logEntries.removeAll()
    }

    /// Export logs as text
    func exportLogsAsText() -> String {
        logEntries.map { entry in
            "[\(entry.formattedTimestamp)] [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }

    // MARK: - Category Management

    func isEnabled(_ category: LogCategory) -> Bool {
        loggingEnabled && enabledCategories.contains(category)
    }

    func setEnabled(_ category: LogCategory, enabled: Bool) {
        if enabled {
            enabledCategories.insert(category)
        } else {
            enabledCategories.remove(category)
        }
    }

    func toggleCategory(_ category: LogCategory) {
        if enabledCategories.contains(category) {
            enabledCategories.remove(category)
        } else {
            enabledCategories.insert(category)
        }
    }

    // MARK: - Group Management

    func enabledCount(for group: LogCategoryGroup) -> Int {
        group.categories.filter { enabledCategories.contains($0) }.count
    }

    func groupState(for group: LogCategoryGroup) -> LogCategoryToggleState {
        let categories = group.categories
        let enabledCount = categories.filter { enabledCategories.contains($0) }.count
        if enabledCount == categories.count {
            return .allEnabled
        } else if enabledCount > 0 {
            return .partiallyEnabled
        } else {
            return .allDisabled
        }
    }

    func setGroupEnabled(_ group: LogCategoryGroup, enabled: Bool) {
        for category in group.categories {
            setEnabled(category, enabled: enabled)
        }
    }

    func toggleGroup(_ group: LogCategoryGroup) {
        let shouldEnable = groupState(for: group) != .allEnabled
        setGroupEnabled(group, enabled: shouldEnable)
    }

    // MARK: - Bulk Operations

    func enableAll() {
        enabledCategories = Set(LogCategory.allCases)
    }

    func disableAll() {
        enabledCategories = []
    }

    // MARK: - Stats

    var enabledCount: Int {
        enabledCategories.count
    }

    var totalCount: Int {
        LogCategory.allCases.count
    }

    // MARK: - Persistence

    private func saveSettings() {
        let enabledIds = enabledCategories.map { $0.rawValue }
        let settings: [String: Any] = [
            "loggingEnabled": loggingEnabled,
            "enabledCategories": enabledIds
        ]
        UserDefaults.standard.set(settings, forKey: userDefaultsKey)
    }

    private func loadSettings() {
        guard let settings = UserDefaults.standard.dictionary(forKey: userDefaultsKey) else {
            return
        }
        if let enabled = settings["loggingEnabled"] as? Bool {
            loggingEnabled = enabled
        }
        if let enabledIds = settings["enabledCategories"] as? [String] {
            enabledCategories = Set(enabledIds.compactMap { LogCategory(rawValue: $0) })
        }
    }
}

// MARK: - Toggle State

enum LogCategoryToggleState {
    case allEnabled
    case partiallyEnabled
    case allDisabled
}

// MARK: - Global Convenience Function

/// Global convenience for logging from anywhere
/// Usage: debugLog(.persistence, "Saved \(count) items")
func debugLog(_ category: LogCategory, _ message: String) {
    Task { @MainActor in
        DebugLogger.shared.log(category, message)
    }
}

/// Global convenience with values dictionary
func debugLog(_ category: LogCategory, _ message: String, _ values: [String: Any]) {
    Task { @MainActor in
        DebugLogger.shared.log(category, message, values)
    }
}
