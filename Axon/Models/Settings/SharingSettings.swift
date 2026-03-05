//
//  SharingSettings.swift
//  Axon
//
//  AI sharing settings for guest access
//

import Foundation

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

// MARK: - Guest Capabilities Preset

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
