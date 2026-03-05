//
//  BridgeSettings.swift
//  Axon
//
//  Persistent settings for the VS Code bridge, including paired devices
//  for automatic reconnection.
//
//  Supports two connection modes:
//  - Local Mode: Axon is server (default), VS Code connects as client
//  - Remote Mode: VS Code is server, Axon connects as client (for LAN access)
//

import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

// MARK: - Bridge Settings

/// Settings for the VS Code bridge feature
struct BridgeSettings: Codable, Equatable, Sendable {
    /// Whether the bridge feature is enabled
    var enabled: Bool = false

    // MARK: - Connection Mode

    /// Connection mode: local (Axon server) or remote (VS Code server)
    var mode: BridgeMode = .local

    // MARK: - Local Mode Settings (Axon as Host / Server)

    /// Port to listen on for WebSocket connections (Host Mode)
    var port: UInt16 = 8081

    /// Bind address for the server (0.0.0.0 for LAN access, 127.0.0.1 for localhost only)
    var serverBindAddress: String = "0.0.0.0"

    // MARK: - Remote Mode Settings (Axon as Client / VS Code as Server)

    /// Host/IP address of the VS Code server (Client Mode)
    var remoteHost: String = ""

    /// Port of the VS Code server (Client Mode)
    var remotePort: UInt16 = 8082

    /// Device name to identify this Axon instance
    var deviceName: String = ""

    /// Reconnect interval base in seconds (Client Mode)
    var reconnectInterval: TimeInterval = 5.0

    /// Maximum reconnect attempts before giving up (Client Mode)
    var maxReconnectAttempts: Int = 6

    /// Saved remote bridge targets for quick switching
    var connectionProfiles: [BridgeConnectionProfile] = []

    /// ID of the profile selected as default
    var defaultConnectionProfileId: UUID?

    /// Device-local behavior to connect to default profile when app becomes active
    var autoConnectDefaultOnActive: Bool = false

    /// Most recently connected profile ID
    var lastConnectedProfileId: UUID?

    // MARK: - TLS Settings

    /// Whether to use TLS (wss://) for connections
    var tlsEnabled: Bool = false

    /// Trusted certificate fingerprints (SHA-256) for self-signed certs
    var trustedCertFingerprints: [String] = []

    // MARK: - Multi-Session Settings

    /// Allow multiple VS Code workspaces to connect simultaneously
    var allowMultipleSessions: Bool = true

    // MARK: - General Settings

    /// Auto-start bridge when app launches (if enabled)
    var autoStart: Bool = false

    /// Previously paired devices for auto-reconnect
    var pairedDevices: [PairedDevice] = []

    /// Automatically approve read operations (no biometric)
    var autoApproveReads: Bool = true

    /// Maximum file size to read (bytes)
    var maxFileSize: Int = 10 * 1024 * 1024  // 10 MB

    /// Terminal command timeout (seconds)
    var terminalTimeout: Int = 60

    /// Optional pairing token required to accept VS Code connections.
    ///
    /// When set (non-empty), Axon will reject hello handshakes that do not present
    /// the same token. This prevents arbitrary localhost processes from connecting.
    var requiredPairingToken: String = ""

    /// Blocked file patterns (glob-style)
    var blockedPatterns: [String] = [
        "**/.env",
        "**/.env.*",
        "**/credentials*",
        "**/secrets*",
        "**/*.pem",
        "**/*.key",
        "**/id_rsa*",
        "**/id_ed25519*"
    ]

    // MARK: - Computed Properties

    /// The WebSocket URL for Remote Mode connections
    var remoteURL: String {
        let scheme = tlsEnabled ? "wss" : "ws"
        return "\(scheme)://\(remoteHost):\(remotePort)"
    }

    /// Whether Remote Mode settings are valid
    var isRemoteModeConfigured: Bool {
        !remoteHost.isEmpty && remotePort > 0
    }

    /// Get the effective device name (or fallback)
    var effectiveDeviceName: String {
        if deviceName.isEmpty {
            #if os(iOS)
            return UIDevice.current.name
            #else
            return Host.current().localizedName ?? "Mac"
            #endif
        }
        return deviceName
    }

    // MARK: - Device Management

    /// Add or update a paired device
    mutating func recordDevice(_ session: BridgeSession) {
        if let index = pairedDevices.firstIndex(where: { $0.workspaceId == session.workspaceId }) {
            pairedDevices[index].lastConnectedAt = Date()
        } else {
            let device = PairedDevice(
                id: session.id,
                workspaceId: session.workspaceId,
                workspaceName: session.workspaceName,
                workspaceRoot: session.workspaceRoot,
                firstPairedAt: Date(),
                lastConnectedAt: Date()
            )
            pairedDevices.append(device)
        }
    }

