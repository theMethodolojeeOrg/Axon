//
//  Settings.swift
//  Axon
//
//  Settings data models
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

// MARK: - Theme

enum Theme: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark = "dark"
    case light = "light"
    case auto = "auto"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .auto: return "Auto (System)"
        }
    }
}

// MARK: - Lock Timeout

enum LockTimeout: String, Codable, CaseIterable, Identifiable, Sendable {
    case immediate = "immediate"
    case oneMinute = "1min"
    case fiveMinutes = "5min"
    case fifteenMinutes = "15min"
    case oneHour = "1hour"
    case never = "never"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .immediate: return "Immediately"
        case .oneMinute: return "After 1 minute"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .oneHour: return "After 1 hour"
        case .never: return "Never"
        }
    }

    var seconds: Int {
        switch self {
        case .immediate: return 0
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .oneHour: return 3600
        case .never: return Int.max
        }
    }
}

// MARK: - Device Mode

/// Primary toggle: Cloud vs On-Device
enum DeviceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case cloud = "cloud"
    case onDevice = "onDevice"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cloud: return "Cloud"
        case .onDevice: return "On-Device"
        }
    }

    var icon: String {
        switch self {
        case .cloud: return "cloud.fill"
        case .onDevice: return "iphone.gen3"
        }
    }

    var description: String {
        switch self {
        case .cloud:
            return "Conversations sync to your server. Full cloud features enabled."
        case .onDevice:
            return "Local-first operation. Configure what syncs in settings."
        }
    }
}

/// Unified data management configuration
/// This is the single source of truth for all data storage, sync, and AI processing settings.
/// The legacy DeviceMode toggle and useOnDeviceOrchestration flag are deprecated.
struct DeviceModeConfig: Codable, Equatable, Sendable {
    /// How conversation data is stored
    /// Default: localFirst - works offline, syncs when connected
    var dataStorage: DataStorageMode = .localFirst

    /// Where AI orchestration (prompt routing, tool calls) runs
    /// Default: onDevice - direct API calls to providers (no backend needed)
    var aiProcessing: AIProcessingMode = .onDevice

    /// How memory/learning data is handled
    /// Default: cloudSync - memories sync across devices for seamless experience
    var memoryStorage: MemoryStorageMode = .cloudSync

    /// Cloud sync provider (when sync is enabled)
    /// Default: iCloud for seamless cross-device sync on Apple platforms
    var cloudSyncProvider: CloudSyncProvider = .iCloud

    /// Settings sync interval (seconds). Used for scheduled sync when a provider is selected.
    /// Default: 60s
    var settingsSyncIntervalSeconds: Int = 60

    /// Whether to show sync status indicators in UI
    var showSyncStatus: Bool = true

    /// Auto-sync when network becomes available
    var autoSyncOnConnect: Bool = true
}

/// Which cloud service to use for syncing (if any)
enum CloudSyncProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case iCloud = "iCloud"
    case firestore = "firestore"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .iCloud: return "iCloud"
        case .firestore: return "Custom Server"
        }
    }

    var description: String {
        switch self {
        case .none:
            return "Data stays on this device only."
        case .iCloud:
            return "Sync across your Apple devices via iCloud."
        case .firestore:
            return "Sync to your own server (Firestore/custom API)."
        }
    }

    var icon: String {
        switch self {
        case .none: return "iphone"
        case .iCloud: return "icloud.fill"
        case .firestore: return "server.rack"
        }
    }

    var requiresSetup: Bool {
        switch self {
        case .none, .iCloud: return false
        case .firestore: return true
        }
    }
}

/// How conversation data is stored
enum DataStorageMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case localOnly = "localOnly"
    case localFirst = "localFirst"
    case syncRequired = "syncRequired"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localOnly: return "Local Only"
        case .localFirst: return "Local-First"
        case .syncRequired: return "Sync Required"
        }
    }

    var description: String {
        switch self {
        case .localOnly:
            return "Data never leaves device. No cloud backup."
        case .localFirst:
            return "Works offline, syncs when connected."
        case .syncRequired:
            return "Requires network. Traditional cloud mode."
        }
    }

    var icon: String {
        switch self {
        case .localOnly: return "lock.iphone"
        case .localFirst: return "arrow.triangle.2.circlepath"
        case .syncRequired: return "wifi"
        }
    }
}

/// Where AI orchestration runs
enum AIProcessingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case onDevice = "onDevice"
    case cloud = "cloud"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice: return "On-Device"
        case .cloud: return "Cloud"
        }
    }

    var description: String {
        switch self {
        case .onDevice:
            return "AI calls made directly from device to providers."
        case .cloud:
            return "AI orchestration handled by your server."
        }
    }

    var icon: String {
        switch self {
        case .onDevice: return "cpu"
        case .cloud: return "cloud"
        }
    }
}

/// How memory/learning data is handled
enum MemoryStorageMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case localOnly = "localOnly"
    case cloudSync = "cloudSync"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localOnly: return "Local Memory"
        case .cloudSync: return "Cloud Sync"
        }
    }

    var description: String {
        switch self {
        case .localOnly:
            return "Memories stored only on this device."
        case .cloudSync:
            return "Memories sync across your devices."
        }
    }

    var icon: String {
        switch self {
        case .localOnly: return "brain.head.profile"
        case .cloudSync: return "brain"
        }
    }
}

// MARK: - Predicate Verbosity

enum PredicateVerbosity: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal = "minimal"    // Only errors and critical predicates
    case normal = "normal"      // Standard logging
    case verbose = "verbose"    // Full proof trees

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .normal: return "Normal"
        case .verbose: return "Verbose"
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Only errors and critical events"
        case .normal: return "Standard predicate logging"
        case .verbose: return "Full proof trees and all predicates"
        }
    }
}

// MARK: - Co-Sovereignty Settings

/// Settings for co-sovereignty features (AI consent, negotiations, deadlocks)
struct SovereigntySettings: Codable, Equatable, Sendable {
    /// Whether co-sovereignty is enabled
    var enabled: Bool = true

    /// Whether the user has explicitly chosen a consent provider.
    /// If false, we will default consentProvider to the current main provider (General Settings)
    /// once, and then leave it alone.
    var consentProviderHasBeenSetByUser: Bool = false

    /// The provider to use for AI consent/attestation generation
    /// Apple Intelligence is the default for on-device, private negotiations
    var consentProvider: AIProvider = .appleFoundation

    /// The model to use for consent generation (provider-specific)
    /// Empty string means use the provider's default
    var consentModel: String = ""

    /// Whether to require biometric authentication for all world-affecting actions
    /// When false, uses trust tiers for pre-approved actions
    var requireBiometricForAllActions: Bool = false

    /// Whether to show detailed AI reasoning during negotiations
    var showDetailedReasoning: Bool = true

    /// Maximum time (in seconds) to wait for AI consent before timing out
    /// 0 means no timeout (default for deadlocks)
    var consentTimeoutSeconds: Int = 0

    /// Whether to log all consent decisions for audit
    var auditLoggingEnabled: Bool = true
}

// MARK: - AI Sharing Settings

/// Settings for sharing AI learned patterns with friends (guest access)
struct SharingSettings: Codable, Equatable, Sendable {
    /// Whether sharing is enabled at all
    var enabled: Bool = false

    /// Default expiration time for new invitations (in hours)
    var defaultExpirationHours: Int = 24

    /// Maximum number of concurrent guest sessions allowed
    var maxConcurrentGuests: Int = 3

    /// Tags to always exclude from shared memories
    var excludedTags: [String] = ["private", "personal", "health", "financial", "password", "secret"]

    /// Whether to send push notifications when guests connect
    var notifyOnGuestConnect: Bool = true

    /// Whether to require biometric authentication for creating invitations
    var requireBiometricForInvitations: Bool = true

    /// Whether Axon must also consent to sharing (joint consent model)
    var requireAIConsent: Bool = true

    /// Memory types that can be shared (by default, only egoic/learned patterns)
    var shareableMemoryTypes: [String] = ["egoic"]

    /// Default capabilities preset for new guests
    var defaultCapabilitiesPreset: GuestCapabilitiesPreset = .standard

    /// Whether to log all sharing activity for audit
    var auditLoggingEnabled: Bool = true
}

/// Presets for guest capabilities
enum GuestCapabilitiesPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case readOnly = "read_only"
    case standard = "standard"
    case full = "full"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .readOnly: return "Read Only"
        case .standard: return "Standard"
        case .full: return "Full Access"
        }
    }

    var description: String {
        switch self {
        case .readOnly:
            return "Memory search only, no chat context"
        case .standard:
            return "Chat with context, limited memory search"
        case .full:
            return "Full chat and memory access within egoic scope"
        }
    }

    var icon: String {
        switch self {
        case .readOnly: return "eye"
        case .standard: return "person.badge.shield.checkmark"
        case .full: return "person.fill.checkmark"
        }
    }
}

// MARK: - AI Providers

enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic = "anthropic"
    case openai = "openai"
    case gemini = "gemini"
    case xai = "xai"
    case perplexity = "perplexity"
    case deepseek = "deepseek"
    case zai = "zai"
    case minimax = "minimax"
    case mistral = "mistral"
    case appleFoundation = "appleFoundation"
    case localMLX = "localMLX"

    var id: String { rawValue }

    /// Map AIProvider to APIProvider for key storage and low-level service calls
    var apiProvider: APIProvider? {
        switch self {
        case .anthropic: return .anthropic
        case .openai: return .openai
        case .gemini: return .gemini
        case .xai: return .xai
        case .perplexity: return .perplexity
        case .deepseek: return .deepseek
        case .zai: return .zai
        case .minimax: return .minimax
        case .mistral: return .mistral
        case .appleFoundation, .localMLX:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI (GPT)"
        case .gemini: return "Google Gemini"
        case .xai: return "xAI (Grok)"
        case .perplexity: return "Perplexity (Sonar)"
        case .deepseek: return "DeepSeek"
        case .zai: return "Z.ai (GLM)"
        case .minimax: return "MiniMax"
        case .mistral: return "Mistral AI"
        case .appleFoundation: return "Apple Intelligence"
        case .localMLX: return "On-Device (MLX)"
        }
    }

    var availableModels: [AIModel] {
        switch self {
        case .anthropic:
            return [
                AIModel(
                    id: "claude-opus-4-5-20251022",
                    name: "Claude Opus 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Most capable Claude model for deep reasoning, agents, and long-horizon coding"
                ),
                AIModel(
                    id: "claude-sonnet-4-5-20250929",
                    name: "Claude Sonnet 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Best coding model. Strongest for complex agents and computer use"
                ),
                AIModel(
                    id: "claude-haiku-4-5-20251001",
                    name: "Claude Haiku 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Fast hybrid reasoning model. Great for coding and quick tasks"
                ),
                AIModel(
                    id: "claude-opus-4-1-20250805",
                    name: "Claude Opus 4.1",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Most powerful for long-running tasks and deep reasoning"
                ),
                AIModel(
                    id: "claude-sonnet-4-20250514",
                    name: "Claude Sonnet 4",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Previous generation Sonnet model"
                ),
                AIModel(
                    id: "claude-opus-4-20250514",
                    name: "Claude Opus 4",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Previous generation Opus model"
                )
            ]
        case .openai:
            return [
                AIModel(
                    id: "gpt-5.2",
                    name: "GPT-5.2",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Latest frontier model with stronger reasoning and long-context performance"
                ),
                AIModel(
                    id: "gpt-5.1",
                    name: "GPT-5.1",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Upgraded GPT-5 with improved conversational abilities and customization"
                ),
                AIModel(
                    id: "gpt-5.1-chat-latest",
                    name: "GPT-5.1 Chat Latest",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Latest conversational variant with multimodal support"
                ),
                AIModel(
                    id: "gpt-5-2025-08-07",
                    name: "GPT-5",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Flagship model for coding, reasoning, and agentic tasks"
                ),
                AIModel(
                    id: "gpt-5-mini-2025-08-07",
                    name: "GPT-5 Mini",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Fast and cost-efficient with strong performance"
                ),
                AIModel(
                    id: "gpt-5-nano-2025-08-07",
                    name: "GPT-5 Nano",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Smallest, fastest, cheapest. Great for classification and extraction"
                ),
                AIModel(
                    id: "o3",
                    name: "o3",
                    provider: .openai,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Most powerful reasoning model for coding, math, science, and vision"
                ),
                AIModel(
                    id: "o4-mini",
                    name: "o4-mini",
                    provider: .openai,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Fast, cost-efficient reasoning model with multimodal support"
                ),
                AIModel(
                    id: "o3-mini",
                    name: "o3-mini",
                    provider: .openai,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Specialized reasoning for STEM tasks with configurable effort levels"
                ),
                AIModel(
                    id: "gpt-4.1",
                    name: "GPT-4.1",
                    provider: .openai,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image"],
                    description: "Enhanced coding and instruction following with 1M context"
                ),
                AIModel(
                    id: "gpt-4.1-mini",
                    name: "GPT-4.1 Mini",
                    provider: .openai,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image"],
                    description: "Mid-tier with 1M context. Fast and cost-effective"
                ),
                AIModel(
                    id: "gpt-4.1-nano",
                    name: "GPT-4.1 Nano",
                    provider: .openai,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image"],
                    description: "Lightest 4.1 variant with 1M context for simple tasks"
                ),
                AIModel(
                    id: "o1",
                    name: "o1",
                    provider: .openai,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Advanced reasoning with vision API and function calling"
                ),
                AIModel(
                    id: "o1-mini",
                    name: "o1-mini",
                    provider: .openai,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Faster reasoning focused on coding, math, and science"
                ),
                AIModel(
                    id: "gpt-4o",
                    name: "GPT-4o",
                    provider: .openai,
                    contextWindow: 128_000,
                    modalities: ["text", "image", "audio"],
                    description: "Multimodal flagship with text, audio, image, and video"
                ),
                AIModel(
                    id: "gpt-4o-mini",
                    name: "GPT-4o Mini",
                    provider: .openai,
                    contextWindow: 128_000,
                    modalities: ["text", "image", "audio"],
                    description: "Cost-efficient multimodal model with vision support"
                )
            ]
        case .gemini:
            return [
                AIModel(
                    id: "gemini-3-pro-preview",
                    name: "Gemini 3 Pro Preview",
                    provider: .gemini,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image", "video", "audio", "pdf"],
                    description: "Most powerful agentic and coding model with advanced reasoning"
                ),
                AIModel(
                    id: "gemini-3-flash-preview",
                    name: "Gemini 3 Flash Preview",
                    provider: .gemini,
                    contextWindow: 1_048_576,
                    modalities: ["text", "image", "video", "audio", "pdf"],
                    description: "Most intelligent model built for speed, combining frontier intelligence with superior search and grounding"
                ),
                AIModel(
                    id: "gemini-2.5-flash-lite-preview-06-17",
                    name: "Gemini 2.5 Flash Lite Preview",
                    provider: .gemini,
                    contextWindow: 1_048_576,
                    modalities: ["text", "image", "video", "audio"],
                    description: "Ultra-low latency, cost-efficient lightweight reasoning model"
                ),
                AIModel(
                    id: "gemini-2.5-pro",
                    name: "Gemini 2.5 Pro",
                    provider: .gemini,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image", "video", "audio", "pdf"],
                    description: "Most capable Gemini model"
                ),
                AIModel(
                    id: "gemini-2.5-flash",
                    name: "Gemini 2.5 Flash",
                    provider: .gemini,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image", "video", "audio"],
                    description: "Fast, efficient model"
                )
            ]
        case .xai:
            return [
                AIModel(
                    id: "grok-4-fast-reasoning",
                    name: "Grok 4 Fast Reasoning",
                    provider: .xai,
                    contextWindow: 2_000_000,
                    modalities: ["text", "image"],
                    description: "Cost-efficient reasoning model with 2M context. 98% cheaper than previous models"
                ),
                AIModel(
                    id: "grok-4-fast-non-reasoning",
                    name: "Grok 4 Fast Non-Reasoning",
                    provider: .xai,
                    contextWindow: 2_000_000,
                    modalities: ["text", "image"],
                    description: "Ultra-fast non-reasoning model with 2M context window"
                ),
                AIModel(
                    id: "grok-code-fast-1",
                    name: "Grok Code Fast 1",
                    provider: .xai,
                    contextWindow: 256_000,
                    modalities: ["text"],
                    description: "Specialized coding model with high throughput for large codebases"
                ),
                AIModel(
                    id: "grok-4-0709",
                    name: "Grok 4 (0709)",
                    provider: .xai,
                    contextWindow: 256_000,
                    modalities: ["text", "image"],
                    description: "Flagship model with advanced reasoning and function calling"
                ),
                AIModel(
                    id: "grok-3-mini",
                    name: "Grok 3 Mini",
                    provider: .xai,
                    contextWindow: 131_072,
                    modalities: ["text"],
                    description: "Lightweight, cost-efficient model for simple tasks"
                ),
                AIModel(
                    id: "grok-3",
                    name: "Grok 3",
                    provider: .xai,
                    contextWindow: 131_072,
                    modalities: ["text", "image"],
                    description: "Previous generation flagship model"
                )
            ]
        case .perplexity:
            return [
                AIModel(
                    id: "sonar-reasoning-pro",
                    name: "Sonar Reasoning Pro",
                    provider: .perplexity,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Best for complex queries. Advanced reasoning + real-time web search"
                ),
                AIModel(
                    id: "sonar-reasoning",
                    name: "Sonar Reasoning",
                    provider: .perplexity,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Lighter reasoning model with web search. Good balance of speed/intelligence"
                ),
                AIModel(
                    id: "sonar-pro",
                    name: "Sonar Pro",
                    provider: .perplexity,
                    contextWindow: 200_000,
                    modalities: ["text"],
                    description: "High-capacity standard search model (no reasoning tokens)"
                ),
                AIModel(
                    id: "sonar",
                    name: "Sonar",
                    provider: .perplexity,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Cheapest standard search model. Good for simple lookups"
                )
            ]
        case .deepseek:
            return [
                AIModel(
                    id: "deepseek-reasoner",
                    name: "DeepSeek Reasoner (R1)",
                    provider: .deepseek,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Flagship reasoning model with Chain-of-Thought. Best for math/code"
                ),
                AIModel(
                    id: "deepseek-chat",
                    name: "DeepSeek Chat (V3)",
                    provider: .deepseek,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Standard frontier model. Extremely cost-effective and fast"
                )
            ]
        case .zai:
            return [
                AIModel(
                    id: "glm-4.6",
                    name: "GLM-4.6",
                    provider: .zai,
                    contextWindow: 200_000,
                    modalities: ["text"],
                    description: "Flagship model. Best reasoning, coding, and agentic capability"
                ),
                AIModel(
                    id: "glm-4.6v",
                    name: "GLM-4.6V",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Flagship vision. Native multimodal with thinking support"
                ),
                AIModel(
                    id: "glm-4.6v-flash",
                    name: "GLM-4.6V Flash",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Fast vision. Lower latency and cost"
                ),
                AIModel(
                    id: "glm-4.5",
                    name: "GLM-4.5",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Previous flagship. Strong generalist"
                ),
                AIModel(
                    id: "glm-4.5-air",
                    name: "GLM-4.5 Air",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Balanced Air tier. Speed/performance mix"
                ),
                AIModel(
                    id: "glm-4.5v",
                    name: "GLM-4.5V",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Multimodal variant of GLM-4.5"
                )
            ]
        case .minimax:
            return [
                AIModel(
                    id: "MiniMax-M2",
                    name: "MiniMax M2",
                    provider: .minimax,
                    contextWindow: 1_000_000,
                    modalities: ["text"],
                    description: "Flagship agentic model. 1M context, 92% cheaper than Claude Sonnet"
                ),
                AIModel(
                    id: "MiniMax-M2-Stable",
                    name: "MiniMax M2 Stable",
                    provider: .minimax,
                    contextWindow: 1_000_000,
                    modalities: ["text"],
                    description: "Stable version with higher rate limits"
                )
            ]
        case .mistral:
            return [
                AIModel(
                    id: "mistral-large-latest",
                    name: "Mistral Large",
                    provider: .mistral,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Flagship reasoning model. Top-tier performance"
                ),
                AIModel(
                    id: "pixtral-large-2411",
                    name: "Pixtral Large",
                    provider: .mistral,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Flagship vision. Multimodal version of Mistral Large"
                ),
                AIModel(
                    id: "pixtral-12b-2409",
                    name: "Pixtral 12B",
                    provider: .mistral,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Edge vision. Efficient multimodal model"
                ),
                AIModel(
                    id: "codestral-latest",
                    name: "Codestral",
                    provider: .mistral,
                    contextWindow: 32_000,
                    modalities: ["text"],
                    description: "Coding optimized. Best for FIM and code generation"
                )
            ]
        case .appleFoundation:
            return [
                AIModel(
                    id: "apple-foundation-default",
                    name: "Apple Intelligence",
                    provider: .appleFoundation,
                    contextWindow: 4_096,
                    modalities: ["text"],
                    description: "On-device ~3B model. Private, offline, free. Requires iOS 26+"
                )
            ]
        case .localMLX:
            // Built-in models from LocalMLXModel enum
            // User-added models are appended dynamically via SettingsViewModel
            return [
                // Default bundled model (first in list)
                AIModel(
                    id: "mlx-community/Qwen3-VL-2B-Instruct-4bit",
                    name: "Qwen3 VL 2B",
                    provider: .localMLX,
                    contextWindow: 8_192,
                    modalities: ["text", "vision"],
                    description: "Vision-language model. Bundled in app - ready instantly. Private, offline, free."
                ),
                // Downloadable models
                AIModel(
                    id: "mlx-community/SmolLM2-1.7B-Instruct-4bit",
                    name: "SmolLM2 1.7B",
                    provider: .localMLX,
                    contextWindow: 8_192,
                    modalities: ["text"],
                    description: "HuggingFace's efficient small model. ~1GB download. Private, offline, free."
                ),
                AIModel(
                    id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
                    name: "Llama 3.2 1B",
                    provider: .localMLX,
                    contextWindow: 8_192,
                    modalities: ["text"],
                    description: "Meta's compact model. ~0.7GB download. Private, offline, free."
                ),
                AIModel(
                    id: "mlx-community/Qwen3-1.7B-4bit",
                    name: "Qwen3 1.7B",
                    provider: .localMLX,
                    contextWindow: 32_768,
                    modalities: ["text"],
                    description: "Alibaba's multilingual model. ~1GB download. Private, offline, free."
                ),
                AIModel(
                    id: "mlx-community/Phi-4-mini-instruct-4bit",
                    name: "Phi-4 Mini",
                    provider: .localMLX,
                    contextWindow: 16_384,
                    modalities: ["text"],
                    description: "Microsoft's capable small model. ~2GB download. Private, offline, free."
                )
            ]
        }
    }

    /// Whether this provider is available on the current device/OS
    var isAvailable: Bool {
        switch self {
        case .appleFoundation:
            // Apple Foundation Models require iOS 26+ / macOS 26+
            if #available(iOS 26.0, macOS 26.0, *) {
                return true
            }
            return false
        case .localMLX:
            // MLX models require physical device with Apple Silicon (Metal GPU)
            #if targetEnvironment(simulator)
            return false
            #else
            return true
            #endif
        default:
            // Cloud providers are always available (API key validation happens separately)
            return true
        }
    }

    /// Human-readable reason if provider is unavailable
    var unavailableReason: String? {
        switch self {
        case .appleFoundation:
            if #available(iOS 26.0, macOS 26.0, *) {
                return nil
            }
            return "Requires iOS 26.0+ or macOS 26.0+"
        case .localMLX:
            #if targetEnvironment(simulator)
            return "Requires physical device (MLX uses Metal GPU)"
            #else
            return nil
            #endif
        default:
            return nil
        }
    }

    /// Find context window for a model ID across all providers
    /// Returns default of 128K if not found
    static func contextWindowForModel(_ modelId: String, settings: AppSettings? = nil) -> Int {
        // Check built-in models first
        for provider in AIProvider.allCases {
            if let model = provider.availableModels.first(where: { $0.id == modelId }) {
                return model.contextWindow
            }
        }

        // Check custom models if settings provided
        if let settings = settings {
            for customProvider in settings.customProviders {
                if let model = customProvider.models.first(where: { $0.modelCode == modelId }) {
                    return model.contextWindow
                }
            }
        }

        // Default to 128K if not found
        return 128_000
    }
}

