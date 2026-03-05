//
//  SovereigntySettings.swift
//  Axon
//
//  Co-sovereignty settings (AI consent, negotiations, deadlocks)
//

import Foundation

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
