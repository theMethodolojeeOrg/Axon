//
//  ShortcutInvocationService.swift
//  Axon
//
//  Service for invoking external apps via URL schemes with approval flow.
//  Integrates with ToolApprovalService for session-based trust.
//

import Foundation
import SwiftUI
import Combine
import os.log

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shortcut Invocation Service

@MainActor
final class ShortcutInvocationService: ObservableObject {
    static let shared = ShortcutInvocationService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "ShortcutInvocation")
    private let portRegistry = PortRegistry.shared
    private let toolApprovalService = ToolApprovalService.shared

    // MARK: - Published State

    /// Current pending invocation request (for approval UI)
    @Published private(set) var pendingRequest: PortInvocationRequest?

    /// History of invocations for this session
    @Published private(set) var invocationHistory: [PortInvocationRecord] = []

    // MARK: - Session Approvals

    /// Ports approved for the current session (tool approval integration)
    /// Key is "conversationId:portId", value is when it was approved
    private var sessionApprovals: [String: Date] = [:]

    /// Current conversation ID for session tracking
    private var currentConversationId: UUID?

    // MARK: - Continuation for async approval

    private var invocationContinuation: CheckedContinuation<PortApprovalResult, Never>?

    private init() {}

    // MARK: - Session Management

    /// Set the current conversation for session-based approvals
    func setCurrentConversation(_ conversationId: UUID) {
        if currentConversationId != conversationId {
            sessionApprovals.removeAll()
            currentConversationId = conversationId
            logger.info("Port session approvals cleared for new conversation")
        }
    }

    /// Check if a port is pre-approved for the current session
    func isApprovedForSession(portId: String) -> Bool {
        guard let conversationId = currentConversationId else { return false }
        let key = "\(conversationId):\(portId)"
        return sessionApprovals[key] != nil
    }

    /// Add a port to session approvals
    private func addSessionApproval(portId: String) {
        guard let conversationId = currentConversationId else { return }
        let key = "\(conversationId):\(portId)"
        sessionApprovals[key] = Date()
        logger.info("Port '\(portId)' approved for session")
    }

    /// Clear all session approvals
    func clearSessionApprovals() {
        sessionApprovals.removeAll()
        logger.info("Port session approvals cleared")
    }

    // MARK: - Public API

    /// Invoke a port by ID with given parameters
    /// Returns the result after approval and invocation
    func invokePort(
        portId: String,
        parameters: [String: String],
        requiresApproval: Bool = true
    ) async -> PortInvocationResult {
        // 1. Find the port
        guard let port = portRegistry.port(id: portId) else {
            logger.error("Port not found: \(portId)")
            return .error("Port '\(portId)' not found")
        }

        // 2. Check if port is enabled
        guard port.isEnabled else {
            logger.warning("Port is disabled: \(portId)")
            return .error("Port '\(portId)' is disabled")
        }

        // 3. Validate required parameters
        let missingParams = port.parameters
            .filter { $0.isRequired }
            .filter { parameters[$0.name] == nil || parameters[$0.name]?.isEmpty == true }
            .map { $0.name }

        if !missingParams.isEmpty {
            logger.warning("Missing required parameters for \(portId): \(missingParams)")
            return .invalidParameters(missing: missingParams)
        }

        // 4. Check if app is installed (if scheme is specified)
        if let scheme = port.appScheme, !portRegistry.isAppInstalled(scheme: scheme) {
            logger.info("App not installed for port \(portId), scheme: \(scheme)")
            return .appNotInstalled(appStoreUrl: port.appStoreUrl)
        }

        // 5. Check session approval
        if requiresApproval && !isApprovedForSession(portId: portId) {
            // Request approval
            let result = await requestApproval(port: port, parameters: parameters)

            switch result {
            case .approved, .approvedForSession:
                // Continue to invocation
                break
            case .denied:
                return .userCancelled
            case .timeout:
                return .error("Approval request timed out")
            default:
                return .userCancelled
            }
        }

        // 6. Generate URL and invoke
        guard let url = port.generateUrl(with: parameters) else {
            logger.error("Failed to generate URL for port: \(portId)")
            return .urlGenerationFailed
        }

        // 7. Open the URL
        let success = await openUrl(url)
        if success {
            // Record the invocation
            recordInvocation(port: port, parameters: parameters, url: url)
            return .success(url: url)
        } else {
            return .error("Failed to open URL: \(url.absoluteString)")
        }
    }

    /// Invoke a shortcut by name
    func invokeShortcut(name: String, input: String? = nil, requiresApproval: Bool = true) async -> PortInvocationResult {
        // Find or create a port entry for this shortcut
        let shortcutPortId = "shortcuts_run"

        var parameters: [String: String] = ["name": name]
        if let input = input {
            parameters["input"] = input
        }

        return await invokePort(portId: shortcutPortId, parameters: parameters, requiresApproval: requiresApproval)
    }

    /// Search and invoke - find a matching port and invoke it
    func searchAndInvoke(query: String, parameters: [String: String]) async -> PortInvocationResult {
        let matchingPorts = portRegistry.searchPorts(query: query)

        guard let bestMatch = matchingPorts.first else {
            return .error("No port found matching '\(query)'")
        }

        return await invokePort(portId: bestMatch.id, parameters: parameters)
    }

    // MARK: - Approval Flow

    private func requestApproval(port: PortRegistryEntry, parameters: [String: String]) async -> PortApprovalResult {
        let request = PortInvocationRequest(port: port, parameters: parameters)
        pendingRequest = request

        logger.info("Requesting approval for port: \(port.id)")

        return await withCheckedContinuation { continuation in
            self.invocationContinuation = continuation

            // Timeout after 2 minutes
            Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                if self.pendingRequest?.id == request.id {
                    self.handleTimeout()
                }
            }
        }
    }

    /// User approves the pending request (one-time)
    func approve() {
        guard let request = pendingRequest else {
            logger.warning("Approve called with no pending request")
            return
        }

        pendingRequest = nil
        logger.info("Port '\(request.port.id)' approved")

        invocationContinuation?.resume(returning: .approved)
        invocationContinuation = nil
    }

    /// User approves for the entire session
    func approveForSession() {
        guard let request = pendingRequest else {
            logger.warning("ApproveForSession called with no pending request")
            return
        }

        addSessionApproval(portId: request.port.id)
        pendingRequest = nil
        logger.info("Port '\(request.port.id)' approved for session")

        invocationContinuation?.resume(returning: .approvedForSession)
        invocationContinuation = nil
    }

    /// User denies the request
    func deny() {
        guard let request = pendingRequest else { return }

        pendingRequest = nil
        logger.info("Port '\(request.port.id)' denied")

        invocationContinuation?.resume(returning: .denied)
        invocationContinuation = nil
    }

    /// Cancel the pending request
    func cancel() {
        guard pendingRequest != nil else { return }

        pendingRequest = nil
        invocationContinuation?.resume(returning: .cancelled)
        invocationContinuation = nil
    }

    private func handleTimeout() {
        guard pendingRequest != nil else { return }

        pendingRequest = nil
        logger.info("Port approval request timed out")

        invocationContinuation?.resume(returning: .timeout)
        invocationContinuation = nil
    }

    // MARK: - URL Opening

    private func openUrl(_ url: URL) async -> Bool {
        #if canImport(UIKit)
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
        #elseif canImport(AppKit)
        // macOS fallback
        return NSWorkspace.shared.open(url)
        #else
        // Unsupported platform
        return false
        #endif
    }

    // MARK: - Invocation History

    private func recordInvocation(port: PortRegistryEntry, parameters: [String: String], url: URL) {
        let record = PortInvocationRecord(
            id: UUID(),
            portId: port.id,
            portName: port.name,
            appName: port.appName,
            parameters: parameters,
            url: url.absoluteString,
            invokedAt: Date()
        )

        invocationHistory.insert(record, at: 0)

        // Keep only last 100 records
        if invocationHistory.count > 100 {
            invocationHistory = Array(invocationHistory.prefix(100))
        }

        logger.info("Recorded invocation for \(port.id)")
    }

    /// Clear invocation history
    func clearHistory() {
        invocationHistory.removeAll()
        logger.info("Invocation history cleared")
    }
}