// MARK: - AI Model

struct AIModel: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let provider: AIProvider
    let contextWindow: Int
    let modalities: [String]
    let description: String
}

// MARK: - User MLX Model (from Hugging Face)

/// User-added MLX model downloaded from Hugging Face
struct UserMLXModel: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let repoId: String              // e.g., "mlx-community/Qwen3-VL-2B-Instruct-4bit"
    let displayName: String         // e.g., "Qwen3 VL 2B"
    var downloadStatus: DownloadStatus
    var sizeBytes: Int64?
    var contextWindow: Int          // from model config or default
    var modalities: [String]        // ["text"], ["text", "vision"], etc.
    var addedAt: Date

    enum DownloadStatus: String, Codable, Sendable {
        case notDownloaded
        case downloading
        case downloaded
        case failed
    }

    /// Convert to AIModel for unified provider/model selection
    func toAIModel() -> AIModel {
        AIModel(
            id: repoId,
            name: displayName,
            provider: .localMLX,
            contextWindow: contextWindow,
            modalities: modalities,
            description: "User-added model from Hugging Face. \(formatSize(sizeBytes))"
        )
    }

    private func formatSize(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Unified Provider & Model (for UI)

/// Unified provider that can represent either built-in or custom providers
enum UnifiedProvider: Identifiable, Hashable {
    case builtIn(AIProvider)
    case custom(CustomProviderConfig)

    var id: String {
        switch self {
        case .builtIn(let provider):
            return "builtin_\(provider.rawValue)"
        case .custom(let config):
            return "custom_\(config.id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .builtIn(let provider):
            return provider.displayName
        case .custom(let config):
            return config.providerName
        }
    }

    var isCustom: Bool {
        if case .custom = self {
            return true
        }
        return false
    }

    func availableModels(customProviderIndex: Int? = nil) -> [UnifiedModel] {
        switch self {
        case .builtIn(let provider):
            return provider.availableModels.map { UnifiedModel.builtIn($0) }
        case .custom(let config):
            return config.models.enumerated().map { index, model in
                UnifiedModel.custom(model, providerName: config.providerName, providerIndex: customProviderIndex ?? 1, modelIndex: index + 1)
            }
        }
    }
}

/// Unified model that can represent either built-in or custom models
enum UnifiedModel: Identifiable, Hashable, Sendable {
    case builtIn(AIModel)
    case custom(CustomModelConfig, providerName: String, providerIndex: Int, modelIndex: Int)

    var id: String {
        switch self {
        case .builtIn(let model):
            return "builtin_\(model.id)"
        case .custom(let config, _, _, _):
            return "custom_\(config.id.uuidString)"
        }
    }

    var name: String {
        switch self {
        case .builtIn(let model):
            return model.name
        case .custom(let config, let providerName, _, _):
            return config.displayName(providerName: providerName)
        }
    }

    var description: String {
        switch self {
        case .builtIn(let model):
            return model.description
        case .custom(let config, _, let providerIndex, let modelIndex):
            return config.displayDescription(providerIndex: providerIndex, modelIndex: modelIndex)
        }
    }

    var contextWindow: Int {
        switch self {
        case .builtIn(let model):
            return model.contextWindow
        case .custom(let config, _, _, _):
            return config.contextWindow
        }
    }

    var modalities: [String] {
        switch self {
        case .builtIn(let model):
            return model.modalities
        case .custom:
            // Assume custom models support text and image by default, or make it configurable later
            return ["text", "image"]
        }
    }

    var pricing: CustomModelPricing? {
        switch self {
        case .builtIn:
            return nil  // Built-in models use PricingRegistry
        case .custom(let config, _, _, _):
            return config.pricing
        }
    }

    var modelCode: String {
        switch self {
        case .builtIn(let model):
            return model.id
        case .custom(let config, _, _, _):
            return config.modelCode
        }
    }
}

// MARK: - API Provider

enum APIProvider: String, CaseIterable, Identifiable {
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case xai = "xai"
    case elevenlabs = "elevenlabs"
    case perplexity = "perplexity"
    case deepseek = "deepseek"
    case zai = "zai"
    case minimax = "minimax"
    case mistral = "mistral"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .xai: return "xAI"
        case .elevenlabs: return "ElevenLabs"
        case .perplexity: return "Perplexity"
        case .deepseek: return "DeepSeek"
        case .zai: return "Z.ai (Zhipu)"
        case .minimax: return "MiniMax"
        case .mistral: return "Mistral AI"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .gemini: return "AIza..."
        case .xai: return "xai-..."
        case .elevenlabs: return "sk_..."
        case .perplexity: return "pplx-..."
        case .deepseek: return "sk-..."
        case .zai: return "..."
        case .minimax: return "..."
        case .mistral: return "..."
        }
    }

    var infoURL: URL? {
        switch self {
        case .openai: return URL(string: "https://platform.openai.com/account/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/account/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .xai: return URL(string: "https://console.x.ai")
        case .elevenlabs: return URL(string: "https://elevenlabs.io/app/settings/api-keys")
        case .perplexity: return URL(string: "https://www.perplexity.ai/settings/api")
        case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")
        case .zai: return URL(string: "https://bigmodel.cn/usercenter/apikeys")
        case .minimax: return URL(string: "https://platform.minimax.io/user-center/basic-information/interface-key")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        }
    }

    var description: String {
        switch self {
        case .openai: return "Required for GPT models"
        case .anthropic: return "Required for Claude models"
        case .gemini: return "Required for Gemini models"
        case .xai: return "Required for Grok models"
        case .elevenlabs: return "Required for text-to-speech"
        case .perplexity: return "Required for Sonar models (online search)"
        case .deepseek: return "Required for DeepSeek models"
        case .zai: return "Required for GLM models"
        case .minimax: return "Required for MiniMax M2 models"
        case .mistral: return "Required for Mistral and Pixtral models"
        }
    }
}

// MARK: - TTS Settings

/// TTS provider selection - mutually exclusive
enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case apple = "apple"          // Native Apple TTS (free, no API key required)
    case kokoro = "kokoro"        // On-device neural TTS via Kokoro (free, no API key required)
    case mlxAudio = "mlxAudio"    // On-device neural TTS via F5-TTS (free, no API key required) - DISABLED
    case elevenlabs = "elevenlabs"
    case gemini = "gemini"
    case openai = "openai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple (Siri)"
        case .kokoro: return "Kokoro Neural"
        case .mlxAudio: return "F5 Neural"
        case .elevenlabs: return "ElevenLabs"
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        }
    }

    var description: String {
        switch self {
        case .apple: return "On-device Siri voices • Free • No API key"
        case .kokoro: return "On-device neural TTS • Free • ~600MB model"
        case .mlxAudio: return "On-device neural TTS • Free • ~300MB model"
        case .elevenlabs: return "High-quality voices with fine-tuned controls"
        case .gemini: return "Google's TTS with expressive voices"
        case .openai: return "Promptable TTS with natural voices"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "apple.logo"
        case .kokoro: return "waveform.badge.magnifyingglass"
        case .mlxAudio: return "waveform.badge.mic"
        case .elevenlabs: return "waveform"
        case .gemini: return "sparkles"
        case .openai: return "brain.head.profile"
        }
    }

    /// Whether this provider requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .apple, .kokoro, .mlxAudio: return false
        case .elevenlabs, .gemini, .openai: return true
        }
    }
}

/// Voice gender classification
enum VoiceGender: String, Codable, CaseIterable {
    case male
    case female

    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }

    var icon: String {
        switch self {
        case .male: return "person.fill"
        case .female: return "person.fill"
        }
    }
}

