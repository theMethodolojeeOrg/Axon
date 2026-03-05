//
//  BridgeLogService.swift
//  Axon
//
//  Service for capturing and storing VS Code Bridge WebSocket traffic
//  for debugging and inspection purposes.
//

import Foundation
import Combine

// MARK: - Log Entry Model

/// A single log entry representing a WebSocket message
struct BridgeLogEntry: Identifiable, Equatable, Hashable {
    let id: UUID
    let timestamp: Date
    let direction: Direction
    let messageType: MessageType
    let method: String?
    let requestId: String?
    let rawJSON: String
    let prettyJSON: String
    let isValid: Bool
    let validationErrors: [String]

    enum Direction: String, Codable {
        case outgoing = "→"  // Axon to VS Code
        case incoming = "←"  // VS Code to Axon

        var icon: String {
            switch self {
            case .outgoing: return "arrow.up.circle"
            case .incoming: return "arrow.down.circle"
            }
        }

        var label: String {
            switch self {
            case .outgoing: return "Sent"
            case .incoming: return "Received"
            }
        }
    }

    enum MessageType: String, Codable {
        case request = "Request"
        case response = "Response"
        case notification = "Notification"
        case error = "Error"
        case unknown = "Unknown"

        var icon: String {
            switch self {
            case .request: return "arrow.right.circle"
            case .response: return "arrow.left.circle"
            case .notification: return "bell"
            case .error: return "exclamationmark.triangle"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    init(
        direction: Direction,
        rawData: Data,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.direction = direction
        self.rawJSON = String(data: rawData, encoding: .utf8) ?? "(binary data)"

        // Try to parse and validate the JSON
        var parsedMethod: String? = nil
        var parsedRequestId: String? = nil
        var parsedMessageType: MessageType = .unknown
        var jsonValid = true
        var errors: [String] = []
        var pretty = self.rawJSON

        if let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            // Pretty print
            if let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                pretty = prettyString
            }

            // Extract fields
            parsedMethod = json["method"] as? String
            parsedRequestId = json["id"] as? String

            // Determine message type
            if json["error"] != nil {
                parsedMessageType = .error
            } else if json["result"] != nil {
                parsedMessageType = .response
            } else if json["method"] != nil {
                if json["id"] != nil {
                    parsedMessageType = .request
                } else {
                    parsedMessageType = .notification
                }
            }

            // Validate JSON-RPC 2.0 structure
            errors = BridgeLogEntry.validateJSONRPC(json)
            if !errors.isEmpty {
                jsonValid = false
            }
        } else {
            jsonValid = false
            errors = ["Invalid JSON: Unable to parse"]
        }

        self.prettyJSON = pretty
        self.method = parsedMethod
        self.requestId = parsedRequestId
        self.messageType = parsedMessageType
        self.isValid = jsonValid
        self.validationErrors = errors
    }

    /// Validate that the JSON conforms to JSON-RPC 2.0 spec
    private static func validateJSONRPC(_ json: [String: Any]) -> [String] {
        var errors: [String] = []

        // Must have jsonrpc field
        if let jsonrpc = json["jsonrpc"] as? String {
            if jsonrpc != "2.0" {
                errors.append("jsonrpc field should be \"2.0\", got \"\(jsonrpc)\"")
            }
        } else {
            errors.append("Missing required field: jsonrpc")
        }

        // Requests and Responses need id
        let hasMethod = json["method"] != nil
        let hasResult = json["result"] != nil
        let hasError = json["error"] != nil

        if hasResult || hasError {
            // This is a response
            if json["id"] == nil {
                errors.append("Response missing required field: id")
            }
            if hasResult && hasError {
                errors.append("Response cannot have both result and error")
            }
        } else if hasMethod {
            // This is a request or notification
            if let method = json["method"] as? String {
                if method.isEmpty {
                    errors.append("Method cannot be empty")
                }
            } else {
                errors.append("Method must be a string")
            }
        } else {
            errors.append("Message must have method (request/notification) or result/error (response)")
        }

        // Validate error structure if present
        if let error = json["error"] as? [String: Any] {
            if error["code"] == nil {
                errors.append("Error missing required field: code")
            } else if !(error["code"] is Int) {
                errors.append("Error code must be an integer")
            }
            if error["message"] == nil {
                errors.append("Error missing required field: message")
            } else if !(error["message"] is String) {
                errors.append("Error message must be a string")
            }
        }

        return errors
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var summary: String {
        if let method = method {
            return method
        } else if messageType == .response {
            return "Response \(requestId ?? "")"
        } else if messageType == .error {
            return "Error"
        }
        return messageType.rawValue
    }
}

// MARK: - Log Service

@MainActor
class BridgeLogService: ObservableObject {
    static let shared = BridgeLogService()

