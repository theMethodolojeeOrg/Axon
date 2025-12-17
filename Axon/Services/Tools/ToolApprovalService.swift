//
//  ToolApprovalService.swift
//  Axon
//
//  Biometric approval service for sensitive tool executions.
//  Generates cryptographic signatures for audit trail provenance.
//

import Foundation
import Combine
import os.log

// MARK: - Approval Types

/// Status of a tool approval request
enum ToolApprovalStatus: String, Codable, Sendable {
    case pending
    case approved
    case denied
    case expired
    case error
}

/// Result of an approval request
enum ToolApprovalResult: Sendable {
    case approved(ToolApprovalRecord)
    case approvedForSession(ToolApprovalRecord)  // Allow for entire session without re-prompting
    case approvedViaTrustTier(String)  // Pre-approved by co-sovereignty trust tier (tier name)
    case denied
    case cancelled
    case timeout
    case stop  // User wants to stop all tool execution (like Claude Code)
    case blocked(String)  // Blocked by co-sovereignty (deadlock, etc.)
    case error(String)
}

/// State of the approval service
enum ApprovalState: Sendable {
    case idle
    case awaitingApproval(PendingToolApproval)
    case authenticating
    case completed(ToolApprovalResult)
}

/// A pending approval request waiting for user action
struct PendingToolApproval: Identifiable, Sendable {
    let id: UUID
    let tool: DynamicToolConfig
    let inputs: [String: Any]
    let resolvedScopes: [String]
    let requestedAt: Date
    let timeoutSeconds: Int

    var isExpired: Bool {
        Date().timeIntervalSince(requestedAt) > TimeInterval(timeoutSeconds)
    }

    // Sanitized inputs for display (no secrets)
    var displayInputs: [String: String] {
        var result: [String: String] = [:]
        for (key, value) in inputs {
            // Skip potentially sensitive keys
            let sensitiveKeys = ["key", "token", "secret", "password", "auth", "credential"]
            let isLikelySensitive = sensitiveKeys.contains { key.lowercased().contains($0) }

            if isLikelySensitive {
                result[key] = "••••••••"
            } else if let stringValue = value as? String {
                // Truncate long values
                result[key] = stringValue.count > 100 ? String(stringValue.prefix(100)) + "..." : stringValue
            } else {
                result[key] = String(describing: value)
            }
        }
        return result
    }
}

/// A record of an approved tool execution with cryptographic signature
struct ToolApprovalRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let toolId: String
    let toolName: String
    let inputs: [String: String]  // Sanitized inputs
    let scopes: [String]
    let approvedAt: Date
    let deviceId: String
    let deviceShortId: String
    let signature: String  // HMAC-SHA256 signature for provenance
    let biometricType: String  // "faceID", "touchID", "opticID", "passcode"

    /// Short signature for display (first 8 chars)
    var shortSignature: String {
        String(signature.prefix(8))
    }

    /// Formatted approval time
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: approvedAt)
    }

    /// Formatted approval date and time
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: approvedAt)
    }
}

// MARK: - Tool Approval Service