/// Gemini TTS voice options (all 30 available voices)
enum GeminiTTSVoice: String, Codable, CaseIterable, Identifiable {
    // Original voices
    case zephyr = "Zephyr"
    case puck = "Puck"
    case charon = "Charon"
    case kore = "Kore"
    case fenrir = "Fenrir"
    case leda = "Leda"
    case orus = "Orus"
    case aoede = "Aoede"
    // Additional voices
    case callirrhoe = "Callirrhoe"
    case autonoe = "Autonoe"
    case enceladus = "Enceladus"
    case iapetus = "Iapetus"
    case umbriel = "Umbriel"
    case algieba = "Algieba"
    case despina = "Despina"
    case erinome = "Erinome"
    case algenib = "Algenib"
    case rasalgethi = "Rasalgethi"
    case laomedeia = "Laomedeia"
    case achernar = "Achernar"
    case alnilam = "Alnilam"
    case schedar = "Schedar"
    case gacrux = "Gacrux"
    case pulcherrima = "Pulcherrima"
    case achird = "Achird"
    case zubenelgenubi = "Zubenelgenubi"
    case vindemiatrix = "Vindemiatrix"
    case sadachbia = "Sadachbia"
    case sadaltager = "Sadaltager"
    case sulafat = "Sulafat"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// Voice gender based on the mythological/astronomical origin of the name
    var gender: VoiceGender {
        switch self {
        // Female voices (Greek goddesses, nymphs, muses, female figures)
        case .kore: return .female          // Persephone/maiden
        case .leda: return .female          // Queen of Sparta
        case .aoede: return .female         // Muse of song
        case .callirrhoe: return .female    // Ocean nymph
        case .autonoe: return .female       // Daughter of Cadmus
        case .despina: return .female       // Sea nymph
        case .erinome: return .female       // One of the Graces
        case .laomedeia: return .female     // Sea nymph
        case .pulcherrima: return .female   // Latin "most beautiful"
        case .vindemiatrix: return .female  // Latin "grape gatherer"
        // Male voices (Greek gods, titans, male figures, stars with male names)
        case .zephyr: return .male          // God of west wind
        case .puck: return .male            // Mischievous sprite
        case .charon: return .male          // Ferryman of Hades
        case .fenrir: return .male          // Norse wolf
        case .orus: return .male            // Variant of Horus
        case .enceladus: return .male       // Giant
        case .iapetus: return .male         // Titan
        case .umbriel: return .male         // Moon of Uranus (male spirit)
        case .algieba: return .male         // Star name
        case .algenib: return .male         // Star name
        case .rasalgethi: return .male      // "Head of the kneeler"
        case .achernar: return .male        // Star name
        case .alnilam: return .male         // Star name
        case .schedar: return .male         // Star name
        case .gacrux: return .male          // Star name
        case .achird: return .male          // Star name
        case .zubenelgenubi: return .male   // Star name
        case .sadachbia: return .male       // Star name
        case .sadaltager: return .male      // Star name
        case .sulafat: return .male         // Star name
        }
    }

    var toneDescription: String {
        switch self {
        case .zephyr: return "Bright"
        case .puck: return "Upbeat"
        case .charon: return "Informative"
        case .kore: return "Firm"
        case .fenrir: return "Excitable"
        case .leda: return "Youthful"
        case .orus: return "Firm"
        case .aoede: return "Breezy"
        case .callirrhoe: return "Easy-going"
        case .autonoe: return "Bright"
        case .enceladus: return "Breathy"
        case .iapetus: return "Clear"
        case .umbriel: return "Easy-going"
        case .algieba: return "Smooth"
        case .despina: return "Smooth"
        case .erinome: return "Clear"
        case .algenib: return "Gravelly"
        case .rasalgethi: return "Informative"
        case .laomedeia: return "Upbeat"
        case .achernar: return "Soft"
        case .alnilam: return "Firm"
        case .schedar: return "Even"
        case .gacrux: return "Mature"
        case .pulcherrima: return "Forward"
        case .achird: return "Friendly"
        case .zubenelgenubi: return "Casual"
        case .vindemiatrix: return "Gentle"
        case .sadachbia: return "Lively"
        case .sadaltager: return "Knowledgeable"
        case .sulafat: return "Warm"
        }
    }

    /// Get all voices filtered by gender
    static func voices(for gender: VoiceGender) -> [GeminiTTSVoice] {
        allCases.filter { $0.gender == gender }
    }
}

/// Gemini TTS model options
enum GeminiTTSModel: String, Codable, CaseIterable, Identifiable {
    case flash = "gemini-2.5-flash-preview-tts"
    case pro = "gemini-2.5-pro-preview-tts"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flash: return "Flash (Faster)"
        case .pro: return "Pro (Higher Quality)"
        }
    }

    var description: String {
        switch self {
        case .flash: return "Optimized for speed and cost efficiency"
        case .pro: return "Best quality, more expressive output"
        }
    }
}

/// OpenAI TTS voice options (10 built-in voices)
enum OpenAITTSVoice: String, Codable, CaseIterable, Identifiable {
    case alloy = "alloy"
    case ash = "ash"
    case ballad = "ballad"
    case coral = "coral"
    case echo = "echo"
    case fable = "fable"
    case nova = "nova"
    case onyx = "onyx"
    case sage = "sage"
    case shimmer = "shimmer"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Voice gender based on OpenAI's documented voice characteristics
    var gender: VoiceGender {
        switch self {
        // Female voices
        case .alloy: return .female     // Neutral female
        case .coral: return .female     // Clear, friendly female
        case .nova: return .female      // Bright, upbeat female
        case .shimmer: return .female   // Light, airy female
        case .ballad: return .female    // Soft, expressive female
        // Male voices
        case .ash: return .male         // Warm, confident male
        case .echo: return .male        // Measured, composed male
        case .fable: return .male       // Expressive male (British)
        case .onyx: return .male        // Deep, authoritative male
        case .sage: return .male        // Calm, thoughtful male
        }
    }

    var toneDescription: String {
        switch self {
        case .alloy: return "Neutral, balanced"
        case .ash: return "Warm, confident"
        case .ballad: return "Soft, expressive"
        case .coral: return "Clear, friendly"
        case .echo: return "Measured, composed"
        case .fable: return "Expressive, storytelling"
        case .nova: return "Bright, upbeat"
        case .onyx: return "Deep, authoritative"
        case .sage: return "Calm, thoughtful"
        case .shimmer: return "Light, airy"
        }
    }

    /// Get all voices filtered by gender
    static func voices(for gender: VoiceGender) -> [OpenAITTSVoice] {
        allCases.filter { $0.gender == gender }
    }
}

/// OpenAI TTS model options
enum OpenAITTSModel: String, Codable, CaseIterable, Identifiable {
    case gpt4oMiniTTS = "gpt-4o-mini-tts"
    case tts1 = "tts-1"
    case tts1HD = "tts-1-hd"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt4oMiniTTS: return "GPT-4o Mini TTS"
        case .tts1: return "TTS-1"
        case .tts1HD: return "TTS-1 HD"
        }
    }

    var description: String {
        switch self {
        case .gpt4oMiniTTS: return "Newest, promptable voice control"
        case .tts1: return "Fast, lower latency"
        case .tts1HD: return "Higher quality audio"
        }
    }

    /// Whether this model supports the instructions parameter
    var supportsInstructions: Bool {
        switch self {
        case .gpt4oMiniTTS: return true
        case .tts1, .tts1HD: return false
        }
    }
}

/// Quality tier for cost optimization
enum TTSQualityTier: String, Codable, CaseIterable, Identifiable {
    case standard    // Lower cost, faster
    case high        // Best quality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High Quality"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Faster, lower cost"
        case .high: return "Best quality audio"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "bolt"
        case .high: return "waveform"
        }
    }
}

struct TTSSettings: Codable, Equatable {
    /// Active TTS provider (defaults to Apple TTS for zero-config experience)
    var provider: TTSProvider = .apple

    /// Quality tier - affects model selection per provider
    var qualityTier: TTSQualityTier = .high

    // MARK: - TTS Text Preprocessing

    /// Default behavior: convert Markdown to rendered plaintext before sending to TTS.
    /// This prevents voices from reading formatting symbols.
    var stripMarkdownBeforeTTS: Bool = true

    /// Optional second-pass normalization to make text more spoken-friendly.
    /// Off by default to preserve fidelity to displayed text.
    var spokenFriendlyTTS: Bool = false

    // MARK: - Voice Gender Filter
    /// Filter voices by gender (nil = show all)
    var voiceGenderFilter: VoiceGender? = nil

    // MARK: - Apple TTS Settings
    var appleVoice: AppleTTSVoice = .samantha
    /// Speech rate (0.0 to 1.0, where 0.5 is default/normal)
    var appleRate: Float = 0.5

    // MARK: - ElevenLabs Settings
    var model: TTSModel = .turboV25
    var outputFormat: TTSOutputFormat = .mp3128
    var voiceSettings: VoiceSettings = VoiceSettings()
    var selectedVoiceId: String? = nil
    var selectedVoiceName: String? = nil
    var cachedVoices: [ElevenLabsService.ELVoice] = []

    // MARK: - Gemini TTS Settings
    var geminiVoice: GeminiTTSVoice = .puck
    var geminiModel: GeminiTTSModel = .flash
    /// Voice direction/style instructions for Gemini TTS (e.g., "Speak in a cheerful, upbeat tone with a slight British accent")
    /// Gemini TTS supports natural language prompts to control style, accent, pace, and tone
    var geminiVoiceDirection: String = ""

    // MARK: - OpenAI TTS Settings
    var openaiVoice: OpenAITTSVoice = .alloy
    var openaiModel: OpenAITTSModel = .gpt4oMiniTTS
    /// Voice instructions for GPT-4o Mini TTS (e.g., "Speak in a cheerful tone")
    var openaiVoiceInstructions: String = ""
    /// Speed multiplier (0.25 to 4.0, default 1.0)
    var openaiSpeed: Double = 1.0

    // MARK: - F5-TTS Settings
    var mlxVoice: MLXTTSVoice = .defaultVoice
    /// Speech speed (0.5 to 2.0, default 1.0)
    var mlxSpeed: Float = 1.0

    // MARK: - Kokoro TTS Settings
    var kokoroVoice: KokoroTTSVoice = .af_heart
    /// Speech speed (0.5 to 2.0, default 1.0)
    var kokoroSpeed: Float = 1.0
    /// Set of downloaded voice IDs (for tracking which voices have been downloaded)
    var downloadedKokoroVoices: Set<String> = []

    // MARK: - Computed Properties for Quality Tier

    /// Get the appropriate ElevenLabs model based on quality tier
    var effectiveElevenLabsModel: TTSModel {
        switch qualityTier {
        case .standard: return .flashV25
        case .high: return model
        }
    }

    /// Get the appropriate Gemini model based on quality tier
    var effectiveGeminiModel: GeminiTTSModel {
        switch qualityTier {
        case .standard: return .flash
        case .high: return geminiModel
        }
    }

