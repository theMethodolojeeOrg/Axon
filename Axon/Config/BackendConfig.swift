//
//  BackendConfig.swift
//  Axon
//
//  Backend Configuration - User-configurable cloud backend
//  Replaces hardcoded Firebase URLs with user-provided endpoints
//

import Foundation
import Combine

/// Backend configuration that reads from user settings
/// Allows users to point to their own cloud functions or use no backend at all
@MainActor
class BackendConfig: ObservableObject {
    static let shared = BackendConfig()

    private var settingsStorage: SettingsStorage { SettingsStorage.shared }

    private init() {}

    // MARK: - Backend URL

    /// The user-configured backend API URL, or nil if not configured
    var apiURL: URL? {
        guard let settings = settingsStorage.loadSettings(),
              let urlString = settings.backendAPIURL,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    /// Whether a backend is configured
    var isBackendConfigured: Bool {
        apiURL != nil
    }

    /// Whether cloud features should be enabled
    var cloudFeaturesEnabled: Bool {
        isBackendConfigured
    }

    // MARK: - Convenience Methods

    /// Build a full URL for an endpoint path
    /// Returns nil if no backend is configured
    func url(for endpoint: String) -> URL? {
        guard let baseURL = apiURL else { return nil }
        return baseURL.appendingPathComponent(endpoint)
    }

    /// Get the backend URL string for display in settings
    var displayURL: String {
        settingsStorage.loadSettings()?.backendAPIURL ?? "Not configured"
    }

    // MARK: - Validation

    /// Validate a backend URL string
    static func validateURL(_ urlString: String) -> BackendURLValidation {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .empty
        }

        guard let url = URL(string: trimmed) else {
            return .invalid("Invalid URL format")
        }

        guard url.scheme == "https" || url.scheme == "http" else {
            return .invalid("URL must use http or https")
        }

        guard url.host != nil else {
            return .invalid("URL must have a host")
        }

        // Warn about http in production
        if url.scheme == "http" && !trimmed.contains("localhost") {
            return .warning("Using HTTP is not recommended for production")
        }

        return .valid
    }
}

// MARK: - Validation Result

enum BackendURLValidation: Equatable {
    case empty
    case valid
    case warning(String)
    case invalid(String)

    var isUsable: Bool {
        switch self {
        case .empty, .valid, .warning:
            return true
        case .invalid:
            return false
        }
    }

    var message: String? {
        switch self {
        case .empty:
            return nil
        case .valid:
            return nil
        case .warning(let msg), .invalid(let msg):
            return msg
        }
    }
}

// MARK: - Legacy Firebase Compatibility

/// Extension to provide backward compatibility with existing code
/// that references FirebaseConfig
extension BackendConfig {
    /// Legacy accessor for code still using FirebaseConfig pattern
    /// Maps to the new user-configurable backend
    var environment: BackendEnvironment {
        BackendEnvironment(apiURL: apiURL)
    }
}

/// Minimal environment struct for backward compatibility
struct BackendEnvironment {
    let apiURL: URL?

    /// For legacy code that expects a non-optional URL
    /// Returns a dummy URL if not configured (callers should check isBackendConfigured first)
    var apiURLOrPlaceholder: URL {
        apiURL ?? URL(string: "https://backend-not-configured.local")!
    }
}