    // MARK: - Published State

    @Published private(set) var entries: [BridgeLogEntry] = []
    @Published var isLoggingEnabled: Bool = true
    @Published var maxEntries: Int = 500

    // MARK: - Filtering

    @Published var filterText: String = ""
    @Published var showIncoming: Bool = true
    @Published var showOutgoing: Bool = true
    @Published var showRequests: Bool = true
    @Published var showResponses: Bool = true
    @Published var showNotifications: Bool = true
    @Published var showErrors: Bool = true
    @Published var onlyShowInvalid: Bool = false

    var filteredEntries: [BridgeLogEntry] {
        entries.filter { entry in
            // Direction filter
            if entry.direction == .incoming && !showIncoming { return false }
            if entry.direction == .outgoing && !showOutgoing { return false }

            // Message type filter
            switch entry.messageType {
            case .request: if !showRequests { return false }
            case .response: if !showResponses { return false }
            case .notification: if !showNotifications { return false }
            case .error: if !showErrors { return false }
            case .unknown: break
            }

            // Validity filter
            if onlyShowInvalid && entry.isValid { return false }

            // Text filter
            if !filterText.isEmpty {
                let searchText = filterText.lowercased()
                let matchesMethod = entry.method?.lowercased().contains(searchText) ?? false
                let matchesJSON = entry.rawJSON.lowercased().contains(searchText)
                let matchesId = entry.requestId?.lowercased().contains(searchText) ?? false
                if !matchesMethod && !matchesJSON && !matchesId { return false }
            }

            return true
        }
    }

    private init() {}

    // MARK: - Logging Methods

    /// Log an outgoing message (Axon → VS Code)
    func logOutgoing(_ data: Data) {
        guard isLoggingEnabled else { return }

        let entry = BridgeLogEntry(direction: .outgoing, rawData: data)
        addEntry(entry)
    }

    /// Log an incoming message (VS Code → Axon)
    func logIncoming(_ data: Data) {
        guard isLoggingEnabled else { return }

        let entry = BridgeLogEntry(direction: .incoming, rawData: data)
        addEntry(entry)
    }

    private func addEntry(_ entry: BridgeLogEntry) {
        entries.insert(entry, at: 0)

        // Trim old entries if over limit
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    // MARK: - Management

    func clear() {
        entries.removeAll()
    }

    func export() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportData = entries.map { entry -> [String: Any] in
            return [
                "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                "direction": entry.direction.rawValue,
                "messageType": entry.messageType.rawValue,
                "method": entry.method as Any,
                "requestId": entry.requestId as Any,
                "isValid": entry.isValid,
                "validationErrors": entry.validationErrors,
                "json": entry.rawJSON
            ]
        }

        if let data = try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return "[]"
    }

    // MARK: - Statistics

    var requestCount: Int {
        entries.filter { $0.messageType == .request }.count
    }

    var responseCount: Int {
        entries.filter { $0.messageType == .response }.count
    }

    var errorCount: Int {
        entries.filter { $0.messageType == .error || !$0.isValid }.count
    }

    var invalidCount: Int {
        entries.filter { !$0.isValid }.count
    }
}