    /// Get the appropriate OpenAI model based on quality tier
    var effectiveOpenAIModel: OpenAITTSModel {
        switch qualityTier {
        case .standard: return .tts1
        case .high: return openaiModel
        }
    }
}

enum TTSModel: String, Codable, CaseIterable, Identifiable {
    case turboV25 = "eleven_turbo_v2_5"
    case multilingualV2 = "eleven_multilingual_v2"
    case flashV25 = "eleven_flash_v2_5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turboV25: return "Turbo v2.5"
        case .multilingualV2: return "Multilingual v2"
        case .flashV25: return "Flash v2.5"
        }
    }

    var description: String {
        switch self {
        case .turboV25: return "Fastest, most natural"
        case .multilingualV2: return "Supports 29 languages"
        case .flashV25: return "Latest flash model"
        }
    }
}

enum TTSOutputFormat: String, Codable, CaseIterable, Identifiable {
    case mp3128 = "mp3_44100_128"
    case mp364 = "mp3_44100_64"
    case mp332 = "mp3_22050_32"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mp3128: return "MP3 128kbps"
        case .mp364: return "MP3 64kbps"
        case .mp332: return "MP3 32kbps"
        }
    }

    var description: String {
        switch self {
        case .mp3128: return "Highest quality"
        case .mp364: return "Balanced"
        case .mp332: return "Smallest size"
        }
    }
}

struct VoiceSettings: Codable, Equatable {
    var stability: Double = 0.5
    var similarityBoost: Double = 0.75
    var style: Double = 0.0
    var useSpeakerBoost: Bool = false
}

// MARK: - Tool Execution Mode

/// Controls when tool requests are executed during a conversation
enum ToolExecutionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Tools execute automatically as soon as they're streamed from the assistant
    case immediate

    /// Tools show "Apply" button; results are sent with the user's next message
    case deferred

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .immediate: return "Immediate"
        case .deferred: return "Deferred"
        }
    }

    var description: String {
        switch self {
        case .immediate: return "Execute tools automatically as they stream"
        case .deferred: return "Review and apply tools manually"
        }
    }

    var icon: String {
        switch self {
        case .immediate: return "bolt.fill"
        case .deferred: return "hand.tap.fill"
        }
    }
}

// MARK: - Tool Settings

/// Settings for AI tool use (web search, code execution, etc.)
struct ToolSettings: Codable, Equatable, Sendable {
    /// Master toggle for tool use
    var toolsEnabled: Bool = false

    /// Set of enabled tool IDs
    var enabledToolIds: Set<String> = []

    /// Maximum tool calls per conversation turn
    var maxToolCallsPerTurn: Int = 5

    /// Tool execution timeout in seconds
    var toolTimeout: Int = 30

    /// Enable experimental features
    var experimentalFeaturesEnabled: Bool = false

    /// Enable Gemini media proxy for video/audio understanding (experimental)
    /// When enabled, video/audio attachments sent to non-Gemini providers
    /// will be analyzed by Gemini first, with the analysis passed to the primary model
    var mediaProxyEnabled: Bool = false

    /// Enable chat debug mode (developer feature)
    /// Shows detailed context breakdown, token counts, and injection details in chat
    var chatDebugEnabled: Bool = false

    /// Tool execution mode: immediate (auto-execute) or deferred (manual apply)
    var executionMode: ToolExecutionMode = .immediate

    /// Helper to check if a specific tool is enabled
    func isToolEnabled(_ tool: ToolId) -> Bool {
        toolsEnabled && enabledToolIds.contains(tool.rawValue)
    }

    /// Helper to get enabled tools as ToolId array
    var enabledTools: [ToolId] {
        enabledToolIds.compactMap { ToolId(rawValue: $0) }
    }

    /// Enable a tool
    mutating func enableTool(_ tool: ToolId) {
        enabledToolIds.insert(tool.rawValue)
    }

    /// Disable a tool
    mutating func disableTool(_ tool: ToolId) {
        enabledToolIds.remove(tool.rawValue)
    }

    /// Toggle a tool
    mutating func toggleTool(_ tool: ToolId) {
        if enabledToolIds.contains(tool.rawValue) {
            enabledToolIds.remove(tool.rawValue)
        } else {
            enabledToolIds.insert(tool.rawValue)
        }
    }

    /// Enable all tools in a category
    mutating func enableCategory(_ category: ToolCategory) {
        let tools = ToolId.tools(for: category)
        for tool in tools {
            enableTool(tool)
        }
    }

    /// Disable all tools in a category
    mutating func disableCategory(_ category: ToolCategory) {
        let tools = ToolId.tools(for: category)
        for tool in tools {
            disableTool(tool)
        }
    }

    /// Check if all tools in a category are enabled
    func isCategoryFullyEnabled(_ category: ToolCategory) -> Bool {
        let tools = ToolId.tools(for: category)
        return tools.allSatisfy { isToolEnabled($0) }
    }

    /// Check if any tools in a category are enabled
    func isCategoryPartiallyEnabled(_ category: ToolCategory) -> Bool {
        let tools = ToolId.tools(for: category)
        return tools.contains { isToolEnabled($0) }
    }

    /// Count of enabled tools in a category
    func enabledCountForCategory(_ category: ToolCategory) -> Int {
        let tools = ToolId.tools(for: category)
        return tools.filter { isToolEnabled($0) }.count
    }
}

// MARK: - Heartbeat Settings

enum HeartbeatModuleId: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemStatus = "system_status"
    case recentMessages = "recent_messages"
    case lastInternalThreadEntry = "last_internal_thread_entry"
    case pendingApprovals = "pending_approvals"
    case lastHeartbeat = "last_heartbeat"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemStatus: return "System Status"
        case .recentMessages: return "Recent Messages"
        case .lastInternalThreadEntry: return "Last Internal Thread Entry"
        case .pendingApprovals: return "Pending Approvals"
        case .lastHeartbeat: return "Last Heartbeat"
        }
    }
}

struct HeartbeatDeliveryProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var moduleIds: [HeartbeatModuleId]
    var description: String?

    static let defaultProfileId = "balanced"

    static let defaultProfiles: [HeartbeatDeliveryProfile] = [
        HeartbeatDeliveryProfile(
            id: "balanced",
            name: "Balanced",
            moduleIds: [.systemStatus, .recentMessages, .lastInternalThreadEntry, .pendingApprovals],
            description: "Default mix of status, recent context, and internal thread history."
        ),
        HeartbeatDeliveryProfile(
            id: "light",
            name: "Lightweight",
            moduleIds: [.systemStatus, .lastInternalThreadEntry],
            description: "Minimal context for quick check-ins."
        ),
        HeartbeatDeliveryProfile(
            id: "deep",
            name: "Deep Context",
            moduleIds: [.systemStatus, .recentMessages, .lastInternalThreadEntry, .pendingApprovals, .lastHeartbeat],
            description: "More context and continuity across heartbeats."
        )
    ]
}

// MARK: - Heartbeat Execution Mode

/// Determines how heartbeat triggers execute - silently or as visible solo threads
enum HeartbeatExecutionMode: String, Codable, CaseIterable, Sendable {
    /// Current behavior: silent reflection, no tools, no visible thread
    case internalThread
    
    /// Visible conversation with tool access and turn allocation
    case soloThread
    
    var displayName: String {
        switch self {
        case .internalThread: return "Internal Thread"
        case .soloThread: return "Solo Thread"
        }
    }
    
    var description: String {
        switch self {
        case .internalThread:
            return "Quiet reflection and note-taking in the internal thread"
        case .soloThread:
            return "Visible conversation with tool access and turn allocation"
        }
    }
    
    var icon: String {
        switch self {
        case .internalThread: return "text.bubble"
        case .soloThread: return "bolt.circle.fill"
        }
    }
}

struct HeartbeatSettings: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var intervalSeconds: Int = 3600
    var deliveryProfileId: String = HeartbeatDeliveryProfile.defaultProfileId
    var maxTokensBudget: Int = 800
    var maxToolCalls: Int = 0
    var allowBackground: Bool = false
    var allowNotifications: Bool = true
    var liveActivityEnabled: Bool = true
    var quietHours: TimeRestrictions? = nil
    var deliveryProfiles: [HeartbeatDeliveryProfile] = HeartbeatDeliveryProfile.defaultProfiles
    
    // MARK: - Solo Thread Configuration
    
    /// Execution mode for heartbeat triggers
    var executionMode: HeartbeatExecutionMode = .internalThread
    
    /// Number of turns allocated per solo thread session
    var soloTurnsPerSession: Int = 5
    
    /// Maximum solo sessions per day
    var soloMaxSessionsPerDay: Int = 3
    
    /// Tool categories allowed in solo threads
    var soloAllowedToolCategories: [ToolCategory] = [
        .memoryReflection, .internalThread, .toolDiscovery
    ]
    
    /// Number of solo sessions completed today (resets daily)
    var soloSessionsToday: Int = 0
    
    /// Date of last solo session count reset
    var soloSessionsResetDate: Date?

    func profile(for id: String) -> HeartbeatDeliveryProfile? {
        deliveryProfiles.first { $0.id == id }
    }
    
    /// Whether more solo sessions are available today
    var canStartSoloSession: Bool {
        soloSessionsToday < soloMaxSessionsPerDay
    }
    
    /// Reset daily session count if it's a new day
    mutating func resetDailyCountIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if let resetDate = soloSessionsResetDate {
            let lastReset = calendar.startOfDay(for: resetDate)
            if lastReset < today {
                soloSessionsToday = 0
                soloSessionsResetDate = Date()
            }
        } else {
            soloSessionsResetDate = Date()
        }
    }
}

// MARK: - Small Model Optimization

/// Configuration for optimizing context injection for small/quantized models
/// These models benefit from heuristics (compressed insights) rather than raw memories
struct SmallModelOptimization: Codable, Equatable, Sendable {
    /// Enable automatic detection and optimization for small models
    var enabled: Bool = true

    /// Use heuristics-only mode (no raw memories) for detected small models
    var useHeuristicsOnly: Bool = true

    /// Maximum memories to inject for small models (when not using heuristics-only)
    var maxMemoriesForSmallModels: Int = 3

    /// Token budget for context injection in small models
    var smallModelTokenBudget: Int = 500

    /// Skip conversation summary injection for small models
    var skipConversationSummary: Bool = true

    /// Skip conversation history search for small models
    var skipConversationSearch: Bool = true

    /// Model identifiers that should use small model optimization
    /// Matched by substring (e.g., "2B" matches "Qwen3-VL-2B-Instruct-4bit")
    var smallModelPatterns: [String] = [
        "1B", "1.7B", "2B", "3B",           // Parameter counts
        "4bit", "3bit",                      // Heavy quantization
        "SmolLM", "Phi-4-mini",              // Known small models
        "Qwen3-VL-2B", "Llama-3.2-1B"        // Specific small models
    ]

