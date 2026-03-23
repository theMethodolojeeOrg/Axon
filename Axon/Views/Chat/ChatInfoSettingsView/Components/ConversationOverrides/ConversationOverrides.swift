//
//  ConversationOverrides.swift
//  Axon
//
//  Per-conversation settings overrides model
//

import Foundation

/// Sampling parameter overrides scoped to a conversation (or turn lease payload).
struct ConversationSamplingOverride: Codable, Equatable, Sendable {
    var temperature: Double?
    var topP: Double?
    var topK: Int?

    var hasAnyValue: Bool {
        temperature != nil || topP != nil || topK != nil
    }
}

/// Stores per-conversation overrides for provider, model, live voice, and tools.
/// When nil values are used, the global defaults apply.
struct ConversationOverrides: Codable, Equatable {
    // MARK: - Provider/Model Identifiers

    var builtInProvider: String?
    var customProviderId: UUID?
    var builtInModel: String?
    var customModelId: UUID?
    var model: String?

    // MARK: - Runtime Sampling Overrides

    /// Optional per-conversation sampling overrides.
    var samplingOverride: ConversationSamplingOverride?

    // MARK: - Realtime Live Session Overrides

    var liveProvider: String?
    var liveModel: String?
    var liveVoice: String?

    // MARK: - Human-Friendly Metadata

    /// Display name for the selected provider (for UI without re-lookup)
    var providerDisplayName: String?

    /// Display name for the selected model (for UI without re-lookup)
    var modelDisplayName: String?

    // MARK: - Per-Conversation Tool Settings

    /// When nil, use global defaults. When set, these override for this conversation only.
    var enabledToolIds: Set<String>?

    // MARK: - Subconscious Memory Logging

    /// Thread-level override for subconscious memory logging.
    /// - true: disabled for this conversation
    /// - nil/false: follows global setting
    var subconsciousLoggingDisabled: Bool?
}