// MARK: - Supporting Types

/// Result of port approval request
enum PortApprovalResult {
    case approved
    case approvedForSession
    case denied
    case cancelled
    case timeout
}

/// Record of a port invocation
struct PortInvocationRecord: Identifiable, Codable {
    let id: UUID
    let portId: String
    let portName: String
    let appName: String
    let parameters: [String: String]
    let url: String
    let invokedAt: Date

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: invokedAt)
    }
}

// MARK: - AI Tool Integration

extension ShortcutInvocationService {
    /// Parse tool query string into port ID and parameters
    /// Format: "port_id | param1=value1 | param2=value2"
    /// Or: "port_id param1=value1 param2=value2"
    func parseToolQuery(_ query: String) -> (portId: String, parameters: [String: String])? {
        let parts: [String]
        if query.contains("|") {
            parts = query.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            // Try space-separated format
            parts = query.split(separator: " ", maxSplits: 1).map { String($0) }
        }

        guard !parts.isEmpty else { return nil }

        let portId = parts[0].trimmingCharacters(in: .whitespaces)
        var parameters: [String: String] = [:]

        // Parse remaining parts as key=value pairs
        for i in 1..<parts.count {
            let paramParts = parts[i].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            for paramPart in paramParts {
                if let eqIndex = paramPart.firstIndex(of: "=") {
                    let key = String(paramPart[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(paramPart[paramPart.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                    parameters[key] = value
                }
            }
        }

        return (portId, parameters)
    }

    /// Execute a tool invocation from AI query
    func executeToolQuery(_ query: String) async -> String {
        guard let (portId, parameters) = parseToolQuery(query) else {
            return "Error: Invalid query format. Use: port_id | param1=value1 | param2=value2"
        }

        let result = await invokePort(portId: portId, parameters: parameters)

        switch result {
        case .success(let url):
            return "Successfully opened \(portId). URL: \(url.absoluteString)"

        case .appNotInstalled(let appStoreUrl):
            if let storeUrl = appStoreUrl {
                return "App not installed. Install from: \(storeUrl)"
            } else {
                return "App not installed."
            }

        case .invalidParameters(let missing):
            let port = portRegistry.port(id: portId)
            let paramHelp = port?.parameters.map { "\($0.name): \($0.description)" }.joined(separator: "\n") ?? ""
            return "Missing required parameters: \(missing.joined(separator: ", "))\n\nAvailable parameters:\n\(paramHelp)"

        case .urlGenerationFailed:
            return "Failed to generate URL for \(portId)"

        case .userCancelled:
            return "User declined to invoke \(portId)"

        case .error(let message):
            return "Error: \(message)"
        }
    }
}