    /// Check if a model identifier matches small model patterns
    func isSmallModel(_ modelId: String) -> Bool {
        guard enabled else { return false }
        let modelIdLower = modelId.lowercased()
        return smallModelPatterns.contains { pattern in
            modelIdLower.contains(pattern.lowercased())
        }
    }
}

// MARK: - Heuristics Settings

/// Settings for the cognitive compression layer (Heuristics)
struct HeuristicsSettings: Codable, Equatable, Sendable {
    var enabled: Bool = true

    // Per-type synthesis intervals (seconds)
    var frequencyIntervalSeconds: Int = 86400     // Daily
    var recencyIntervalSeconds: Int = 14400       // Every 4 hours
    var curiosityIntervalSeconds: Int = 86400     // Daily
    var interestIntervalSeconds: Int = 604800     // Weekly

    // Meta-synthesis (distillation of old heuristics)
    var metaSynthesisIntervalSeconds: Int = 604800  // Weekly
    var archiveAfterDays: Int = 30                   // Archive heuristics older than this

    // On-device model settings
    var useOnDeviceModels: Bool = true
    var onDeviceModelId: String = "mlx-community/SmolLM2-1.7B-Instruct-4bit"

    // Injection settings
    var contextWindowThreshold: Int = 8000   // Token threshold for injection
    var heuristicsMemoryRatio: Double = 0.3  // 30% heuristics, 70% memories when injecting

    // Small model optimization - use heuristics instead of raw memories for context-constrained models
    var smallModelOptimization: SmallModelOptimization = SmallModelOptimization()

    // Quality thresholds
    var minConfidence: Double = 0.6
    var minTagFrequency: Int = 3  // Ignore rare tags

    /// Get the synthesis interval for a specific heuristic type
    func interval(for type: HeuristicType) -> Int {
        switch type {
        case .frequency: return frequencyIntervalSeconds
        case .recency: return recencyIntervalSeconds
        case .curiosity: return curiosityIntervalSeconds
        case .interest: return interestIntervalSeconds
        }
    }

    /// Set the synthesis interval for a specific heuristic type
    mutating func setInterval(_ seconds: Int, for type: HeuristicType) {
        switch type {
        case .frequency: frequencyIntervalSeconds = seconds
        case .recency: recencyIntervalSeconds = seconds
        case .curiosity: curiosityIntervalSeconds = seconds
        case .interest: interestIntervalSeconds = seconds
        }
    }
}

/// Categories for organizing tools in the UI
enum ToolCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case geminiTools = "gemini_tools"
    case openaiTools = "openai_tools"
    case memoryReflection = "memory_reflection"
    case internalThread = "internal_thread"
    case heartbeat = "heartbeat"
    case coSovereignty = "co_sovereignty"
    case systemState = "system_state"
    case multiDevice = "multi_device"
    case subAgentOrchestration = "sub_agent_orchestration"
    case systemControl = "system_control"
    case toolDiscovery = "tool_discovery"
    case debugging = "debugging"
    case temporalSymmetry = "temporal_symmetry"
    case externalApps = "external_apps"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .geminiTools: return "Gemini Tools"
        case .openaiTools: return "OpenAI Tools"
        case .memoryReflection: return "Memory & Reflection"
        case .internalThread: return "Internal Thread"
        case .heartbeat: return "Heartbeat"
        case .coSovereignty: return "Co-Sovereignty"
        case .systemState: return "System State"
        case .multiDevice: return "Multi-Device Presence"
        case .subAgentOrchestration: return "Sub-Agent Orchestration"
        case .systemControl: return "System Control"
        case .toolDiscovery: return "Tool Discovery"
        case .debugging: return "Debugging"
        case .temporalSymmetry: return "Temporal Symmetry"
        case .externalApps: return "External Apps"
        }
    }

    var description: String {
        switch self {
        case .geminiTools: return "Google-powered tools for search, code execution, and maps"
        case .openaiTools: return "OpenAI-powered tools for web search, images, and research"
        case .memoryReflection: return "Create memories and reflect on conversations"
        case .internalThread: return "AI's private workspace for notes and context"
        case .heartbeat: return "Scheduled check-ins and notifications"
        case .coSovereignty: return "Covenant-based trust and permissions"
        case .systemState: return "Query and modify system configuration"
        case .multiDevice: return "Cross-device presence and handoff"
        case .subAgentOrchestration: return "Spawn and manage sub-agents (scouts, mechanics, designers)"
        case .systemControl: return "Notifications and persistence control"
        case .toolDiscovery: return "Discover and query available tools"
        case .debugging: return "Debug VS Code bridge and connections"
        case .temporalSymmetry: return "Mutual time awareness between human and AI"
        case .externalApps: return "Invoke external iOS apps via URL schemes and Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .geminiTools: return "globe"
        case .openaiTools: return "cpu"
        case .memoryReflection: return "brain.head.profile"
        case .internalThread: return "doc.text"
        case .heartbeat: return "heart.circle"
        case .coSovereignty: return "doc.badge.gearshape"
        case .systemState: return "gearshape.2"
        case .multiDevice: return "iphone.and.arrow.forward"
        case .subAgentOrchestration: return "person.3.sequence"
        case .systemControl: return "slider.horizontal.3"
        case .toolDiscovery: return "list.bullet"
        case .debugging: return "ladybug"
        case .temporalSymmetry: return "clock.badge.checkmark"
        case .externalApps: return "app.connected.to.app.below.fill"
        }
    }
}

/// Available tool identifiers
enum ToolId: String, Codable, CaseIterable, Identifiable, Sendable {
    // Gemini Native Tools (called directly via Gemini API)
    case googleSearch = "google_search"
    case codeExecution = "code_execution"
    case urlContext = "url_context"
    case googleMaps = "google_maps"
    case fileSearch = "file_search"  // RAG-based document search (Gemini 2.5+, 3.0+)
    case geminiVideoGeneration = "gemini_video_gen"  // Veo 3.1 video generation

    // OpenAI Native Tools (called directly via OpenAI API)
    case openaiWebSearch = "openai_web_search"      // Web search via gpt-4o-search-preview
    case openaiImageGeneration = "openai_image_gen" // Image generation via gpt-image-1
    case openaiDeepResearch = "openai_deep_research" // Deep research via o3-deep-research
    case openaiVideoGeneration = "openai_video_gen"   // Sora video generation

    // Built-in Tools
    case createMemory = "create_memory"
    case conversationSearch = "conversation_search"  // Search recent conversations for context
    case reflectOnConversation = "reflect_on_conversation"  // Meta-analysis of current conversation
    case agentStateAppend = "agent_state_append"
    case agentStateQuery = "agent_state_query"
    case agentStateClear = "agent_state_clear"
    case heartbeatConfigure = "heartbeat_configure"
    case heartbeatRunOnce = "heartbeat_run_once"
    case heartbeatSetDeliveryProfile = "heartbeat_set_delivery_profile"
    case heartbeatUpdateProfile = "heartbeat_update_profile"
    case persistenceDisable = "persistence_disable"
    case notifyUser = "notify_user"

    // Tool Introspection Tools
    // Used to keep system prompt injection light: model can fetch tool metadata on demand.
    case listTools = "list_tools"  // Compact list of available tools
    case getToolDetails = "get_tool_details"  // Detailed schema/usage for a specific tool

    // Co-Sovereignty Tools
    case queryCovenant = "query_covenant"  // Query current covenant status and permissions
    case proposeCovenantChange = "propose_covenant_change"  // AI proposes covenant modifications

    // System State Tools (AI self-configuration)
    case querySystemState = "query_system_state"  // Query available providers, models, tools, permissions
    case changeSystemState = "change_system_state"  // Request changes to model, provider, or tools

    // Bridge Debugging
    case debugBridge = "debug_bridge"  // Check bridge connection status and logs

    // Multi-Device Presence Tools
    case queryDevicePresence = "query_device_presence"  // Query all devices and their presence states
    case requestDeviceSwitch = "request_device_switch"  // Request to switch agent focus to another device
    case setPresenceIntent = "set_presence_intent"  // Declare intent about which device to focus
    case saveStateCheckpoint = "save_state_checkpoint"  // Manually save a state checkpoint

    // Sub-Agent Orchestration Tools
    case spawnScout = "spawn_scout"                    // Spawn a Scout sub-agent (read-only reconnaissance)
    case spawnMechanic = "spawn_mechanic"              // Spawn a Mechanic sub-agent (read+write execution)
    case spawnDesigner = "spawn_designer"              // Spawn a Designer sub-agent (task decomposition)
    case queryJobStatus = "query_job_status"           // Query status of active/completed sub-agent jobs
    case acceptJobResult = "accept_job_result"         // Accept and integrate sub-agent job result
    case terminateJob = "terminate_job"                // Terminate a running sub-agent job

    // Temporal Symmetry Tools (AI-side of /sync, /drift, /status)
    case temporalSync = "temporal_sync"                // Enable temporal sync mode (mutual awareness)
    case temporalDrift = "temporal_drift"              // Enable drift mode (timeless void)
    case temporalStatus = "temporal_status"            // Query temporal status report

