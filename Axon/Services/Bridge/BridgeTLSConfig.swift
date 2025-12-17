//
//  BridgeTLSConfig.swift
//  Axon
//
//  TLS configuration helpers for secure WebSocket connections.
//  Supports self-signed certificate validation via fingerprint pinning.
//

import Foundation
import Network
import Security
import CryptoKit

// MARK: - TLS Configuration

/// Helpers for configuring TLS connections with certificate pinning
struct BridgeTLSConfig {

    /// Configure TLS options for a connection with optional certificate pinning
    /// - Parameters:
    ///   - options: The TLS protocol options to configure
    ///   - trustedFingerprints: Array of trusted SHA-256 certificate fingerprints (hex strings)
    ///   - queue: Dispatch queue for verification callbacks
    static func configure(
        _ options: NWProtocolTLS.Options,
        trustedFingerprints: [String],
        queue: DispatchQueue
    ) {
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { (_, trust, completionHandler) in

            // If no fingerprints configured, trust all (user should be on trusted LAN)
            if trustedFingerprints.isEmpty {
                completionHandler(true)
                return
            }

            // Get the server certificate
            guard let serverTrust = sec_trust_copy_ref(trust).takeRetainedValue() as SecTrust? else {
                completionHandler(false)
                return
            }

            // Get the leaf certificate
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
                completionHandler(false)
                return
            }

            // Calculate fingerprint
            let fingerprint = certificateFingerprint(certificate)

            // Check if fingerprint matches any trusted one
            let trusted = trustedFingerprints.contains { $0.lowercased() == fingerprint.lowercased() }

            if trusted {
                print("[BridgeTLS] Certificate fingerprint matched: \(fingerprint.prefix(16))...")
            } else {
                print("[BridgeTLS] Certificate fingerprint not trusted: \(fingerprint)")
            }

            completionHandler(trusted)
        }, queue)
    }

    /// Calculate SHA-256 fingerprint of a certificate
    /// - Parameter certificate: The certificate to fingerprint
    /// - Returns: Hex string of the SHA-256 hash
    static func certificateFingerprint(_ certificate: SecCertificate) -> String {
        let data = SecCertificateCopyData(certificate) as Data
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Parse a certificate fingerprint from common formats
    /// Accepts: "AA:BB:CC:DD...", "AABBCCDD...", "aa:bb:cc:dd...", etc.
    /// - Parameter input: The fingerprint string to normalize
    /// - Returns: Lowercase hex string without separators
    static func normalizeFingerprint(_ input: String) -> String {
        return input
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Format a fingerprint for display (with colons)
    /// - Parameter fingerprint: Raw hex fingerprint
    /// - Returns: Formatted string like "AA:BB:CC:DD:..."
    static func formatFingerprint(_ fingerprint: String) -> String {
        let normalized = normalizeFingerprint(fingerprint).uppercased()
        var formatted = ""
        for (index, char) in normalized.enumerated() {
            if index > 0 && index % 2 == 0 {
                formatted += ":"
            }
            formatted += String(char)
        }
        return formatted
    }

    /// Validate a fingerprint string format
    /// - Parameter fingerprint: The fingerprint to validate
    /// - Returns: true if the fingerprint appears valid (64 hex chars for SHA-256)
    static func isValidFingerprint(_ fingerprint: String) -> Bool {
        let normalized = normalizeFingerprint(fingerprint)
        // SHA-256 = 32 bytes = 64 hex characters
        guard normalized.count == 64 else { return false }
        return normalized.allSatisfy { $0.isHexDigit }
    }
}

// MARK: - Certificate Info

/// Information about a server certificate for display
struct CertificateInfo {
    let fingerprint: String          // SHA-256 hex
    let subject: String              // Common Name or subject
    let issuer: String               // Issuer name
    let validFrom: Date?
    let validTo: Date?
    let isSelfSigned: Bool

    var isExpired: Bool {
        guard let validTo = validTo else { return false }
        return validTo < Date()
    }

    var formattedFingerprint: String {
        BridgeTLSConfig.formatFingerprint(fingerprint)
    }
}

// MARK: - Helper Extensions

extension Character {
    var isHexDigit: Bool {
        return "0123456789abcdefABCDEF".contains(self)
    }
}
