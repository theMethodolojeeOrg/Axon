//
//  GuestInvitation.swift
//  Axon
//
//  Created by Tom on 2025.
//

import Foundation
import CryptoKit

// MARK: - Guest Invitation

/// An invitation created after a sharing request is jointly approved
/// The invitation token is shown once at creation; only the hash is stored
struct GuestInvitation: Codable, Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let expiresAt: Date
    let createdBy: String
    let requestId: String?

    let tokenHash: String
    let grantedCapabilities: GuestCapabilities
    let maxSessions: Int

    var usageCount: Int
    var lastUsedAt: Date?
    var isRevoked: Bool
    var revokedAt: Date?
    var revokedReason: String?

    let guestName: String
    var note: String?

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        expiresAt: Date,
        createdBy: String,
        requestId: String? = nil,
        tokenHash: String,
        grantedCapabilities: GuestCapabilities,
        maxSessions: Int = 1,
        guestName: String,
        note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.createdBy = createdBy
        self.requestId = requestId
        self.tokenHash = tokenHash
        self.grantedCapabilities = grantedCapabilities
        self.maxSessions = maxSessions
        self.usageCount = 0
        self.isRevoked = false
        self.guestName = guestName
        self.note = note
    }

    var isExpired: Bool {
        Date() > expiresAt || isRevoked
    }

    var isValid: Bool {
        !isExpired && usageCount < maxSessions
    }

    var remainingSessions: Int {
        max(0, maxSessions - usageCount)
    }

    var timeRemaining: TimeInterval {
        max(0, expiresAt.timeIntervalSince(Date()))
    }

    var formattedTimeRemaining: String {
        let remaining = timeRemaining
        if remaining <= 0 {
            return "Expired"
        }

        let hours = Int(remaining / 3600)
        let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours >= 24 {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s") remaining"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes) minutes remaining"
        }
    }

    var statusDescription: String {
        if isRevoked {
            return "Revoked"
        } else if isExpired {
            return "Expired"
        } else if usageCount >= maxSessions {
            return "Fully Used"
        } else {
            return "Active"
        }
    }

    mutating func revoke(reason: String? = nil) {
        isRevoked = true
        revokedAt = Date()
        revokedReason = reason
    }

    mutating func recordUsage() {
        usageCount += 1
        lastUsedAt = Date()
    }
}

// MARK: - Invitation Token

/// Handles secure token generation and validation
struct InvitationToken {
    /// Generate a cryptographically secure token
    static func generate() -> (token: String, hash: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let hash = Self.hash(token)
        return (token, hash)
    }

    /// Hash a token for storage comparison
    static func hash(_ token: String) -> String {
        let data = Data(token.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Validate a token against a stored hash
    static func validate(token: String, against storedHash: String) -> Bool {
        let tokenHash = hash(token)
        return tokenHash == storedHash
    }
}

// MARK: - Shareable Link

/// Creates shareable invitation links
struct InvitationLink {
    static let scheme = "axon"
    static let host = "share"

    /// Create a shareable link from an invitation token
    static func create(token: String, hostId: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/connect"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "host", value: hostId)
        ]
        return components.url
    }

    /// Parse an invitation link
    static func parse(_ url: URL) -> (token: String, hostId: String)? {
        guard url.scheme == scheme,
              url.host == host,
              url.path == "/connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              let hostId = components.queryItems?.first(where: { $0.name == "host" })?.value else {
            return nil
        }
        return (token, hostId)
    }

    /// Create a shareable text description
    static func shareText(guestName: String, hostName: String, expiresIn: String) -> String {
        """
        \(hostName) has invited you to use their AI assistant.

        This invitation expires in \(expiresIn).

        Tap the link below to connect:
        """
    }
}

// MARK: - Guest Session

/// An active session for a connected guest
struct GuestSession: Codable, Identifiable, Equatable {
    let id: String
    let invitationId: String
    let guestDeviceName: String
    let connectedAt: Date
    let capabilities: GuestCapabilities
    let expiresAt: Date

    var queryCount: Int
    var lastQueryAt: Date?
    var disconnectedAt: Date?

    init(
        id: String = UUID().uuidString,
        invitationId: String,
        guestDeviceName: String,
        connectedAt: Date = Date(),
        capabilities: GuestCapabilities,
        expiresAt: Date
    ) {
        self.id = id
        self.invitationId = invitationId
        self.guestDeviceName = guestDeviceName
        self.connectedAt = connectedAt
        self.capabilities = capabilities
        self.expiresAt = expiresAt
        self.queryCount = 0
    }

    var isActive: Bool {
        disconnectedAt == nil && Date() < expiresAt
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var sessionDuration: TimeInterval {
        let endTime = disconnectedAt ?? Date()
        return endTime.timeIntervalSince(connectedAt)
    }

    var formattedSessionDuration: String {
        let duration = sessionDuration
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) minutes"
        }
    }

    mutating func recordQuery() {
        queryCount += 1
        lastQueryAt = Date()
    }

    mutating func disconnect() {
        disconnectedAt = Date()
    }

    /// Check if a query is allowed based on rate limits
    func canQuery(hourlyLimit: Int) -> Bool {
        guard isActive else { return false }

        // Simple hourly rate limiting
        // In production, this would track queries per time window
        return queryCount < hourlyLimit * 24 // Rough daily limit
    }
}

// MARK: - Invitation Creation Result

/// Result of creating an invitation (includes the one-time visible token)
struct InvitationCreationResult {
    let invitation: GuestInvitation
    let token: String
    let shareableLink: URL?
    let qrCodeData: Data?

    var shareText: String {
        InvitationLink.shareText(
            guestName: invitation.guestName,
            hostName: "Your friend",
            expiresIn: invitation.formattedTimeRemaining
        )
    }
}