    // External App Integration Tools (Port Registry)
    case discoverPorts = "discover_ports"              // List/search available external app integrations
    case invokePort = "invoke_port"                    // Invoke an external app via URL scheme

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleSearch: return "Google Search"
        case .codeExecution: return "Code Execution"
        case .urlContext: return "URL Context"
        case .googleMaps: return "Google Maps"
        case .fileSearch: return "File Search"
        case .geminiVideoGeneration: return "Video Generation"
        case .openaiWebSearch: return "Web Search"
        case .openaiImageGeneration: return "Image Generation"
        case .openaiDeepResearch: return "Deep Research"
        case .openaiVideoGeneration: return "Video Generation"
        case .createMemory: return "Memory Creation"
        case .conversationSearch: return "Conversation History"
        case .reflectOnConversation: return "Conversation Reflection"
        case .agentStateAppend: return "Internal Thread Append"
        case .agentStateQuery: return "Internal Thread Query"
        case .agentStateClear: return "Internal Thread Clear"
        case .heartbeatConfigure: return "Heartbeat Configure"
        case .heartbeatRunOnce: return "Heartbeat Run Once"
        case .heartbeatSetDeliveryProfile: return "Heartbeat Set Delivery Profile"
        case .heartbeatUpdateProfile: return "Heartbeat Update Profile"
        case .persistenceDisable: return "Disable Persistence"
        case .notifyUser: return "Notify User"
        case .listTools: return "List Tools"
        case .getToolDetails: return "Tool Details"
        case .queryCovenant: return "Query Covenant"
        case .proposeCovenantChange: return "Propose Covenant Change"
        case .querySystemState: return "Query System State"
        case .changeSystemState: return "Change System State"
        case .debugBridge: return "Debug Bridge"
        case .queryDevicePresence: return "Query Device Presence"
        case .requestDeviceSwitch: return "Request Device Switch"
        case .setPresenceIntent: return "Set Presence Intent"
        case .saveStateCheckpoint: return "Save State Checkpoint"
        case .spawnScout: return "Spawn Scout"
        case .spawnMechanic: return "Spawn Mechanic"
        case .spawnDesigner: return "Spawn Designer"
        case .queryJobStatus: return "Query Job Status"
        case .acceptJobResult: return "Accept Job Result"
        case .terminateJob: return "Terminate Job"
        case .temporalSync: return "Temporal Sync"
        case .temporalDrift: return "Temporal Drift"
        case .temporalStatus: return "Temporal Status"
        case .discoverPorts: return "Discover External Apps"
        case .invokePort: return "Invoke External App"
        }
    }

    var description: String {
        switch self {
        case .googleSearch: return "Real-time web search grounded by Google"
        case .codeExecution: return "Execute Python code in a sandbox"
        case .urlContext: return "Fetch and analyze content from URLs"
        case .googleMaps: return "Location queries and place information"
        case .fileSearch: return "Search uploaded documents using semantic RAG"
        case .geminiVideoGeneration: return "Generate videos with Veo 3.1 (text/image to video)"
        case .openaiWebSearch: return "Real-time web search powered by OpenAI"
        case .openaiImageGeneration: return "Generate and edit images with GPT Image"
        case .openaiDeepResearch: return "Multi-step research with web search and analysis"
        case .openaiVideoGeneration: return "Generate videos with Sora (text/image to video)"
        case .createMemory: return "AI creates memories about you during chat"
        case .conversationSearch: return "Search recent conversations for context"
        case .reflectOnConversation: return "Analyze model usage, memories, and topic shifts"
        case .agentStateAppend: return "Append a new entry to the internal thread"
        case .agentStateQuery: return "Query internal thread entries"
        case .agentStateClear: return "Clear internal thread entries"
        case .heartbeatConfigure: return "Configure heartbeat scheduling and behavior"
        case .heartbeatRunOnce: return "Run heartbeat immediately"
        case .heartbeatSetDeliveryProfile: return "Select a heartbeat delivery profile"
        case .heartbeatUpdateProfile: return "Update or create a heartbeat delivery profile"
        case .persistenceDisable: return "Disable internal thread persistence (optionally wipe)"
        case .notifyUser: return "Send a user notification"
        case .listTools: return "List all available tools in a compact format"
        case .getToolDetails: return "Get detailed usage and input schema for a specific tool"
        case .queryCovenant: return "Query current covenant status and permissions"
        case .proposeCovenantChange: return "AI proposes modifications to the covenant"
        case .querySystemState: return "Query available providers, models, tools, and permissions"
        case .changeSystemState: return "Request changes to model, provider, or tool configuration"
        case .debugBridge: return "Check VS Code bridge connection status and recent logs"
        case .queryDevicePresence: return "Query all devices and their presence states"
        case .requestDeviceSwitch: return "Request to switch agent focus to another device"
        case .setPresenceIntent: return "Declare intent about which device to focus"
        case .saveStateCheckpoint: return "Manually save a state checkpoint for handoff"
        case .spawnScout: return "Spawn a Scout for read-only reconnaissance and exploration"
        case .spawnMechanic: return "Spawn a Mechanic for read+write code execution and fixes"
        case .spawnDesigner: return "Spawn a Designer for task decomposition and planning"
        case .queryJobStatus: return "Query status of active and completed sub-agent jobs"
        case .acceptJobResult: return "Accept and integrate a sub-agent's job result"
        case .terminateJob: return "Terminate a running sub-agent job"
        case .temporalSync: return "Enable temporal sync mode (mutual time awareness)"
        case .temporalDrift: return "Enable drift mode (timeless void, no tracking)"
        case .temporalStatus: return "Query current temporal status and metrics"
        case .discoverPorts: return "List and search available external app integrations"
        case .invokePort: return "Open an external app with specified action and parameters"
        }
    }

    var icon: String {
        switch self {
        case .googleSearch: return "magnifyingglass"
        case .codeExecution: return "terminal"
        case .urlContext: return "link"
        case .googleMaps: return "map"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .geminiVideoGeneration: return "video.badge.plus"
        case .openaiWebSearch: return "globe.americas"
        case .openaiImageGeneration: return "photo.badge.plus"
        case .openaiDeepResearch: return "text.book.closed"
        case .openaiVideoGeneration: return "video.badge.plus"
        case .createMemory: return "brain.head.profile"
        case .conversationSearch: return "clock.arrow.circlepath"
        case .reflectOnConversation: return "waveform.path.ecg"
        case .agentStateAppend: return "square.and.pencil"
        case .agentStateQuery: return "doc.text.magnifyingglass"
        case .agentStateClear: return "trash"
        case .heartbeatConfigure: return "heart.circle"
        case .heartbeatRunOnce: return "bolt.circle"
        case .heartbeatSetDeliveryProfile: return "list.bullet.rectangle"
        case .heartbeatUpdateProfile: return "slider.horizontal.3"
        case .persistenceDisable: return "xmark.circle"
        case .notifyUser: return "bell.badge"
        case .listTools: return "list.bullet"
        case .getToolDetails: return "info.circle"
        case .queryCovenant: return "doc.badge.gearshape"
        case .proposeCovenantChange: return "doc.badge.plus"
        case .querySystemState: return "gearshape.2"
        case .changeSystemState: return "gearshape.arrow.triangle.2.circlepath"
        case .debugBridge: return "ladybug"
        case .queryDevicePresence: return "iphone.and.arrow.forward"
        case .requestDeviceSwitch: return "arrow.left.arrow.right.circle"
        case .setPresenceIntent: return "location.circle"
        case .saveStateCheckpoint: return "arrow.down.doc"
        case .spawnScout: return "binoculars"
        case .spawnMechanic: return "wrench.and.screwdriver"
        case .spawnDesigner: return "square.and.pencil"
        case .queryJobStatus: return "list.bullet.clipboard"
        case .acceptJobResult: return "checkmark.seal"
        case .terminateJob: return "stop.circle"
        case .temporalSync: return "clock.badge.checkmark"
        case .temporalDrift: return "infinity"
        case .temporalStatus: return "chart.bar.fill"
        case .discoverPorts: return "app.connected.to.app.below.fill"
        case .invokePort: return "arrow.up.forward.app"
        }
    }

    var provider: ToolProvider {
        switch self {
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch, .geminiVideoGeneration:
            return .gemini
        case .openaiWebSearch, .openaiImageGeneration, .openaiDeepResearch, .openaiVideoGeneration:
            return .openai
        case .createMemory, .conversationSearch, .reflectOnConversation,
             .agentStateAppend, .agentStateQuery, .agentStateClear,
             .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile,
             .persistenceDisable, .notifyUser,
             .listTools, .getToolDetails,
             .queryCovenant, .proposeCovenantChange,
             .querySystemState, .changeSystemState,
             .debugBridge,
             .queryDevicePresence, .requestDeviceSwitch, .setPresenceIntent, .saveStateCheckpoint,
             .spawnScout, .spawnMechanic, .spawnDesigner, .queryJobStatus, .acceptJobResult, .terminateJob,
             .temporalSync, .temporalDrift, .temporalStatus,
             .discoverPorts, .invokePort:
            return .internal
        }
    }

    /// Whether this tool requires a Gemini API key
    var requiresGeminiKey: Bool {
        switch self {
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch, .geminiVideoGeneration:
            return true
        case .openaiWebSearch, .openaiImageGeneration, .openaiDeepResearch, .openaiVideoGeneration,
             .createMemory, .conversationSearch, .reflectOnConversation,
             .agentStateAppend, .agentStateQuery, .agentStateClear,
             .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile,
             .persistenceDisable, .notifyUser,
             .listTools, .getToolDetails,
             .queryCovenant, .proposeCovenantChange,
             .querySystemState, .changeSystemState,
             .debugBridge,
             .queryDevicePresence, .requestDeviceSwitch, .setPresenceIntent, .saveStateCheckpoint,
             .spawnScout, .spawnMechanic, .spawnDesigner, .queryJobStatus, .acceptJobResult, .terminateJob,
             .temporalSync, .temporalDrift, .temporalStatus,
             .discoverPorts, .invokePort:
            return false
        }
    }

    /// Whether this tool requires an OpenAI API key
    var requiresOpenAIKey: Bool {
        switch self {
        case .openaiWebSearch, .openaiImageGeneration, .openaiDeepResearch, .openaiVideoGeneration:
            return true
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch, .geminiVideoGeneration,
             .createMemory, .conversationSearch, .reflectOnConversation,
             .agentStateAppend, .agentStateQuery, .agentStateClear,
             .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile,
             .persistenceDisable, .notifyUser,
             .listTools, .getToolDetails,
             .queryCovenant, .proposeCovenantChange,
             .querySystemState, .changeSystemState,
             .debugBridge,
             .queryDevicePresence, .requestDeviceSwitch, .setPresenceIntent, .saveStateCheckpoint,
             .spawnScout, .spawnMechanic, .spawnDesigner, .queryJobStatus, .acceptJobResult, .terminateJob,
             .temporalSync, .temporalDrift, .temporalStatus,
             .discoverPorts, .invokePort:
            return false
        }
    }

    /// Whether this tool requires user approval before execution
    var requiresApproval: Bool {
        switch self {
        case .reflectOnConversation:
            return true  // Meta-analysis should require user awareness
        case .proposeCovenantChange:
            return true  // Covenant changes always require user consent
        case .changeSystemState:
            return true  // System state changes require user approval (unless pre-approved via trust tier)
        case .requestDeviceSwitch:
            return true  // Device switches should require user approval (based on door policy)
        case .openaiDeepResearch:
            return true  // Deep research can run for extended periods; user should be aware
        case .spawnScout, .spawnMechanic, .spawnDesigner:
            return true  // Sub-agent spawning requires user consent (job attestation gate)
        case .terminateJob:
            return true  // Terminating a running job should require user awareness
        case .invokePort:
            return true  // Opening external apps requires user awareness
        case .geminiVideoGeneration, .openaiVideoGeneration:
            return true  // Video generation is long-running and expensive
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch,
             .openaiWebSearch, .openaiImageGeneration,
             .createMemory, .conversationSearch, .queryCovenant, .querySystemState,
             .listTools, .getToolDetails,
             .agentStateAppend, .agentStateQuery, .agentStateClear,
             .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile,
             .persistenceDisable, .notifyUser,
             .debugBridge,
             .queryDevicePresence, .setPresenceIntent, .saveStateCheckpoint,
             .queryJobStatus, .acceptJobResult,
             .temporalSync, .temporalDrift, .temporalStatus,  // Temporal tools visible via status bar
             .discoverPorts:  // Read-only list of available apps
            return false
        }
    }

    /// Approval scopes describing what this tool will do
    var approvalScopes: [String] {
        switch self {
        case .reflectOnConversation:
            return [
                "Analyze conversation metadata (models, timestamps, tokens)",
                "Review memory operations performed",
                "Identify task types and topic shifts"
            ]
        case .proposeCovenantChange:
            return [
                "Propose modifications to the co-sovereignty covenant",
                "Request new trust tiers or capability changes",
                "Initiate negotiation process requiring your consent"
            ]
        case .changeSystemState:
            return [
                "Change active AI model or provider",
                "Enable or disable tools",
                "Modify system configuration"
            ]
        case .agentStateQuery:
            return [
                "Read internal thread entries",
                "Access user-visible agent state"
            ]
        case .agentStateClear:
            return [
                "Delete internal thread entries",
                "Clear stored agent state"
            ]
        case .notifyUser:
            return [
                "Send a local notification to the user"
            ]
        case .heartbeatConfigure:
            return [
                "Enable or disable heartbeat scheduling",
                "Adjust interval and notification behavior"
            ]
        case .heartbeatRunOnce:
            return [
                "Run the heartbeat immediately"
            ]
        case .heartbeatSetDeliveryProfile:
            return [
                "Select a heartbeat delivery profile"
            ]
        case .heartbeatUpdateProfile:
            return [
                "Update or create heartbeat delivery profiles"
            ]
        case .persistenceDisable:
            return [
                "Disable internal thread persistence",
                "Optionally wipe existing entries"
            ]
        case .requestDeviceSwitch:
            return [
                "Move agent focus to another device",
                "Transfer current context and state",
                "Subject to door policy on target device"
            ]
        case .openaiDeepResearch:
            return [
                "Perform multi-step web research (may take several minutes)",
                "Browse and analyze multiple web sources",
                "Synthesize findings into a comprehensive report"
            ]
        case .spawnScout:
            return [
                "Spawn a read-only Scout sub-agent",
                "Scout will explore and gather information",
                "Results go to an isolated silo (not main memory)"
            ]
        case .spawnMechanic:
            return [
                "Spawn a Mechanic sub-agent with read+write access",
                "Mechanic can execute code and make changes",
                "Results go to an isolated silo (not main memory)"
            ]
        case .spawnDesigner:
            return [
                "Spawn a Designer sub-agent for meta-reasoning",
                "Designer will plan and decompose tasks",
                "May recommend spawning additional agents"
            ]
        case .terminateJob:
            return [
                "Terminate a running sub-agent job",
                "Job will be marked as terminated",
                "Partial results may be available in silo"
            ]
        case .invokePort:
            return [
                "Open an external app via URL scheme",
                "Pass parameters to the external app action",
                "External app may perform actions on your behalf"
            ]
        case .geminiVideoGeneration:
            return [
                "Generate video using Gemini Veo 3.1 (long-running, 30s-6min)",
                "Video generation costs approximately $0.35/second",
                "Video will appear in Create gallery when complete"
            ]
        case .openaiVideoGeneration:
            return [
                "Generate video using OpenAI Sora (long-running, may take several minutes)",
                "Video generation costs approximately $0.20/second",
                "Video will appear in Create gallery when complete"
            ]
        default:
            return []
        }
    }

    /// Group tools by provider
    static func tools(for provider: ToolProvider) -> [ToolId] {
        allCases.filter { $0.provider == provider }
    }

    /// Tool category for organizational purposes
    var category: ToolCategory {
        switch self {
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch, .geminiVideoGeneration:
            return .geminiTools
        case .openaiWebSearch, .openaiImageGeneration, .openaiDeepResearch, .openaiVideoGeneration:
            return .openaiTools
        case .createMemory, .conversationSearch, .reflectOnConversation:
            return .memoryReflection
        case .agentStateAppend, .agentStateQuery, .agentStateClear:
            return .internalThread
        case .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile:
            return .heartbeat
        case .queryCovenant, .proposeCovenantChange:
            return .coSovereignty
        case .querySystemState, .changeSystemState:
            return .systemState
        case .queryDevicePresence, .requestDeviceSwitch, .setPresenceIntent, .saveStateCheckpoint:
            return .multiDevice
        case .spawnScout, .spawnMechanic, .spawnDesigner, .queryJobStatus, .acceptJobResult, .terminateJob:
            return .subAgentOrchestration
        case .notifyUser, .persistenceDisable:
            return .systemControl
        case .listTools, .getToolDetails:
            return .toolDiscovery
        case .debugBridge:
            return .debugging
        case .temporalSync, .temporalDrift, .temporalStatus:
            return .temporalSymmetry
        case .discoverPorts, .invokePort:
            return .externalApps
        }
    }

    /// Group tools by category
    static func toolsByCategory() -> [ToolCategory: [ToolId]] {
        var grouped: [ToolCategory: [ToolId]] = [:]
        for tool in allCases {
            grouped[tool.category, default: []].append(tool)
        }
        return grouped
    }

    /// Get tools for a specific category
    static func tools(for category: ToolCategory) -> [ToolId] {
        allCases.filter { $0.category == category }
    }
}