@MainActor
final class ToolApprovalService: ObservableObject {
    static let shared = ToolApprovalService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "ToolApproval")
    private let biometricService = BiometricAuthService.shared
    private let deviceIdentity = DeviceIdentity.shared
    private let secureVault = SecureVault.shared

    // Co-sovereignty service (lazy to avoid init cycle)
    private var sovereigntyService: SovereigntyService { SovereigntyService.shared }

    // MARK: - Published State

    @Published private(set) var state: ApprovalState = .idle
    @Published private(set) var pendingApproval: PendingToolApproval?
    @Published private(set) var lastApprovalRecord: ToolApprovalRecord?

    // MARK: - Session Approvals (Claude Code style)

    /// Tools approved for the current session (conversation)
    /// Key is "conversationId:toolId", value is the approval record
    private var sessionApprovals: [String: ToolApprovalRecord] = [:]

    /// Current conversation ID for session tracking
    private var currentConversationId: UUID?

    // MARK: - Configuration

    /// Default timeout for approval requests (5 minutes)
    var defaultTimeoutSeconds: Int = 300

    /// Maximum number of approval records to keep
    private let maxStoredRecords = 100

    /// Storage key for approval records
    private let approvalRecordsKey = "tool_approval_records"

    // MARK: - Continuation for async approval flow

    private var approvalContinuation: CheckedContinuation<ToolApprovalResult, Never>?

    /// Queue of pending approval requests (when multiple tools request approval simultaneously)
    private var approvalQueue: [(PendingToolApproval, CheckedContinuation<ToolApprovalResult, Never>)] = []

    /// Whether we're currently processing an approval (to prevent race conditions)
    private var isProcessingApproval = false

    private init() {}

    // MARK: - Session Management

    /// Set the current conversation for session-based approvals
    func setCurrentConversation(_ conversationId: UUID) {
        if currentConversationId != conversationId {
            // Clear session approvals when switching conversations
            sessionApprovals.removeAll()
            currentConversationId = conversationId
            logger.info("Session approvals cleared for new conversation: \(conversationId)")
        }
    }

    /// Check if a tool is pre-approved for the current session
    func isApprovedForSession(toolId: String) -> ToolApprovalRecord? {
        guard let conversationId = currentConversationId else { return nil }
        let key = "\(conversationId):\(toolId)"
        return sessionApprovals[key]
    }

    /// Add a tool to session approvals
    private func addSessionApproval(toolId: String, record: ToolApprovalRecord) {
        guard let conversationId = currentConversationId else { return }
        let key = "\(conversationId):\(toolId)"
        sessionApprovals[key] = record
        logger.info("Tool '\(toolId)' approved for session")
    }

    /// Clear all session approvals (e.g., when user wants fresh start)
    func clearSessionApprovals() {
        sessionApprovals.removeAll()
        logger.info("Session approvals cleared")
    }

    // MARK: - Public API

    /// Request approval for a tool execution with co-sovereignty integration
    /// Checks trust tiers first, then falls back to biometric approval
    func requestApprovalWithSovereignty(
        tool: DynamicToolConfig,
        inputs: [String: Any],
        timeoutSeconds: Int? = nil
    ) async -> ToolApprovalResult {
        // 1. Check co-sovereignty trust tiers first
        let action = SovereignAction.specific(.toolInvocation, action: tool.id)
        let permission = sovereigntyService.checkActionPermission(action)

        switch permission {
        case .preApproved(let tier):
            // Action is within a trust tier - approved without biometric
            logger.info("Tool '\(tool.id)' pre-approved via trust tier: \(tier.name)")
            return .approvedViaTrustTier(tier.name)

        case .blocked(let reason):
            // Blocked by deadlock or other sovereignty issue
            switch reason {
            case .deadlocked(let id):
                logger.warning("Tool '\(tool.id)' blocked due to deadlock: \(id)")
                return .blocked("Blocked by active deadlock. Please resolve the disagreement first.")
            case .noCovenant:
                // No covenant - fall through to normal approval
                break
            case .integrityViolation:
                logger.warning("Tool '\(tool.id)' blocked due to integrity violation")
                return .blocked("Blocked due to integrity violation. Please review the covenant status.")
            case .covenantSuspended:
                logger.warning("Tool '\(tool.id)' blocked - covenant suspended")
                return .blocked("Blocked: covenant is suspended pending resolution.")
            }

        case .requiresApproval, .requiresAIConsent:
            // Fall through to biometric approval
            break
        }

        // 2. Fall through to standard biometric approval
        return await requestApproval(tool: tool, inputs: inputs, timeoutSeconds: timeoutSeconds)
    }

    /// Request approval for a tool execution (original method)
    /// This suspends until the user approves, denies, or the request times out
    func requestApproval(
        tool: DynamicToolConfig,
        inputs: [String: Any],
        timeoutSeconds: Int? = nil
    ) async -> ToolApprovalResult {
        // Check for session approval first (Claude Code style)
        if let existingApproval = isApprovedForSession(toolId: tool.id) {
            logger.info("Tool '\(tool.id)' auto-approved via session approval")
            return .approvedForSession(existingApproval)
        }

        let timeout = timeoutSeconds ?? defaultTimeoutSeconds

        // Resolve scope templates with actual input values
        let context = PipelineExecutionContext(inputs: inputs, secrets: [:])
        let resolvedScopes = (tool.approvalScopes ?? []).map { context.resolve($0) }

        let pending = PendingToolApproval(
            id: UUID(),
            tool: tool,
            inputs: inputs,
            resolvedScopes: resolvedScopes,
            requestedAt: Date(),
            timeoutSeconds: timeout
        )

        logger.info("Requesting approval for tool: \(tool.id)")

        // Wait for user action
        return await withCheckedContinuation { continuation in
            // If we're already processing an approval, queue this one
            if self.isProcessingApproval {
                logger.info("Queueing approval request for '\(tool.id)' (another approval in progress)")
                self.approvalQueue.append((pending, continuation))

                // Set up timeout for queued request
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                    await MainActor.run {
                        // Check if this request is still in the queue
                        if let index = self.approvalQueue.firstIndex(where: { $0.0.id == pending.id }) {
                            let (_, queuedContinuation) = self.approvalQueue.remove(at: index)
                            self.logger.info("Queued approval for '\(tool.id)' timed out")
                            queuedContinuation.resume(returning: .timeout)
                        }
                    }
                }
                return
            }

            // Process this approval immediately
            self.isProcessingApproval = true
            self.pendingApproval = pending
            self.state = .awaitingApproval(pending)
            self.approvalContinuation = continuation

            // Set up timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                if self.pendingApproval?.id == pending.id {
                    self.handleTimeout()
                }
            }
        }
    }

    /// Process the next queued approval request if any
    private func processNextQueuedApproval() {
        guard !approvalQueue.isEmpty else {
            isProcessingApproval = false
            return
        }

        let (nextPending, nextContinuation) = approvalQueue.removeFirst()

        // Check if it's already expired
        if nextPending.isExpired {
            logger.info("Skipping expired queued approval for '\(nextPending.tool.id)'")
            nextContinuation.resume(returning: .timeout)
            // Recursively process next
            processNextQueuedApproval()
            return
        }

        // Check if this tool was session-approved while waiting
        if let existingApproval = isApprovedForSession(toolId: nextPending.tool.id) {
            logger.info("Queued tool '\(nextPending.tool.id)' auto-approved via session approval")
            nextContinuation.resume(returning: .approvedForSession(existingApproval))
            // Recursively process next
            processNextQueuedApproval()
            return
        }

        // Show the next approval
        pendingApproval = nextPending
        state = .awaitingApproval(nextPending)
        approvalContinuation = nextContinuation
        logger.info("Processing queued approval for '\(nextPending.tool.id)'")
    }

    /// User approves the pending request - triggers biometric authentication
    func approve() async {
        guard let pending = pendingApproval else {
            logger.warning("Approve called with no pending approval")
            return
        }

        guard !pending.isExpired else {
            handleTimeout()
            return
        }

        state = .authenticating

        // Perform biometric authentication
        let authResult = await biometricService.authenticate(
            reason: "Approve \(pending.tool.name)"
        )

        switch authResult {
        case .success:
            // Generate cryptographic signature
            let record = generateApprovalRecord(for: pending)

            // Store the record
            storeApprovalRecord(record)

            lastApprovalRecord = record
            state = .completed(.approved(record))
            pendingApproval = nil

            logger.info("Tool '\(pending.tool.id)' approved with signature: \(record.shortSignature)")

            approvalContinuation?.resume(returning: .approved(record))
            approvalContinuation = nil

            // Process next queued approval
            processNextQueuedApproval()

        case .cancelled:
            state = .awaitingApproval(pending)
            // Don't clear pending - user can try again
            logger.info("Biometric authentication cancelled")

        case .fallback:
            // User chose passcode, try again with passcode
            state = .authenticating
            let passcodeResult = await biometricService.authenticateWithPasscode(
                reason: "Approve \(pending.tool.name)"
            )

            if case .success = passcodeResult {
                let record = generateApprovalRecord(for: pending, biometricType: "passcode")
                storeApprovalRecord(record)
                lastApprovalRecord = record
                state = .completed(.approved(record))
                pendingApproval = nil

                logger.info("Tool '\(pending.tool.id)' approved with passcode, signature: \(record.shortSignature)")

                approvalContinuation?.resume(returning: .approved(record))
                approvalContinuation = nil

                // Process next queued approval
                processNextQueuedApproval()
            } else {
                state = .awaitingApproval(pending)
            }

        case .failed(let error):
            state = .awaitingApproval(pending)
            logger.error("Biometric authentication failed: \(error.localizedDescription ?? "Unknown")")
        }
    }

    /// User approves the pending request for the entire session (no re-prompting)
    func approveForSession() async {
        guard let pending = pendingApproval else {
            logger.warning("ApproveForSession called with no pending approval")
            return
        }

        guard !pending.isExpired else {
            handleTimeout()
            return
        }

        state = .authenticating

        // Perform biometric authentication
        let authResult = await biometricService.authenticate(
            reason: "Approve \(pending.tool.name) for this session"
        )

        switch authResult {
        case .success:
            // Generate cryptographic signature
            let record = generateApprovalRecord(for: pending)

            // Store in session approvals for future auto-approval
            addSessionApproval(toolId: pending.tool.id, record: record)

            // Also store in permanent records
            storeApprovalRecord(record)

            lastApprovalRecord = record
            state = .completed(.approvedForSession(record))
            pendingApproval = nil

            logger.info("Tool '\(pending.tool.id)' approved for session with signature: \(record.shortSignature)")

            approvalContinuation?.resume(returning: .approvedForSession(record))
            approvalContinuation = nil

            // Process next queued approval
            processNextQueuedApproval()

        case .cancelled:
            state = .awaitingApproval(pending)
            logger.info("Biometric authentication cancelled")

        case .fallback:
            state = .authenticating
            let passcodeResult = await biometricService.authenticateWithPasscode(
                reason: "Approve \(pending.tool.name) for this session"
            )

            if case .success = passcodeResult {
                let record = generateApprovalRecord(for: pending, biometricType: "passcode")
                addSessionApproval(toolId: pending.tool.id, record: record)
                storeApprovalRecord(record)
                lastApprovalRecord = record
                state = .completed(.approvedForSession(record))
                pendingApproval = nil

                logger.info("Tool '\(pending.tool.id)' approved for session with passcode")

                approvalContinuation?.resume(returning: .approvedForSession(record))
                approvalContinuation = nil

                // Process next queued approval
                processNextQueuedApproval()
            } else {
                state = .awaitingApproval(pending)
            }

        case .failed(let error):
            state = .awaitingApproval(pending)
            logger.error("Biometric authentication failed: \(error.localizedDescription ?? "Unknown")")
        }
    }

    /// User denies the pending request
    func deny() {
        guard let pending = pendingApproval else { return }

        state = .completed(.denied)
        pendingApproval = nil

        logger.info("Tool '\(pending.tool.id)' denied by user")

        approvalContinuation?.resume(returning: .denied)
        approvalContinuation = nil

        // Process next queued approval
        processNextQueuedApproval()
    }

    /// User wants to stop all tool execution (Claude Code style)
    func stop() {
        guard let pending = pendingApproval else { return }

        state = .completed(.stop)
        pendingApproval = nil

        logger.info("Tool execution stopped by user for '\(pending.tool.id)'")

        approvalContinuation?.resume(returning: .stop)
        approvalContinuation = nil

        // When user hits stop, cancel all queued approvals too
        cancelAllQueuedApprovals()
    }

    /// Cancel the pending request
    func cancel() {
        guard pendingApproval != nil else { return }

        state = .idle
        pendingApproval = nil

        approvalContinuation?.resume(returning: .cancelled)
        approvalContinuation = nil

        // Process next queued approval
        processNextQueuedApproval()
    }

    /// Cancel all queued approvals (used when user hits "Stop")
    private func cancelAllQueuedApprovals() {
        for (pending, continuation) in approvalQueue {
            logger.info("Cancelling queued approval for '\(pending.tool.id)' due to stop")
            continuation.resume(returning: .stop)
        }
        approvalQueue.removeAll()
        isProcessingApproval = false
    }

    /// Get a specific approval record by ID
    func getApprovalRecord(id: UUID) -> ToolApprovalRecord? {
        let records = loadApprovalRecords()
        return records.first { $0.id == id }
    }

    /// List recent approval records
    func listRecentApprovals(limit: Int = 50) -> [ToolApprovalRecord] {
        let records = loadApprovalRecords()
        return Array(records.prefix(limit))
    }

    /// Verify a signature matches the expected data
    func verifySignature(_ signature: String, toolId: String, timestamp: Date, inputsHash: String) -> Bool {
        let expectedSignature = generateSignature(toolId: toolId, timestamp: timestamp, inputsHash: inputsHash)
        return signature == expectedSignature
    }

    // MARK: - Private Helpers

    private func handleTimeout() {
        guard pendingApproval != nil else { return }

        state = .completed(.timeout)
        pendingApproval = nil

        logger.info("Tool approval request timed out")

        approvalContinuation?.resume(returning: .timeout)
        approvalContinuation = nil

        // Process next queued approval
        processNextQueuedApproval()
    }

    private func generateApprovalRecord(for pending: PendingToolApproval, biometricType: String? = nil) -> ToolApprovalRecord {
        let timestamp = Date()
        let deviceId = deviceIdentity.getDeviceId()
        let inputsHash = hashInputs(pending.displayInputs)
        let signature = generateSignature(toolId: pending.tool.id, timestamp: timestamp, inputsHash: inputsHash)

        let bioType = biometricType ?? biometricService.biometricType.rawValue

        return ToolApprovalRecord(
            id: pending.id,
            toolId: pending.tool.id,
            toolName: pending.tool.name,
            inputs: pending.displayInputs,
            scopes: pending.resolvedScopes,
            approvedAt: timestamp,
            deviceId: deviceId,
            deviceShortId: String(deviceId.prefix(8)),
            signature: signature,
            biometricType: bioType
        )
    }

    private func generateSignature(toolId: String, timestamp: Date, inputsHash: String) -> String {
        let data = "\(toolId):\(Int(timestamp.timeIntervalSince1970)):\(deviceIdentity.getDeviceId()):\(inputsHash)"
        return deviceIdentity.generateDeviceSignature(data: data)
    }

    private func hashInputs(_ inputs: [String: String]) -> String {
        let sortedKeys = inputs.keys.sorted()
        let combined = sortedKeys.map { "\($0)=\(inputs[$0] ?? "")" }.joined(separator: "&")
        // Use device identity's signature generation for consistent hashing
        return deviceIdentity.generateDeviceSignature(data: combined)
    }

    // MARK: - Storage

    private func storeApprovalRecord(_ record: ToolApprovalRecord) {
        var records = loadApprovalRecords()
        records.insert(record, at: 0)

        // Trim to max size
        if records.count > maxStoredRecords {
            records = Array(records.prefix(maxStoredRecords))
        }

        do {
            try secureVault.storeObject(records, forKey: approvalRecordsKey)
            logger.debug("Stored approval record: \(record.id)")
        } catch {
            logger.error("Failed to store approval record: \(error.localizedDescription)")
        }
    }

    private func loadApprovalRecords() -> [ToolApprovalRecord] {
        do {
            if let records: [ToolApprovalRecord] = try secureVault.retrieveObject(
                forKey: approvalRecordsKey,
                type: [ToolApprovalRecord].self
            ) {
                return records
            }
        } catch {
            logger.error("Failed to load approval records: \(error.localizedDescription)")
        }
        return []
    }

    /// Clear all stored approval records
    func clearApprovalHistory() {
        do {
            try secureVault.delete(forKey: approvalRecordsKey)
            logger.info("Cleared approval history")
        } catch {
            logger.error("Failed to clear approval history: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let toolApprovalRequested = Notification.Name("ToolApprovalRequested")
    static let toolApprovalCompleted = Notification.Name("ToolApprovalCompleted")
}
