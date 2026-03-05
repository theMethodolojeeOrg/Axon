//
//  BridgeConnectionQRParser.swift
//  Axon
//
//  Parses bridge QR payloads into normalized connection profile values.
//

import Foundation

struct BridgeConnectionQRImportResult: Equatable, Sendable {
    let suggestedName: String
    let host: String
    let port: UInt16
    let tlsEnabled: Bool
    let pairingToken: String?

    var addressDisplay: String {
        let scheme = tlsEnabled ? "wss" : "ws"
        return "\(scheme)://\(host):\(port)"
    }
}

enum BridgeConnectionQRParseError: LocalizedError, Equatable {
    case emptyPayload
    case invalidURL
    case unsupportedScheme(String?)
    case missingHost
    case missingPort
    case invalidPort
    case portOutOfRange(Int)

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "QR payload is empty."
        case .invalidURL:
            return "Invalid QR payload. Expected a WebSocket URL."
        case .unsupportedScheme(let scheme):
            if let scheme, !scheme.isEmpty {
                return "Unsupported URL scheme '\(scheme)'. Use ws:// or wss://."
            }
            return "Unsupported URL scheme. Use ws:// or wss://."
        case .missingHost:
            return "Missing host in URL."
        case .missingPort:
            return "Missing port in URL."
        case .invalidPort:
            return "Invalid port in URL."
        case .portOutOfRange(let port):
            return "Port \(port) is out of range. Use 1 to 65535."
        }
    }
}

enum BridgeConnectionQRParser {
    static func parse(_ rawPayload: String) throws -> BridgeConnectionQRImportResult {
        let payload = rawPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            throw BridgeConnectionQRParseError.emptyPayload
        }

        guard let components = URLComponents(string: payload) else {
            throw BridgeConnectionQRParseError.invalidURL
        }

        guard let scheme = components.scheme?.lowercased() else {
            throw BridgeConnectionQRParseError.invalidURL
        }

        guard scheme == "ws" || scheme == "wss" else {
            throw BridgeConnectionQRParseError.unsupportedScheme(components.scheme)
        }

        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            throw BridgeConnectionQRParseError.missingHost
        }

        guard let rawPort = components.port else {
            throw BridgeConnectionQRParseError.missingPort
        }

        guard rawPort > 0 else {
            throw BridgeConnectionQRParseError.invalidPort
        }

        guard rawPort <= 65535 else {
            throw BridgeConnectionQRParseError.portOutOfRange(rawPort)
        }

        guard let port = UInt16(exactly: rawPort) else {
            throw BridgeConnectionQRParseError.invalidPort
        }

        let pairingToken = components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("pairingToken") == .orderedSame })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = pairingToken?.isEmpty == true ? nil : pairingToken

        return BridgeConnectionQRImportResult(
            suggestedName: "Bridge \(host)",
            host: host,
            port: port,
            tlsEnabled: scheme == "wss",
            pairingToken: normalizedToken
        )
    }
}