    /// Remove a paired device
    mutating func removeDevice(workspaceId: String) {
        pairedDevices.removeAll { $0.workspaceId == workspaceId }
    }

    /// Check if a workspace was previously paired
    func isPaired(workspaceId: String) -> Bool {
        pairedDevices.contains { $0.workspaceId == workspaceId }
    }

    /// Get paired device by workspace ID
    func pairedDevice(for workspaceId: String) -> PairedDevice? {
        pairedDevices.first { $0.workspaceId == workspaceId }
    }

    // MARK: - Path Validation

    /// Check if a file path is blocked
    func isPathBlocked(_ path: String) -> Bool {
        for pattern in blockedPatterns {
            if matchesGlobPattern(path: path, pattern: pattern) {
                return true
            }
        }
        return false
    }

    /// Simple glob pattern matching
    private func matchesGlobPattern(path: String, pattern: String) -> Bool {
        // Convert glob to regex
        var regex = "^"
        var i = pattern.startIndex

        while i < pattern.endIndex {
            let char = pattern[i]

            if char == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex && pattern[next] == "*" {
                    // ** matches any path segment
                    regex += ".*"
                    i = pattern.index(after: next)
                    // Skip following slash if present
                    if i < pattern.endIndex && pattern[i] == "/" {
                        i = pattern.index(after: i)
                    }
                    continue
                } else {
                    // * matches anything except /
                    regex += "[^/]*"
                }
            } else if char == "?" {
                regex += "[^/]"
            } else if char == "." {
                regex += "\\."
            } else {
                regex += String(char)
            }

            i = pattern.index(after: i)
        }

        regex += "$"

        guard let regexObj = try? NSRegularExpression(pattern: regex, options: []) else {
            return false
        }

        let range = NSRange(path.startIndex..., in: path)
        return regexObj.firstMatch(in: path, options: [], range: range) != nil
    }
}

// MARK: - Connection Profile

struct BridgeConnectionProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var host: String
    var port: UInt16
    var tlsEnabled: Bool
    let createdAt: Date
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16,
        tlsEnabled: Bool,
        createdAt: Date = Date(),
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.tlsEnabled = tlsEnabled
        self.createdAt = createdAt
        self.lastConnectedAt = lastConnectedAt
    }

    var displayAddress: String {
        let scheme = tlsEnabled ? "wss" : "ws"
        return "\(scheme)://\(host):\(port)"
    }
}

// MARK: - Paired Device

/// A previously connected VS Code workspace
struct PairedDevice: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let workspaceId: String
    let workspaceName: String
    let workspaceRoot: String
    let firstPairedAt: Date
    var lastConnectedAt: Date

    /// How long since last connection
    var timeSinceLastConnection: TimeInterval {
        Date().timeIntervalSince(lastConnectedAt)
    }

    /// Human-readable last connection time
    var lastConnectedDescription: String {
        let seconds = timeSinceLastConnection

        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}

// MARK: - Bridge Settings Storage

/// Manages persistence of bridge settings
@MainActor
class BridgeSettingsStorage: ObservableObject {
    static let shared = BridgeSettingsStorage()

    private let defaults = UserDefaults.standard
    private let settingsKey = "BridgeSettings"

    @Published var settings: BridgeSettings {
        didSet {
            save()
        }
    }

    private init() {
        self.settings = BridgeSettingsStorage.load()
    }

    private static func load() -> BridgeSettings {
        guard let data = UserDefaults.standard.data(forKey: "BridgeSettings"),
              let settings = try? JSONDecoder().decode(BridgeSettings.self, from: data) else {
            return BridgeSettings()
        }
        return settings
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    /// Record a connection for persistent pairing
    func recordConnection(_ session: BridgeSession) {
        settings.recordDevice(session)
    }

    /// Remove a paired device
    func removePairedDevice(workspaceId: String) {
        settings.removeDevice(workspaceId: workspaceId)
    }

    /// Toggle bridge enabled state
    func setEnabled(_ enabled: Bool) {
        settings.enabled = enabled
    }

    /// Update port
    func setPort(_ port: UInt16) {
        settings.port = port
    }

    /// Update connection mode
    func setMode(_ mode: BridgeMode) {
        settings.mode = mode
    }

    /// Update Remote Mode settings
    func setRemoteConfig(host: String, port: UInt16) {
        settings.remoteHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.remotePort = port
    }

    /// Update TLS settings
    func setTLSEnabled(_ enabled: Bool) {
        settings.tlsEnabled = enabled
    }

    /// Update required pairing token
    func setRequiredPairingToken(_ token: String) {
        settings.requiredPairingToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Add a trusted certificate fingerprint
    func addTrustedCertFingerprint(_ fingerprint: String) {
        if !settings.trustedCertFingerprints.contains(fingerprint) {
            settings.trustedCertFingerprints.append(fingerprint)
        }
    }

    /// Remove a trusted certificate fingerprint
    func removeTrustedCertFingerprint(_ fingerprint: String) {
        settings.trustedCertFingerprints.removeAll { $0 == fingerprint }
    }

    // MARK: - Connection Profiles

    @discardableResult
    func createConnectionProfile(
        name: String,
        host: String,
        port: UInt16,
        tlsEnabled: Bool,
        lastConnectedAt: Date? = nil
    ) -> BridgeConnectionProfile {
        let profile = BridgeConnectionProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            tlsEnabled: tlsEnabled,
            lastConnectedAt: lastConnectedAt
        )
        settings.connectionProfiles.append(profile)
        return profile
    }

    @discardableResult
    func updateConnectionProfile(_ profile: BridgeConnectionProfile) -> Bool {
        guard let index = settings.connectionProfiles.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }

        var updated = profile
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.host = updated.host.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.connectionProfiles[index] = updated
        return true
    }

