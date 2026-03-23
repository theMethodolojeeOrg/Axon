//
//  AppSettings.swift
//  Axon
//
//  Main settings container
//

import Foundation

// MARK: - Main Settings Container

struct AppSettings: Codable, Equatable, Sendable {
    // General
    var theme: Theme = .auto
    var defaultProvider: AIProvider = .appleFoundation
    var defaultModel: String = "apple-foundation-default"

    // Custom Provider Selection (when using custom providers)
    var selectedCustomProviderId: UUID? = nil
    var selectedCustomModelId: UUID? = nil

    var showArtifactsByDefault: Bool = true
    var enableKeyboardShortcuts: Bool = true

    /// Legacy flag - use `deviceModeConfig.aiProcessing` instead
    /// Kept for backward compatibility during migration
    @available(*, deprecated, message: "Use deviceModeConfig.aiProcessing instead")
    var useOnDeviceOrchestration: Bool = false

    // Account
    var firstName: String = ""
    var lastName: String = ""

    // Memory
    var memoryEnabled: Bool = true
    var memoryAutoInject: Bool = true
    var memoryConfidenceThreshold: Double = 0.3  // 0-1.0
    var maxMemoriesPerRequest: Int = 10  // 5-50
    var memoryAnalyticsEnabled: Bool = true
    var subconsciousMemoryLogging: SubconsciousMemoryLoggingSettings? = nil

    // Internal Thread (Agent State)
    var internalThreadEnabled: Bool = true
    var internalThreadRetentionDays: Int = 0  // 0 = keep indefinitely

    // Heartbeat
    var heartbeatSettings: HeartbeatSettings = HeartbeatSettings()

    // Heuristics (cognitive compression layer)
    var heuristicsSettings: HeuristicsSettings = HeuristicsSettings()

    // Notifications
    var notificationsEnabled: Bool = true

    // Epistemic Engine (Consciousness & Grounding)
    var epistemicEnabled: Bool = true               // Enable epistemic grounding
    var epistemicVerbose: Bool = false              // Include detailed epistemic boundaries in prompts
    var learningLoopEnabled: Bool = true            // Enable feedback-driven learning
    var predicateLoggingEnabled: Bool = true        // Enable formal predicate logging
    var predicateLoggingVerbosity: PredicateVerbosity = .normal  // Logging detail level

    // Security & Authentication
    var appLockEnabled: Bool = false                // Require auth to open app
    var biometricEnabled: Bool = true               // Use Face ID/Touch ID
    var passcodeEnabled: Bool = true                // Allow passcode fallback
    var lockTimeout: LockTimeout = .immediate       // When to require re-auth
    var hideContentInAppSwitcher: Bool = true       // Blur content in app switcher

    // Device Mode (On-Device vs Cloud)
    /// Legacy toggle - deviceModeConfig is now the single source of truth
    /// Kept for backward compatibility during migration
    @available(*, deprecated, message: "Use deviceModeConfig directly - this toggle is no longer used")
    var deviceMode: DeviceMode = .onDevice

    /// Unified data management configuration - this is the single source of truth
    /// for all data storage, sync, and AI processing settings
    var deviceModeConfig: DeviceModeConfig = DeviceModeConfig()

    // Conversations
    var archiveRetentionDays: Int = 30

    // API Keys (stored separately in Keychain for security)
    // We'll reference them but not store them here

    // Text-to-Speech
    var ttsSettings: TTSSettings = TTSSettings()

    // Audio Sync (cross-device TTS audio caching)
    var audioSyncSettings: AudioSyncSettings = AudioSyncSettings()

    // AI Tools (web search, code execution, etc.)
    var toolSettings: ToolSettings = ToolSettings()

    // VS Code Bridge
    var bridgeSettings: BridgeSettings = BridgeSettings()

    // Realtime Voice
    var liveSettings: LiveSettings = LiveSettings()

    // Custom Providers
    var customProviders: [CustomProviderConfig] = []

    // User-added MLX Models (from Hugging Face browser)
    var userMLXModels: [UserMLXModel] = []
    var selectedMLXModelId: String? = nil  // repoId of selected model (nil = use default bundled)

    // Local API Server
    var serverEnabled: Bool = false
    var serverPort: Int = 8080
    var serverPassword: String? = nil
    var serverAllowExternal: Bool = false

    // Onboarding
    var hasCompletedOnboarding: Bool = false
    var hasSeenFirstRunWelcome: Bool = false  // Welcome card after first AI response

    // Co-Sovereignty
    var sovereigntySettings: SovereigntySettings = SovereigntySettings()

    // AI Sharing with Friends
    var sharingSettings: SharingSettings = SharingSettings()

    // Multi-Device Presence
    var presenceSettings: PresenceSettings = PresenceSettings()

    // Model Generation Parameters (temperature, top-p, top-k, etc.)
    var modelGenerationSettings: ModelGenerationSettings = ModelGenerationSettings()

    // Per-Model Generation Overrides (keyed by model ID)
    var modelOverrides: [String: ModelOverride] = [:]

    // Temporal Symmetry (mutual time/turn awareness)
    var temporalSettings: TemporalSettings = TemporalSettings()

    // Backend Configuration (optional - for cloud features)
    var backendAPIURL: String? = nil  // e.g., "https://us-central1-your-project.cloudfunctions.net"
    var backendAuthToken: String? = nil  // Optional auth token for backend (stored in Keychain separately)

    // Metadata
    var version: Int = 1
    var lastUpdated: Date = Date()
    var lastSyncedAt: Date?
}

// MARK: - Subconscious Memory Logging Settings

/// Settings for autonomous background memory logging.
///
/// Important: this is stored as an optional field in AppSettings so older persisted
/// settings blobs can decode without reset. Use `resolved` to read effective defaults.
struct SubconsciousMemoryLoggingSettings: Codable, Equatable, Sendable {
    // Master toggle
    var enabled: Bool = false

    // Provider/model selection
    var builtInProvider: String? = nil
    var customProviderId: UUID? = nil
    var builtInModel: String? = nil
    var customModelId: UUID? = nil

    // Context behavior
    var rollingContextPercent: Double = 0.25

    // Salience / epistemic controls
    var maxMemories: Int = 10
    var confidenceThreshold: Double = 0.30
    var minSalienceThreshold: Double = 0.20
    var relevanceWeight: Double = 0.40
    var confidenceWeight: Double = 0.30
    var recencyWeight: Double = 0.20
    var includeEpistemicBoundaries: Bool = false
    var showConfidence: Bool = true

    // Execution guardrails
    var maxToolRounds: Int = 3

    static let `default` = SubconsciousMemoryLoggingSettings()
}

extension AppSettings {
    var resolvedSubconsciousMemoryLogging: SubconsciousMemoryLoggingSettings {
        subconsciousMemoryLogging ?? .default
    }
}