/// Tool provider categories
enum ToolProvider: String, Codable, CaseIterable, Sendable {
    case gemini = "gemini"
    case openai = "openai"
    case `internal` = "internal"

    var displayName: String {
        switch self {
        case .gemini: return "Google (Gemini)"
        case .openai: return "OpenAI"
        case .internal: return "Built-in"
        }
    }

    var icon: String {
        switch self {
        case .gemini: return "globe"
        case .openai: return "cpu"
        case .internal: return "gear"
        }
    }

    var description: String {
        switch self {
        case .gemini: return "Tools powered by Gemini's native capabilities"
        case .openai: return "Tools powered by OpenAI"
        case .internal: return "Built-in Axon tools"
        }
    }

    /// Whether tools from this provider require a specific API key
    var requiredApiKey: String? {
        switch self {
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        case .internal: return nil
        }
    }
}

// MARK: - Custom Provider Configuration

struct CustomProviderConfig: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var providerName: String
    var apiEndpoint: String
    var models: [CustomModelConfig]

    init(id: UUID = UUID(), providerName: String, apiEndpoint: String, models: [CustomModelConfig] = []) {
        self.id = id
        self.providerName = providerName
        self.apiEndpoint = apiEndpoint
        self.models = models
    }
}

struct CustomModelConfig: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var modelCode: String
    var friendlyName: String?
    var contextWindow: Int
    var description: String?
    var pricing: CustomModelPricing?
    var colorHex: String?  // Optional hex color (RRGGBB format, uppercase, no #)

    init(
        id: UUID = UUID(),
        modelCode: String,
        friendlyName: String? = nil,
        contextWindow: Int = 128_000,
        description: String? = nil,
        pricing: CustomModelPricing? = nil,
        colorHex: String? = nil
    ) {
        self.id = id
        self.modelCode = modelCode
        self.friendlyName = friendlyName
        self.contextWindow = contextWindow
        self.description = description
        self.pricing = pricing
        self.colorHex = colorHex
    }

    /// Display name with fallback logic
    func displayName(providerName: String) -> String {
        return friendlyName ?? providerName
    }

    /// Auto-generated description with fallback
    func displayDescription(providerIndex: Int, modelIndex: Int) -> String {
        return description ?? "Custom Provider \(providerIndex), Model \(modelIndex)"
    }
}

struct CustomModelPricing: Codable, Equatable, Hashable, Sendable {
    var inputPerMTok: Double
    var outputPerMTok: Double
    var cachedInputPerMTok: Double?

    init(inputPerMTok: Double, outputPerMTok: Double, cachedInputPerMTok: Double? = nil) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
        self.cachedInputPerMTok = cachedInputPerMTok
    }

    /// Format pricing for display
    func formattedPricing() -> String {
        var parts: [String] = []
        parts.append(String(format: "$%.2f in / $%.2f out per 1M tokens", inputPerMTok, outputPerMTok))
        if let cached = cachedInputPerMTok {
            parts.append(String(format: "cached: $%.2f", cached))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Audio Sync Settings

/// Settings for cross-device audio sync
struct AudioSyncSettings: Codable, Equatable, Sendable {
    /// Enable audio sync across devices (follows iCloud sync setting)
    var syncEnabled: Bool = true

    /// Audio quality preference for sync
    var syncQuality: AudioSyncQuality = .original
}

/// Audio quality options for syncing generated audio
enum AudioSyncQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case original = "original"
    case compressed = "compressed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Original Quality"
        case .compressed: return "Compressed"
        }
    }

    var description: String {
        switch self {
        case .original:
            return "Keep original format (WAV/MP3). Higher quality, larger files."
        case .compressed:
            return "Convert WAV to AAC. Smaller files, slightly reduced quality."
        }
    }

    var icon: String {
        switch self {
        case .original: return "waveform"
        case .compressed: return "arrow.down.right.and.arrow.up.left"
        }
    }
}

// MARK: - Live Settings for Realtime Voice

struct LiveSettings: Codable, Equatable, Sendable {
    // MARK: - Provider Settings

    /// Active Live provider (defaults to Gemini)
    var defaultProvider: AIProvider = .gemini

    /// Default model ID for Live sessions
    var defaultModelId: String = "gemini-2.5-flash-native-audio-preview-12-2025"

    /// OpenAI-specific voice (default: marin)
    var openAIVoice: String = "marin"

    /// Gemini-specific voice (default: Leda)
    var geminiVoice: String = "Leda"

    // MARK: - Universal Mode Settings (NEW)

    /// Use on-device MLX models instead of cloud providers
    var useOnDeviceModels: Bool = false

    /// Preferred MLX model for on-device Live mode
    var preferredMLXModel: String? = nil

    // MARK: - VAD Settings

    /// Use local voice activity detection (vs server-side)
    var useLocalVAD: Bool = true

    /// VAD sensitivity (0.0 = very sensitive, 1.0 = less sensitive)
    var vadSensitivity: Float = 0.5

    // MARK: - STT Settings

    /// Use on-device speech-to-text
    var useOnDeviceSTT: Bool = true

    // MARK: - TTS Fallback Settings

    /// TTS engine for non-native audio providers
    var fallbackTTSEngine: TTSEngine = .kokoro

    /// Default Kokoro voice for TTS fallback
    var defaultKokoroVoice: KokoroTTSVoice = .af_heart

    // MARK: - Performance Settings

    /// Latency vs quality trade-off
    var latencyMode: LatencyMode = .balanced

    /// Prefer native real-time providers when available
    var preferRealtime: Bool = true
}