    func deleteConnectionProfile(id: UUID) {
        settings.connectionProfiles.removeAll { $0.id == id }

        if settings.defaultConnectionProfileId == id {
            settings.defaultConnectionProfileId = nil
        }

        if settings.lastConnectedProfileId == id {
            settings.lastConnectedProfileId = nil
        }
    }

    func setDefaultConnectionProfile(_ profileId: UUID?) {
        guard let profileId else {
            settings.defaultConnectionProfileId = nil
            return
        }

        guard settings.connectionProfiles.contains(where: { $0.id == profileId }) else {
            return
        }

        settings.defaultConnectionProfileId = profileId
    }

    func connectionProfile(id: UUID) -> BridgeConnectionProfile? {
        settings.connectionProfiles.first { $0.id == id }
    }

    func defaultConnectionProfile() -> BridgeConnectionProfile? {
        guard let profileId = settings.defaultConnectionProfileId else { return nil }
        return settings.connectionProfiles.first { $0.id == profileId }
    }

    func resolveDefaultConnectionProfile() -> BridgeConnectionProfile? {
        guard let profileId = settings.defaultConnectionProfileId else { return nil }

        guard let profile = settings.connectionProfiles.first(where: { $0.id == profileId }) else {
            settings.defaultConnectionProfileId = nil
            return nil
        }

        return profile
    }

    @discardableResult
    func applyConnectionProfileToActiveRemoteConfig(profileId: UUID) -> BridgeConnectionProfile? {
        guard let profile = connectionProfile(id: profileId) else { return nil }
        settings.remoteHost = profile.host
        settings.remotePort = profile.port
        settings.tlsEnabled = profile.tlsEnabled
        return profile
    }

    func profileIdMatchingActiveRemoteConfig() -> UUID? {
        settings.connectionProfiles.first(where: {
            $0.host == settings.remoteHost &&
            $0.port == settings.remotePort &&
            $0.tlsEnabled == settings.tlsEnabled
        })?.id
    }

    func markConnectedProfile(_ profileId: UUID) {
        guard let index = settings.connectionProfiles.firstIndex(where: { $0.id == profileId }) else {
            return
        }

        settings.connectionProfiles[index].lastConnectedAt = Date()
        settings.lastConnectedProfileId = profileId
    }

    func setAutoConnectDefaultOnActive(_ enabled: Bool) {
        settings.autoConnectDefaultOnActive = enabled
    }

    // MARK: - Host Mode Settings

    func setServerBindAddress(_ address: String) {
        settings.serverBindAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setServerPort(_ port: UInt16) {
        settings.port = port
    }

    // MARK: - Client Mode Settings

    func setReconnectInterval(_ interval: TimeInterval) {
        settings.reconnectInterval = max(1.0, interval)
    }

    func setMaxReconnectAttempts(_ count: Int) {
        settings.maxReconnectAttempts = max(1, count)
    }

    // MARK: - Advanced Settings

    func setAllowMultipleSessions(_ enabled: Bool) {
        settings.allowMultipleSessions = enabled
    }

    func setAutoApproveReads(_ enabled: Bool) {
        settings.autoApproveReads = enabled
    }

    func setMaxFileSize(_ bytes: Int) {
        settings.maxFileSize = max(1024, bytes)
    }

    func setTerminalTimeout(_ seconds: Int) {
        settings.terminalTimeout = max(5, seconds)
    }

    func setBlockedPatterns(_ patterns: [String]) {
        settings.blockedPatterns = patterns
    }

    func setAutoStart(_ enabled: Bool) {
        settings.autoStart = enabled
    }
}
