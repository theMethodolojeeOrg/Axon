# Settings Conversion Guide: Web to iOS/SwiftUI

A comprehensive guide for converting all settings functionality from the NeurXAxonChat web app to iOS/SwiftUI. This document covers the 5 main settings tabs, their components, data persistence, and implementation patterns.

---

## Table of Contents

1. [Settings Architecture Overview](#settings-architecture-overview)
2. [Data Models & Types](#data-models--types)
3. [Tab 1: General Settings](#tab-1-general-settings)
4. [Tab 2: Account Settings](#tab-2-account-settings)
5. [Tab 3: Memory Settings](#tab-3-memory-settings)
6. [Tab 4: API Keys Settings](#tab-4-api-keys-settings)
7. [Tab 5: Text-to-Speech Settings](#tab-5-text-to-speech-settings)
8. [Super Admin Settings](#super-admin-settings)
9. [Settings Persistence](#settings-persistence)
10. [Settings Service Implementation](#settings-service-implementation)
11. [Integration with App](#integration-with-app)
12. [Migration & Backup](#migration--backup)

---

## Settings Architecture Overview

### Web App Structure

The web app organizes settings across multiple layers:

```
SettingsModal (UI Container)
├── 5 Main Tabs
│   ├── General
│   ├── Account
│   ├── Memory
│   ├── API Keys
│   └── TTS (Text-to-Speech)
├── SettingsContext (State Management)
├── useSettings Hook (Local Storage)
├── useFirestoreSettings Hook (Cloud Sync)
└── Storage Services
    ├── settingsStorage (Browser localStorage)
    └── firestoreSettingsStorage (Firestore + Encryption)
```

### iOS/SwiftUI Structure

Recommended architecture:

```
SettingsView (Tab Container)
├── 5 Settings Tabs (NavigationStack or TabView)
│   ├── GeneralSettingsView
│   ├── AccountSettingsView
│   ├── MemorySettingsView
│   ├── APIKeysSettingsView
│   └── TTSSettingsView
├── SettingsViewModel (@MainActor)
├── SettingsService (Business Logic)
└── Persistence
    ├── UserDefaults (Local Preferences)
    └── Firestore (Cloud Sync + Encryption)
```

---

## Data Models & Types

### 1. Core Settings Model

**Models/Settings.swift**:

```swift
import Foundation

// MARK: - Main Settings Container

struct AppSettings: Codable, Equatable {
    // General
    var theme: Theme = .dark
    var defaultProvider: AIProvider = .anthropic
    var defaultModel: String = "claude-4.5-sonnet"
    var showArtifactsByDefault: Bool = true
    var enableKeyboardShortcuts: Bool = true

    // Account
    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""

    // Memory
    var memoryEnabled: Bool = true
    var memoryAutoInject: Bool = true
    var memorySidePanelEnabled: Bool = true
    var memoryConfidenceThreshold: Double = 0.3  // 0-1.0
    var maxMemoriesPerRequest: Int = 50  // 5-50
    var memoryAnalyticsEnabled: Bool = true

    // API Keys (encrypted on Firestore)
    var apiKeys: APIKeysSettings = APIKeysSettings()

    // Text-to-Speech
    var ttsSettings: TTSSettings = TTSSettings()

    // Super Admin
    var superAdminSettings: SuperAdminSettings?

    // Metadata
    var version: Int = 1
    var lastUpdated: Date = Date()
    var lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case theme, defaultProvider, defaultModel, showArtifactsByDefault, enableKeyboardShortcuts
        case firstName, lastName, email
        case memoryEnabled, memoryAutoInject, memorySidePanelEnabled
        case memoryConfidenceThreshold, maxMemoriesPerRequest, memoryAnalyticsEnabled
        case apiKeys, ttsSettings, superAdminSettings, version, lastUpdated, lastSyncedAt
    }
}

// MARK: - Theme

enum Theme: String, Codable, CaseIterable {
    case dark = "dark"
    case light = "light"
    case auto = "auto"  // Follows system preference

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .auto: return "Auto (System)"
        }
    }
}

// MARK: - AI Providers

enum AIProvider: String, Codable, CaseIterable {
    case anthropic = "anthropic"      // Claude
    case openai = "openai"            // GPT
    case gemini = "gemini"            // Google Gemini

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI (GPT)"
        case .gemini: return "Google Gemini"
        }
    }

    var availableModels: [AIModel] {
        switch self {
        case .anthropic:
            return AnthropicModels.allCases.map { $0.toAIModel() }
        case .openai:
            return OpenAIModels.allCases.map { $0.toAIModel() }
        case .gemini:
            return GeminiModels.allCases.map { $0.toAIModel() }
        }
    }
}

// MARK: - AI Models

struct AIModel: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let provider: AIProvider
    let contextWindow: Int
    let description: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AIModel, rhs: AIModel) -> Bool {
        lhs.id == rhs.id
    }
}

enum AnthropicModels: String, CaseIterable {
    case sonnet45 = "claude-4.5-sonnet"
    case haiku45 = "claude-4.5-haiku"
    case opus41 = "claude-4.1-opus"
    case opus3 = "claude-3-opus"

    func toAIModel() -> AIModel {
        switch self {
        case .sonnet45:
            return AIModel(
                id: self.rawValue,
                name: "Claude 4.5 Sonnet",
                provider: .anthropic,
                contextWindow: 200_000,
                description: "Recommended. Best balance of speed and intelligence"
            )
        case .haiku45:
            return AIModel(
                id: self.rawValue,
                name: "Claude 4.5 Haiku",
                provider: .anthropic,
                contextWindow: 200_000,
                description: "Fastest, lightest. Great for quick tasks"
            )
        case .opus41:
            return AIModel(
                id: self.rawValue,
                name: "Claude 4.1 Opus",
                provider: .anthropic,
                contextWindow: 200_000,
                description: "Most capable. Best for complex reasoning"
            )
        case .opus3:
            return AIModel(
                id: self.rawValue,
                name: "Claude 3 Opus",
                provider: .anthropic,
                contextWindow: 200_000,
                description: "Legacy model"
            )
        }
    }
}

enum OpenAIModels: String, CaseIterable {
    case gpt5 = "gpt-5"
    case gpt5mini = "gpt-5-mini"
    case gpt5nano = "gpt-5-nano"
    case gpt4turbo = "gpt-4-turbo"

    func toAIModel() -> AIModel {
        switch self {
        case .gpt5:
            return AIModel(
                id: self.rawValue,
                name: "GPT-5",
                provider: .openai,
                contextWindow: 128_000,
                description: "Most capable OpenAI model"
            )
        case .gpt5mini:
            return AIModel(
                id: self.rawValue,
                name: "GPT-5 Mini",
                provider: .openai,
                contextWindow: 128_000,
                description: "Smaller, faster version of GPT-5"
            )
        case .gpt5nano:
            return AIModel(
                id: self.rawValue,
                name: "GPT-5 Nano",
                provider: .openai,
                contextWindow: 128_000,
                description: "Ultra-lightweight model"
            )
        case .gpt4turbo:
            return AIModel(
                id: self.rawValue,
                name: "GPT-4 Turbo",
                provider: .openai,
                contextWindow: 128_000,
                description: "Previous generation model"
            )
        }
    }
}

enum GeminiModels: String, CaseIterable {
    case gemini25pro = "gemini-2.5-pro"
    case gemini25flash = "gemini-2.5-flash"
    case gemini25flashlite = "gemini-2.5-flash-lite"
    case gemini2pro = "gemini-2-pro"

    func toAIModel() -> AIModel {
        switch self {
        case .gemini25pro:
            return AIModel(
                id: self.rawValue,
                name: "Gemini 2.5 Pro",
                provider: .gemini,
                contextWindow: 1_000_000,
                description: "Most capable Gemini model"
            )
        case .gemini25flash:
            return AIModel(
                id: self.rawValue,
                name: "Gemini 2.5 Flash",
                provider: .gemini,
                contextWindow: 1_000_000,
                description: "Fast, efficient model"
            )
        case .gemini25flashlite:
            return AIModel(
                id: self.rawValue,
                name: "Gemini 2.5 Flash Lite",
                provider: .gemini,
                contextWindow: 1_000_000,
                description: "Ultra-lightweight model"
            )
        case .gemini2pro:
            return AIModel(
                id: self.rawValue,
                name: "Gemini 2 Pro",
                provider: .gemini,
                contextWindow: 1_000_000,
                description: "Previous generation model"
            )
        }
    }
}

// MARK: - API Keys Settings

struct APIKeysSettings: Codable, Equatable {
    var openaiKey: String?
    var anthropicKey: String?
    var geminiKey: String?
    var elevenLabsKey: String?

    // Computed properties to check if configured
    var isOpenaiConfigured: Bool { !openaiKey.isNilOrEmpty }
    var isAnthropicConfigured: Bool { !anthropicKey.isNilOrEmpty }
    var isGeminiConfigured: Bool { !geminiKey.isNilOrEmpty }
    var isElevenLabsConfigured: Bool { !elevenLabsKey.isNilOrEmpty }

    mutating func clearKey(for provider: APIProvider) {
        switch provider {
        case .openai: openaiKey = nil
        case .anthropic: anthropicKey = nil
        case .gemini: geminiKey = nil
        case .elevenlabs: elevenLabsKey = nil
        }
    }

    func getKey(for provider: APIProvider) -> String? {
        switch provider {
        case .openai: return openaiKey
        case .anthropic: return anthropicKey
        case .gemini: return geminiKey
        case .elevenlabs: return elevenLabsKey
        }
    }
}

enum APIProvider: String, CaseIterable {
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case elevenlabs = "elevenlabs"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .elevenlabs: return "ElevenLabs"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .gemini: return "AIza..."
        case .elevenlabs: return "sk_..."
        }
    }

    var infoURL: URL? {
        switch self {
        case .openai: return URL(string: "https://platform.openai.com/account/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/account/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .elevenlabs: return URL(string: "https://elevenlabs.io/app/settings/api-keys")
        }
    }
}

// MARK: - TTS Settings

struct TTSSettings: Codable, Equatable {
    var elevenLabsApiKey: String?
    var userVoiceId: String = "MF3mGyEYCl7XYWbV9V6O"  // Default female voice
    var assistantVoiceId: String = "EXAVITQu4vr4xnSDxMaL"  // Default male voice
    var model: TTSModel = .turboV25
    var outputFormat: TTSOutputFormat = .mp3128
    var voiceSettings: VoiceSettings = VoiceSettings()

    var isConfigured: Bool { !elevenLabsApiKey.isNilOrEmpty }
}

enum TTSModel: String, Codable, CaseIterable {
    case turboV25 = "eleven_turbo_v2_5"
    case multilingualV2 = "eleven_multilingual_v2"
    case flashV25 = "eleven_flash_v2_5"

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

enum TTSOutputFormat: String, Codable, CaseIterable {
    case mp3128 = "mp3_44100_128"
    case mp364 = "mp3_44100_64"
    case mp332 = "mp3_22050_32"

    var displayName: String {
        switch self {
        case .mp3128: return "MP3 128kbps"
        case .mp364: return "MP3 64kbps"
        case .mp332: return "MP3 32kbps"
        }
    }

    var description: String {
        switch self {
        case .mp3128: return "Highest quality, largest file size"
        case .mp364: return "Balanced quality and file size"
        case .mp332: return "Lowest quality, smallest file size"
        }
    }
}

struct VoiceSettings: Codable, Equatable {
    var stability: Double = 0.5        // 0.0-1.0
    var similarityBoost: Double = 0.75 // 0.0-1.0
    var style: Double = 0.0            // 0.0-1.0
    var useSpeakerBoost: Bool = false

    var stabilityPercent: Int {
        Int(stability * 100)
    }

    var similarityBoostPercent: Int {
        Int(similarityBoost * 100)
    }

    var stylePercent: Int {
        Int(style * 100)
    }
}

struct ElevenLabsVoice: Codable, Identifiable {
    let voiceId: String
    let name: String
    let category: String
    let labels: [String: String]
    let previewUrl: String?
    let availableForTiers: [String]

    var id: String { voiceId }

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name, category, labels
        case previewUrl = "preview_url"
        case availableForTiers = "available_for_tiers"
    }
}

// MARK: - Memory Settings

struct MemoryConfig: Codable, Equatable {
    var enabled: Bool = true
    var autoInject: Bool = true
    var sidePanelEnabled: Bool = true
    var confidenceThreshold: Double = 0.3  // 0-1.0
    var maxMemoriesPerRequest: Int = 50    // 5-50
    var analyticsEnabled: Bool = true

    var confidencePercent: Int {
        Int(confidenceThreshold * 100)
    }
}

// MARK: - Super Admin Settings

struct SuperAdminSettings: Codable, Equatable {
    var julesAPIGitHubRepo: String?
    var julesAPIDefaultBranch: String = "main"
    var julesAPIAutoApprovePlans: Bool = false
    var julesAPIRateLimitPerDay: Int = 100
    var auditLogRetentionDays: Int = 90
    var enableJulesAPI: Bool = false

    // API Status (real-time, fetched from backend)
    var julesAPICallsUsed: Int = 0
    var julesAPICallsRemaining: Int = 100
    var julesAPIResetTime: Date?
}

// MARK: - Helper Extensions

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
```

---

## Tab 1: General Settings

### Features

- **Theme Selection**: Dark, Light, Auto (system)
- **AI Provider Selection**: Anthropic (Claude), OpenAI, Google Gemini
- **Model Selection**: Dynamic dropdown based on provider
- **Artifacts Display**: Toggle to show/hide artifacts by default
- **Keyboard Shortcuts**: Enable/disable keyboard shortcuts

### Implementation

**Views/Settings/GeneralSettingsView.swift**:

```swift
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.colorScheme) var systemColorScheme

    var body: some View {
        Form {
            // MARK: - Theme Section

            Section("Theme") {
                Picker("App Theme", selection: $viewModel.settings.theme) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .onChange(of: viewModel.settings.theme) { oldValue, newValue in
                    Task {
                        await viewModel.updateSetting(\.theme, newValue)
                    }
                }

                if viewModel.settings.theme == .auto {
                    HStack {
                        Label("System Theme", systemImage: "gear")
                        Spacer()
                        Text(systemColorScheme == .dark ? "Dark" : "Light")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - AI Provider Section

            Section("AI Model") {
                Picker("Provider", selection: $viewModel.settings.defaultProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: viewModel.settings.defaultProvider) { oldValue, newValue in
                    Task {
                        // Reset to first model of new provider
                        if let firstModel = newValue.availableModels.first {
                            await viewModel.updateSetting(\.defaultModel, firstModel.id)
                        }
                        await viewModel.updateSetting(\.defaultProvider, newValue)
                    }
                }

                Picker("Model", selection: $viewModel.settings.defaultModel) {
                    ForEach(
                        viewModel.settings.defaultProvider.availableModels,
                        id: \.id
                    ) { model in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name).tag(model.id)
                            Text(model.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onChange(of: viewModel.settings.defaultModel) { oldValue, newValue in
                    Task {
                        await viewModel.updateSetting(\.defaultModel, newValue)
                    }
                }

                HStack {
                    Label("Context Window", systemImage: "brain.head.profile")
                    Spacer()
                    if let currentModel = viewModel.currentModel {
                        Text(String(format: "%.0fK", Double(currentModel.contextWindow) / 1000))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - Display Options

            Section("Display") {
                Toggle("Show Artifacts by Default", isOn: $viewModel.settings.showArtifactsByDefault)
                    .onChange(of: viewModel.settings.showArtifactsByDefault) { oldValue, newValue in
                        Task {
                            await viewModel.updateSetting(\.showArtifactsByDefault, newValue)
                        }
                    }

                Toggle("Enable Keyboard Shortcuts", isOn: $viewModel.settings.enableKeyboardShortcuts)
                    .onChange(of: viewModel.settings.enableKeyboardShortcuts) { oldValue, newValue in
                        Task {
                            await viewModel.updateSetting(\.enableKeyboardShortcuts, newValue)
                        }
                    }
            }

            // MARK: - Status

            if let lastSyncedAt = viewModel.settings.lastSyncedAt {
                Section {
                    HStack {
                        Label("Last Synced", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text(lastSyncedAt.formatted(date: .omitted, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let error = viewModel.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("General")
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView(viewModel: SettingsViewModel())
    }
}
```

---

## Tab 2: Account Settings

### Features

- **Profile Management**: First name, last name display
- **Email Display**: Read-only email from Firebase Auth
- **Password Reset**: Trigger password reset email
- **Encryption Key Refresh**: Rotate encryption key
- **Sign Out**: Clear local data and sign out

### Implementation

**Views/Settings/AccountSettingsView.swift**:

```swift
import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var authService = AuthenticationService.shared
    @State private var showPasswordResetConfirmation = false
    @State private var showSignOutConfirmation = false
    @State private var passwordResetError: String?
    @State private var isRefreshingKey = false
    @State private var keyRefreshError: String?

    var body: some View {
        Form {
            // MARK: - Profile Section

            Section("Profile") {
                TextField("First Name", text: $viewModel.settings.firstName)
                    .onChange(of: viewModel.settings.firstName) { oldValue, newValue in
                        Task {
                            await viewModel.updateSetting(\.firstName, newValue)
                        }
                    }

                TextField("Last Name", text: $viewModel.settings.lastName)
                    .onChange(of: viewModel.settings.lastName) { oldValue, newValue in
                        Task {
                            await viewModel.updateSetting(\.lastName, newValue)
                        }
                    }

                if let user = authService.user {
                    HStack {
                        Label("Email", systemImage: "envelope.fill")
                        Spacer()
                        Text(user.email ?? "Unknown")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // MARK: - Security Section

            Section("Security") {
                Button(role: .none) {
                    showPasswordResetConfirmation = true
                } label: {
                    Label("Reset Password", systemImage: "key.fill")
                        .foregroundColor(.primary)
                }

                if let error = passwordResetError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            // MARK: - Encryption Section

            Section("Encryption") {
                Button(action: {
                    Task {
                        isRefreshingKey = true
                        keyRefreshError = nil

                        // Call refresh key endpoint
                        do {
                            let _: [String: Any] = try await APIClient.shared.post(
                                "/api/encryption/refresh",
                                body: ["userId": authService.user?.uid ?? ""]
                            )
                            viewModel.showSuccessMessage("Encryption key refreshed successfully")
                        } catch {
                            keyRefreshError = error.localizedDescription
                        }

                        isRefreshingKey = false
                    }
                }) {
                    if isRefreshingKey {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Refreshing Key...")
                        }
                    } else {
                        Label("Refresh Encryption Key", systemImage: "lock.rotation")
                    }
                }
                .disabled(isRefreshingKey)

                Text("Regenerates your data encryption key and re-encrypts all sensitive data")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let error = keyRefreshError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            // MARK: - Sign Out Section

            Section {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "arrowbottom.right.rectangle")
                }
            }
        }
        .navigationTitle("Account")
        .confirmationDialog(
            "Reset Password",
            isPresented: $showPasswordResetConfirmation,
            actions: {
                Button("Send Reset Email", role: .none) {
                    Task {
                        passwordResetError = nil

                        do {
                            try await authService.resetPassword(
                                email: authService.user?.email ?? ""
                            )
                            viewModel.showSuccessMessage("Password reset email sent")
                        } catch {
                            passwordResetError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("A password reset email will be sent to your email address.")
            }
        )
        .confirmationDialog(
            "Sign Out",
            isPresented: $showSignOutConfirmation,
            actions: {
                Button("Sign Out", role: .destructive) {
                    Task {
                        do {
                            try authService.signOut()
                        } catch {
                            passwordResetError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("You will be signed out of all devices. Local data will be cleared.")
            }
        )
    }
}

#Preview {
    NavigationStack {
        AccountSettingsView(viewModel: SettingsViewModel())
    }
}
```

---

## Tab 3: Memory Settings

### Features

- **Enable/Disable**: Toggle memory system on/off
- **Auto-Inject**: Automatically inject relevant memories into conversations
- **Side Panel**: Show/hide memory side panel in chat
- **Confidence Threshold**: Filter memories by confidence level (0-100%)
- **Max Memories**: Limit memories per request (5-50)
- **Analytics**: Enable/disable memory analytics

### Implementation

**Views/Settings/MemorySettingsView.swift**:

```swift
import SwiftUI

struct MemorySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showMemoryAnalytics = false

    var body: some View {
        Form {
            // MARK: - Memory System

            Section("Memory System") {
                Toggle("Enable Memory System", isOn: $viewModel.settings.memoryEnabled)
                    .onChange(of: viewModel.settings.memoryEnabled) { oldValue, newValue in
                        Task {
                            await viewModel.updateSetting(\.memoryEnabled, newValue)
                        }
                    }

                if viewModel.settings.memoryEnabled {
                    Toggle("Auto-Inject Memories", isOn: $viewModel.settings.memoryAutoInject)
                        .onChange(of: viewModel.settings.memoryAutoInject) { oldValue, newValue in
                            Task {
                                await viewModel.updateSetting(\.memoryAutoInject, newValue)
                            }
                        }

                    Text("Automatically retrieve and inject relevant memories into conversations")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Show Memory Side Panel", isOn: $viewModel.settings.memorySidePanelEnabled)
                        .onChange(of: viewModel.settings.memorySidePanelEnabled) { oldValue, newValue in
                            Task {
                                await viewModel.updateSetting(\.memorySidePanelEnabled, newValue)
                            }
                        }
                }
            }

            // MARK: - Memory Filtering

            if viewModel.settings.memoryEnabled {
                Section("Memory Filtering") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Confidence Threshold", systemImage: "target")
                            Spacer()
                            Text("\(Int(viewModel.settings.memoryConfidenceThreshold * 100))%")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }

                        Slider(
                            value: $viewModel.settings.memoryConfidenceThreshold,
                            in: 0...1,
                            step: 0.05
                        )
                        .onChange(of: viewModel.settings.memoryConfidenceThreshold) { oldValue, newValue in
                            Task {
                                await viewModel.updateSetting(\.memoryConfidenceThreshold, newValue)
                            }
                        }

                        Text("Only memories with confidence above this threshold are retrieved")
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                    }
                    .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Max Memories per Request", systemImage: "list.number")
                            Spacer()
                            Text("\(viewModel.settings.maxMemoriesPerRequest)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.maxMemoriesPerRequest) },
                                set: { viewModel.settings.maxMemoriesPerRequest = Int($0) }
                            ),
                            in: 5...50,
                            step: 1
                        )
                        .onChange(of: viewModel.settings.maxMemoriesPerRequest) { oldValue, newValue in
                            Task {
                                await viewModel.updateSetting(\.maxMemoriesPerRequest, newValue)
                            }
                        }

                        Text("Limit number of memories injected per conversation turn")
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Analytics

                Section("Analytics") {
                    Toggle("Memory Analytics", isOn: $viewModel.settings.memoryAnalyticsEnabled)
                        .onChange(of: viewModel.settings.memoryAnalyticsEnabled) { oldValue, newValue in
                            Task {
                                await viewModel.updateSetting(\.memoryAnalyticsEnabled, newValue)
                            }
                        }

                    if viewModel.settings.memoryAnalyticsEnabled {
                        NavigationLink(destination: MemoryAnalyticsView()) {
                            Label("View Analytics", systemImage: "chart.bar.xaxis")
                        }
                    }
                }
            }

            // MARK: - Info

            if !viewModel.settings.memoryEnabled {
                Section {
                    Label(
                        "Memory system is disabled. Enable to track and reuse conversation context.",
                        systemImage: "info.circle"
                    )
                    .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Memory")
    }
}

struct MemoryAnalyticsView: View {
    @State private var isLoading = false
    @State private var analytics: [String: Any]?

    var body: some View {
        Form {
            Section("Memory Analytics") {
                if isLoading {
                    ProgressView()
                } else if let analytics = analytics {
                    HStack {
                        Label("Total Memories", systemImage: "brain.head.profile")
                        Spacer()
                        Text("\(analytics["total"] ?? 0)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Average Confidence", systemImage: "target")
                        Spacer()
                        Text(String(format: "%.0f%%", (analytics["averageConfidence"] as? Double ?? 0) * 100))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Most Used Type", systemImage: "tag.fill")
                        Spacer()
                        Text(analytics["mostUsedType"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No analytics data available")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Memory Analytics")
        .task {
            isLoading = true
            // Fetch memory analytics from API
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        MemorySettingsView(viewModel: SettingsViewModel())
    }
}
```

---

## Tab 4: API Keys Settings

### Features

- **Provider Configuration**: OpenAI, Anthropic, Google Gemini, ElevenLabs
- **Key Management**: Add, edit, and clear API keys
- **Secure Storage**: Encrypted in Firestore
- **Visibility Toggle**: Show/hide key for security
- **Configuration Status**: Badge showing if key is configured
- **Help Links**: Direct links to get API keys

### Implementation

**Views/Settings/APIKeysSettingsView.swift**:

```swift
import SwiftUI

struct APIKeysSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedProvider: APIProvider? = nil
    @State private var editingKeyValue = ""
    @State private var showingKeyInput = false

    var body: some View {
        Form {
            Section("API Keys") {
                ForEach(APIProvider.allCases, id: \.self) { provider in
                    APIKeyRow(
                        provider: provider,
                        isConfigured: viewModel.isAPIKeyConfigured(provider),
                        onEdit: {
                            selectedProvider = provider
                            editingKeyValue = viewModel.getAPIKey(provider) ?? ""
                            showingKeyInput = true
                        },
                        onClear: {
                            Task {
                                await viewModel.clearAPIKey(provider)
                            }
                        },
                        onGetKey: {
                            if let url = provider.infoURL {
                                UIApplication.shared.open(url)
                            }
                        }
                    )
                }
            }

            Section {
                Text("API keys are encrypted and stored securely. Your keys are never shared or logged.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("API Keys")
        .sheet(isPresented: $showingKeyInput) {
            APIKeyInputSheet(
                provider: selectedProvider ?? .openai,
                keyValue: $editingKeyValue,
                onSave: {
                    if let provider = selectedProvider {
                        Task {
                            await viewModel.saveAPIKey(editingKeyValue, for: provider)
                            showingKeyInput = false
                        }
                    }
                },
                onCancel: {
                    showingKeyInput = false
                }
            )
        }
    }
}

struct APIKeyRow: View {
    let provider: APIProvider
    let isConfigured: Bool
    let onEdit: () -> Void
    let onClear: () -> Void
    let onGetKey: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.displayName)
                    .font(.headline)

                HStack(spacing: 8) {
                    if isConfigured {
                        Label("Configured", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Not Configured", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }

                if isConfigured {
                    Button(role: .destructive, action: onClear) {
                        Label("Clear", systemImage: "xmark.circle.fill")
                    }
                }

                Divider()

                Button(action: onGetKey) {
                    Label("Get API Key", systemImage: "link")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct APIKeyInputSheet: View {
    let provider: APIProvider
    @Binding var keyValue: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var isShowingKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section("\(provider.displayName) API Key") {
                    HStack {
                        if isShowingKey {
                            TextField("Paste your API key", text: $keyValue)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.monospaced(.body)())
                        } else {
                            SecureField("Paste your API key", text: $keyValue)
                                .font(.monospaced(.body)())
                        }

                        Button(action: { isShowingKey.toggle() }) {
                            Image(systemName: isShowingKey ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Expected format: \(provider.apiKeyPlaceholder)", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Link("Get API key from \(provider.displayName)", destination: provider.infoURL ?? URL(string: "https://example.com")!)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add \(provider.displayName) Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(keyValue.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        APIKeysSettingsView(viewModel: SettingsViewModel())
    }
}
```

---

## Tab 5: Text-to-Speech Settings

### Features

- **ElevenLabs API Key**: Configure TTS service
- **Model Selection**: Choose TTS model (Turbo v2.5, Multilingual v2, Flash v2.5)
- **Output Format**: Select audio quality (128kbps, 64kbps, 32kbps)
- **Voice Selection**: Choose voices for user and assistant messages
- **Voice Parameters**: Adjust stability, similarity boost, style, speaker boost
- **Voice Preview**: Listen to voice samples

### Implementation

**Views/Settings/TTSSettingsView.swift**:

```swift
import SwiftUI
import AVFoundation

struct TTSSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showAPIKeySheet = false
    @State private var showVoiceSelection = false
    @State private var selectedVoiceType: VoiceType = .user
    @State private var availableVoices: [ElevenLabsVoice] = []
    @State private var isLoadingVoices = false

    enum VoiceType {
        case user
        case assistant
    }

    var body: some View {
        Form {
            // MARK: - Configuration

            Section("Configuration") {
                if !viewModel.settings.ttsSettings.isConfigured {
                    Button(action: { showAPIKeySheet = true }) {
                        Label("Add ElevenLabs API Key", systemImage: "key.fill")
                            .foregroundColor(.blue)
                    }

                    Link(
                        "Get API Key from ElevenLabs",
                        destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!
                    )
                    .font(.caption)
                } else {
                    HStack {
                        Label("API Key", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text("Configured")
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive) {
                        Task {
                            await viewModel.clearTTSAPIKey()
                        }
                    } label: {
                        Label("Remove API Key", systemImage: "xmark.circle.fill")
                    }
                }
            }

            if viewModel.settings.ttsSettings.isConfigured {
                // MARK: - Model Selection

                Section("Model") {
                    Picker("TTS Model", selection: $viewModel.settings.ttsSettings.model) {
                        ForEach(TTSModel.allCases, id: \.self) { model in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName).tag(model)
                                Text(model.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onChange(of: viewModel.settings.ttsSettings.model) { oldValue, newValue in
                        Task {
                            await viewModel.updateTTSSetting(\.model, newValue)
                        }
                    }
                }

                // MARK: - Audio Quality

                Section("Audio Quality") {
                    Picker("Output Format", selection: $viewModel.settings.ttsSettings.outputFormat) {
                        ForEach(TTSOutputFormat.allCases, id: \.self) { format in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.displayName).tag(format)
                                Text(format.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onChange(of: viewModel.settings.ttsSettings.outputFormat) { oldValue, newValue in
                        Task {
                            await viewModel.updateTTSSetting(\.outputFormat, newValue)
                        }
                    }
                }

                // MARK: - Voice Selection

                Section("Voices") {
                    HStack {
                        Label("User Message Voice", systemImage: "person.fill")
                        Spacer()
                        NavigationLink(destination: VoiceSelectionView(
                            selectedVoiceId: $viewModel.settings.ttsSettings.userVoiceId,
                            availableVoices: availableVoices
                        )) {
                            Text(getVoiceName(viewModel.settings.ttsSettings.userVoiceId))
                                .foregroundColor(.blue)
                        }
                    }

                    HStack {
                        Label("Assistant Voice", systemImage: "bubble.left.fill")
                        Spacer()
                        NavigationLink(destination: VoiceSelectionView(
                            selectedVoiceId: $viewModel.settings.ttsSettings.assistantVoiceId,
                            availableVoices: availableVoices
                        )) {
                            Text(getVoiceName(viewModel.settings.ttsSettings.assistantVoiceId))
                                .foregroundColor(.blue)
                        }
                    }
                }

                // MARK: - Voice Parameters

                Section("Voice Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Stability", systemImage: "waveform")
                            Spacer()
                            Text(String(format: "%.0f%%", viewModel.settings.ttsSettings.voiceSettings.stability * 100))
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: $viewModel.settings.ttsSettings.voiceSettings.stability,
                            in: 0...1,
                            step: 0.05
                        )
                        .onChange(of: viewModel.settings.ttsSettings.voiceSettings.stability) { oldValue, newValue in
                            Task {
                                await viewModel.updateTTSSetting(\.voiceSettings.stability, newValue)
                            }
                        }

                        Text("Lower = more varied, Higher = more consistent")
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                    }
                    .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Similarity Boost", systemImage: "sparkles")
                            Spacer()
                            Text(String(format: "%.0f%%", viewModel.settings.ttsSettings.voiceSettings.similarityBoost * 100))
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: $viewModel.settings.ttsSettings.voiceSettings.similarityBoost,
                            in: 0...1,
                            step: 0.05
                        )
                        .onChange(of: viewModel.settings.ttsSettings.voiceSettings.similarityBoost) { oldValue, newValue in
                            Task {
                                await viewModel.updateTTSSetting(\.voiceSettings.similarityBoost, newValue)
                            }
                        }

                        Text("How closely to match the original voice")
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                    }
                    .padding(.vertical, 8)

                    Toggle("Speaker Boost", isOn: $viewModel.settings.ttsSettings.voiceSettings.useSpeakerBoost)
                        .onChange(of: viewModel.settings.ttsSettings.voiceSettings.useSpeakerBoost) { oldValue, newValue in
                            Task {
                                await viewModel.updateTTSSetting(\.voiceSettings.useSpeakerBoost, newValue)
                            }
                        }
                }

                // MARK: - Info

                Section {
                    Label(
                        "Adjust these settings to customize the voice output. Changes are applied to new TTS requests.",
                        systemImage: "info.circle"
                    )
                    .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Text-to-Speech")
        .sheet(isPresented: $showAPIKeySheet) {
            APIKeyInputSheet(
                provider: .elevenlabs,
                keyValue: Binding(
                    get: { viewModel.settings.ttsSettings.elevenLabsApiKey ?? "" },
                    set: { viewModel.settings.ttsSettings.elevenLabsApiKey = $0 }
                ),
                onSave: {
                    Task {
                        await viewModel.saveTTSAPIKey()
                        showAPIKeySheet = false
                    }
                },
                onCancel: {
                    showAPIKeySheet = false
                }
            )
        }
        .task {
            if isLoadingVoices { return }
            isLoadingVoices = true
            // Fetch available voices from ElevenLabs API
            isLoadingVoices = false
        }
    }

    private func getVoiceName(_ voiceId: String) -> String {
        availableVoices.first { $0.voiceId == voiceId }?.name ?? "Unknown"
    }
}

struct VoiceSelectionView: View {
    @Binding var selectedVoiceId: String
    let availableVoices: [ElevenLabsVoice]
    @State private var isPlayingPreview: [String: Bool] = [:]

    var body: some View {
        List {
            ForEach(availableVoices) { voice in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(voice.name)
                            .font(.headline)

                        HStack(spacing: 8) {
                            ForEach(voice.labels.values.sorted(), id: \.self) { label in
                                Text(label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }

                    Spacer()

                    if selectedVoiceId == voice.voiceId {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    if let previewUrl = voice.previewUrl {
                        Button(action: {
                            // Play preview
                            if let url = URL(string: previewUrl) {
                                URLSession.shared.dataTask(with: url) { data, _, _ in
                                    if let data = data {
                                        let audioSession = AVAudioSession.sharedInstance()
                                        try? audioSession.setCategory(.playback)
                                        try? audioSession.setActive(true)
                                        // Play audio
                                    }
                                }.resume()
                            }
                        }) {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedVoiceId = voice.voiceId
                }
            }
        }
        .navigationTitle("Select Voice")
    }
}

#Preview {
    NavigationStack {
        TTSSettingsView(viewModel: SettingsViewModel())
    }
}
```

---

## Super Admin Settings

### Features

- **Jules API Configuration**: GitHub repo, branch, auto-approve
- **Rate Limit Status**: Display API usage and limits
- **Audit Log Settings**: Retention days configuration
- **System Settings**: Enable/disable features

### Implementation

**Views/Settings/SuperAdminSettingsView.swift**:

```swift
import SwiftUI

struct SuperAdminSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isLoadingRateLimits = false

    var superAdminSettings: SuperAdminSettings? {
        viewModel.settings.superAdminSettings
    }

    var body: some View {
        Form {
            // MARK: - Rate Limits

            Section("Rate Limits") {
                if isLoadingRateLimits {
                    ProgressView()
                } else if let settings = superAdminSettings {
                    HStack {
                        Label("Calls Used", systemImage: "checkmark.circle.fill")
                        Spacer()
                        Text(String(settings.julesAPICallsUsed))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Daily Limit", systemImage: "limit.circle.fill")
                        Spacer()
                        Text(String(settings.julesAPIRateLimitPerDay))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Remaining", systemImage: "arrow.up.circle.fill")
                        Spacer()
                        Text(String(settings.julesAPICallsRemaining))
                            .foregroundColor(
                                settings.julesAPICallsRemaining > 10 ? .green : .orange
                            )
                    }

                    if let resetTime = settings.julesAPIResetTime {
                        HStack {
                            Label("Resets", systemImage: "timer")
                            Spacer()
                            Text(resetTime.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // MARK: - Jules API Configuration

            Section("Jules API Configuration") {
                if var settings = superAdminSettings {
                    TextField(
                        "GitHub Repository",
                        text: Binding(
                            get: { settings.julesAPIGitHubRepo ?? "" },
                            set: { settings.julesAPIGitHubRepo = $0 }
                        )
                    )
                    .onChange(of: settings.julesAPIGitHubRepo) { _, newValue in
                        Task {
                            if let settings = viewModel.settings.superAdminSettings {
                                var updated = settings
                                updated.julesAPIGitHubRepo = newValue
                                viewModel.settings.superAdminSettings = updated
                                await viewModel.updateSetting(\.superAdminSettings, updated)
                            }
                        }
                    }

                    Picker(
                        "Default Branch",
                        selection: Binding(
                            get: { settings.julesAPIDefaultBranch },
                            set: { settings.julesAPIDefaultBranch = $0 }
                        )
                    ) {
                        Text("main").tag("main")
                        Text("develop").tag("develop")
                        Text("master").tag("master")
                    }
                    .onChange(of: settings.julesAPIDefaultBranch) { _, newValue in
                        Task {
                            if let settings = viewModel.settings.superAdminSettings {
                                var updated = settings
                                updated.julesAPIDefaultBranch = newValue
                                viewModel.settings.superAdminSettings = updated
                                await viewModel.updateSetting(\.superAdminSettings, updated)
                            }
                        }
                    }

                    Toggle(
                        "Auto-Approve Execution Plans",
                        isOn: Binding(
                            get: { settings.julesAPIAutoApprovePlans },
                            set: { settings.julesAPIAutoApprovePlans = $0 }
                        )
                    )
                    .onChange(of: settings.julesAPIAutoApprovePlans) { _, newValue in
                        Task {
                            if let settings = viewModel.settings.superAdminSettings {
                                var updated = settings
                                updated.julesAPIAutoApprovePlans = newValue
                                viewModel.settings.superAdminSettings = updated
                                await viewModel.updateSetting(\.superAdminSettings, updated)
                            }
                        }
                    }
                }
            }

            // MARK: - Audit Log

            Section("Audit & Logging") {
                if var settings = superAdminSettings {
                    Stepper(
                        "Audit Log Retention: \(settings.auditLogRetentionDays) days",
                        value: Binding(
                            get: { settings.auditLogRetentionDays },
                            set: { settings.auditLogRetentionDays = $0 }
                        ),
                        in: 7...365
                    )
                    .onChange(of: settings.auditLogRetentionDays) { _, newValue in
                        Task {
                            if let settings = viewModel.settings.superAdminSettings {
                                var updated = settings
                                updated.auditLogRetentionDays = newValue
                                viewModel.settings.superAdminSettings = updated
                                await viewModel.updateSetting(\.superAdminSettings, updated)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Super Admin")
        .task {
            isLoadingRateLimits = true
            // Fetch rate limit info from API
            isLoadingRateLimits = false
        }
    }
}

#Preview {
    NavigationStack {
        SuperAdminSettingsView(viewModel: SettingsViewModel())
    }
}
```

---

## Settings Persistence

### 1. UserDefaults Service

**Services/SettingsStorage.swift**:

```swift
import Foundation

class SettingsStorage {
    static let shared = SettingsStorage()

    private let defaults = UserDefaults.standard
    private let settingsKey = "app.settings"
    private let versionKey = "app.settings.version"

    // MARK: - Save & Load

    func saveSettings(_ settings: AppSettings) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: settingsKey)
    }

    func loadSettings() -> AppSettings? {
        guard let data = defaults.data(forKey: settingsKey) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            print("Error decoding settings: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Individual Settings

    func saveSetting<T: Encodable>(_ keyPath: KeyPath<AppSettings, T>, value: T) throws {
        var settings = loadSettings() ?? AppSettings()

        // Use reflection to set the value
        var tempSettings = settings
        // Note: This requires a custom approach since KeyPath doesn't support setting
        // Consider using a switch statement or dictionary-based approach instead

        try saveSettings(tempSettings)
    }

    // MARK: - Clear

    func clearSettings() {
        defaults.removeObject(forKey: settingsKey)
    }

    // MARK: - Migration

    func migrateIfNeeded() {
        let currentVersion = defaults.integer(forKey: versionKey)

        if currentVersion < 1 {
            // Migration from version 0 to 1
            // Add any necessary migrations here
            defaults.set(1, forKey: versionKey)
        }
    }
}
```

### 2. Firestore Encrypted Settings

**Services/FirestoreSettingsService.swift**:

```swift
import Foundation
import CryptoKit
import FirebaseFirestore

@MainActor
class FirestoreSettingsService: ObservableObject {
    static let shared = FirestoreSettingsService()

    private let db = Firestore.firestore()
    private let encryptionService = EncryptionService.shared

    // MARK: - Save Settings

    func saveSettings(
        _ settings: AppSettings,
        for userId: String
    ) async throws {
        // Encrypt sensitive data
        var settingsData = try JSONEncoder().encode(settings)

        // Encrypt API keys
        if var encrypted = try? encryptionService.encrypt(settingsData) {
            let docData: [String: Any] = [
                "settings": encrypted,
                "version": settings.version,
                "updatedAt": FieldValue.serverTimestamp(),
                "userId": userId
            ]

            try await db.collection("users")
                .document(userId)
                .collection("settings")
                .document("preferences")
                .setData(docData, merge: true)
        }
    }

    // MARK: - Load Settings

    func loadSettings(for userId: String) async throws -> AppSettings? {
        let document = try await db.collection("users")
            .document(userId)
            .collection("settings")
            .document("preferences")
            .getDocument()

        guard let data = document.data(),
              let encryptedData = data["settings"] as? String else {
            return nil
        }

        // Decrypt and decode
        let decrypted = try encryptionService.decrypt(encryptedData)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        return try decoder.decode(AppSettings.self, from: decrypted)
    }

    // MARK: - Update Individual Setting

    func updateSetting<T: Encodable>(
        _ keyPath: PartialKeyPath<AppSettings>,
        value: T,
        for userId: String
    ) async throws {
        // Load current settings
        var currentSettings = try await loadSettings(for: userId) ?? AppSettings()

        // Update based on keyPath
        // This requires a custom update mechanism

        // Save updated settings
        try await saveSettings(currentSettings, for: userId)
    }
}
```

---

## Settings Service Implementation

### Settings ViewModel

**ViewModels/SettingsViewModel.swift**:

```swift
import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = AppSettings()
    @Published var isLoading = false
    @Published var error: String?
    @Published var successMessage: String?

    private let storageService = SettingsStorage.shared
    private let firestoreService = FirestoreSettingsService.shared
    private let authService = AuthenticationService.shared

    init() {
        loadSettings()
    }

    // MARK: - Load Settings

    private func loadSettings() {
        // Load from local storage first
        if let localSettings = storageService.loadSettings() {
            self.settings = localSettings
        }

        // Sync from Firestore if authenticated
        if let userId = authService.user?.uid {
            Task {
                do {
                    let firestoreSettings = try await firestoreService.loadSettings(for: userId)
                    if let firestoreSettings = firestoreSettings {
                        self.settings = firestoreSettings
                    }
                } catch {
                    self.error = "Failed to sync settings: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Update Settings

    func updateSetting<T: Encodable>(
        _ keyPath: WritableKeyPath<AppSettings, T>,
        _ newValue: T
    ) async {
        // Update local
        settings[keyPath: keyPath] = newValue
        settings.lastUpdated = Date()

        // Persist to UserDefaults
        do {
            try storageService.saveSettings(settings)
        } catch {
            self.error = "Failed to save settings: \(error.localizedDescription)"
        }

        // Sync to Firestore
        if let userId = authService.user?.uid {
            do {
                try await firestoreService.saveSettings(settings, for: userId)
                settings.lastSyncedAt = Date()
            } catch {
                self.error = "Failed to sync settings: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - API Keys

    func isAPIKeyConfigured(_ provider: APIProvider) -> Bool {
        switch provider {
        case .openai: return !settings.apiKeys.openaiKey.isNilOrEmpty
        case .anthropic: return !settings.apiKeys.anthropicKey.isNilOrEmpty
        case .gemini: return !settings.apiKeys.geminiKey.isNilOrEmpty
        case .elevenlabs: return !settings.apiKeys.elevenLabsKey.isNilOrEmpty
        }
    }

    func getAPIKey(_ provider: APIProvider) -> String? {
        settings.apiKeys.getKey(for: provider)
    }

    func saveAPIKey(_ key: String, for provider: APIProvider) async {
        isLoading = true
        defer { isLoading = false }

        var updatedKeys = settings.apiKeys

        switch provider {
        case .openai: updatedKeys.openaiKey = key
        case .anthropic: updatedKeys.anthropicKey = key
        case .gemini: updatedKeys.geminiKey = key
        case .elevenlabs: updatedKeys.elevenLabsKey = key
        }

        await updateSetting(\.apiKeys, updatedKeys)
        showSuccessMessage("API key saved securely")
    }

    func clearAPIKey(_ provider: APIProvider) async {
        var updatedKeys = settings.apiKeys
        updatedKeys.clearKey(for: provider)
        await updateSetting(\.apiKeys, updatedKeys)
        showSuccessMessage("API key cleared")
    }

    // MARK: - TTS Settings

    func saveTTSAPIKey() async {
        await updateSetting(\.ttsSettings, settings.ttsSettings)
        showSuccessMessage("TTS configuration saved")
    }

    func clearTTSAPIKey() async {
        var updated = settings.ttsSettings
        updated.elevenLabsApiKey = nil
        await updateSetting(\.ttsSettings, updated)
        showSuccessMessage("TTS API key cleared")
    }

    func updateTTSSetting<T: Encodable>(
        _ keyPath: WritableKeyPath<TTSSettings, T>,
        _ value: T
    ) async {
        settings.ttsSettings[keyPath: keyPath] = value
        await updateSetting(\.ttsSettings, settings.ttsSettings)
    }

    // MARK: - Current Model

    var currentModel: AIModel? {
        settings.defaultProvider.availableModels.first { $0.id == settings.defaultModel }
    }

    // MARK: - Messages

    func showSuccessMessage(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.successMessage = nil
        }
    }
}
```

---

## Integration with App

### Main Settings View

**Views/Settings/SettingsView.swift**:

```swift
import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            TabView {
                // General Tab
                GeneralSettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }

                // Account Tab
                AccountSettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("Account", systemImage: "person.crop.circle.fill")
                    }

                // Memory Tab
                MemorySettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("Memory", systemImage: "brain.head.profile")
                    }

                // API Keys Tab
                APIKeysSettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("API Keys", systemImage: "key.fill")
                    }

                // TTS Tab
                TTSSettingsView(viewModel: viewModel)
                    .tabItem {
                        Label("TTS", systemImage: "waveform.circle.fill")
                    }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: { dismiss() })
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
```

---

## Migration & Backup

### Settings Export

```swift
extension SettingsViewModel {
    func exportSettings() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(settings)
    }

    func importSettings(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let imported = try decoder.decode(AppSettings.self, from: data)
        self.settings = imported

        // Persist
        try storageService.saveSettings(settings)
    }
}
```

---

## Checklist for SwiftUI Implementation

- [ ] Create all Settings data models (`AppSettings`, `TTSSettings`, etc.)
- [ ] Implement `SettingsViewModel` with @MainActor
- [ ] Create `GeneralSettingsView` with theme and provider selection
- [ ] Create `AccountSettingsView` with profile and security options
- [ ] Create `MemorySettingsView` with sliders and toggles
- [ ] Create `APIKeysSettingsView` with secure key input
- [ ] Create `TTSSettingsView` with model and voice selection
- [ ] Implement `SettingsStorage` for UserDefaults persistence
- [ ] Implement `FirestoreSettingsService` for cloud sync
- [ ] Add encryption for sensitive settings
- [ ] Create `SuperAdminSettingsView` if needed
- [ ] Test all settings persistence paths
- [ ] Implement settings export/import
- [ ] Add loading and error states
- [ ] Test with Firebase emulator

---

**Document Version:** 1.0
**Last Updated:** October 29, 2025
**Platform:** iOS 14.0+, SwiftUI
