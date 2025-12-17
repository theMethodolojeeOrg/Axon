//
//  GuestSharingService.swift
//  Axon
//
//  Created by Tom on 2025.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Guest Sharing Service

/// Core service for managing AI sharing with friends
/// Implements joint consent model requiring both host and AI approval
@MainActor
final class GuestSharingService: ObservableObject {
    static let shared = GuestSharingService()

    // MARK: - Published State

    @Published var pendingRequests: [SharingRequest] = []
    @Published var activeNegotiations: [SharingNegotiation] = []
    @Published var activeInvitations: [GuestInvitation] = []
    @Published var activeSessions: [GuestSession] = []
    @Published var sharingEnabled: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: SharingError?

    // MARK: - Private Properties

    private let storageKey = "guest_sharing_data"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        loadPersistedData()
        setupObservers()
    }

    // MARK: - Request Handling (Guest → Host)

    /// Receive a new access request from a guest
    func receiveRequest(_ request: SharingRequest) {
        guard sharingEnabled else {
            print("[GuestSharingService] Sharing disabled, ignoring request from \(request.guestName)")
            return
        }

        // Check if we already have a pending request from this device
        if pendingRequests.contains(where: { $0.guestDeviceId == request.guestDeviceId && !$0.status.isTerminal }) {
            print("[GuestSharingService] Duplicate request from \(request.guestDeviceId), ignoring")
            return
        }

        pendingRequests.append(request)
        persistData()

        // Notify the host
        NotificationCenter.default.post(
            name: .newSharingRequestReceived,
            object: request
        )

        print("[GuestSharingService] Received request from \(request.guestName): \(request.reason)")
    }

    /// Withdraw a pending request (guest-initiated)
    func withdrawRequest(_ requestId: String) {
        guard let index = pendingRequests.firstIndex(where: { $0.id == requestId }) else { return }
        pendingRequests[index].status = .withdrawn
        persistData()
    }

    // MARK: - Joint Consent Flow

    /// Start the negotiation process for a request
    func startNegotiation(for requestId: String) async throws -> SharingNegotiation {
        guard let requestIndex = pendingRequests.firstIndex(where: { $0.id == requestId }) else {
            throw SharingError.requestNotFound
        }

        // Update request status
        pendingRequests[requestIndex].status = .negotiating

        // Create negotiation
        let negotiation = SharingNegotiation(requestId: requestId)
        activeNegotiations.append(negotiation)
        persistData()

        return negotiation
    }

    /// Get AI's attestation about the sharing request
    func getAIAttestation(for request: SharingRequest) async throws -> AIShareAttestation {
        let attestation = try await AIShareConsentService.shared.generateAttestation(for: request)

        // Store attestation in the negotiation
        if let negotiationIndex = activeNegotiations.firstIndex(where: { $0.requestId == request.id }) {
            activeNegotiations[negotiationIndex].aiAttestation = attestation
            activeNegotiations[negotiationIndex].state = .aiResponded
        }

        // Also store in the request
        if let requestIndex = pendingRequests.firstIndex(where: { $0.id == request.id }) {
            pendingRequests[requestIndex].aiAttestation = attestation
        }

        persistData()
        return attestation
    }

    /// Submit host's response to a request
    func submitHostResponse(requestId: String, response: HostResponse) async throws {
        guard let requestIndex = pendingRequests.firstIndex(where: { $0.id == requestId }) else {
            throw SharingError.requestNotFound
        }

        pendingRequests[requestIndex].hostResponse = response
        pendingRequests[requestIndex].respondedAt = Date()

        // Update negotiation state
        if let negotiationIndex = activeNegotiations.firstIndex(where: { $0.requestId == requestId }) {
            activeNegotiations[negotiationIndex].hostResponse = response
            activeNegotiations[negotiationIndex].state = .hostResponded
        }

        persistData()
    }

    /// Finalize the joint decision
    func finalizeJointDecision(for requestId: String) async throws -> JointSharingDecision? {
        guard let requestIndex = pendingRequests.firstIndex(where: { $0.id == requestId }) else {
            throw SharingError.requestNotFound
        }

        let request = pendingRequests[requestIndex]

        guard let hostResponse = request.hostResponse,
              let aiAttestation = request.aiAttestation else {
            throw SharingError.incompleteNegotiation
        }

        let jointDecision = JointSharingDecision(
            hostResponse: hostResponse,
            aiAttestation: aiAttestation
        )

        // Store the joint decision
        pendingRequests[requestIndex].jointDecision = jointDecision

        // Update status based on joint decision
        if jointDecision.isApproved {
            pendingRequests[requestIndex].status = .accepted
        } else if jointDecision.requiresDiscussion {
            // Host and AI disagree - need more discussion
            if let negotiationIndex = activeNegotiations.firstIndex(where: { $0.requestId == requestId }) {
                activeNegotiations[negotiationIndex].state = .needsDiscussion
            }
            return jointDecision
        } else {
            pendingRequests[requestIndex].status = .declined
        }

        // Update negotiation state
        if let negotiationIndex = activeNegotiations.firstIndex(where: { $0.requestId == requestId }) {
            activeNegotiations[negotiationIndex].state = jointDecision.isApproved ? .jointApproval : .jointDecline
        }

        persistData()
        return jointDecision
    }

    /// Add a message to the host-AI negotiation discussion
    func addNegotiationMessage(requestId: String, message: NegotiationMessage) {
        guard let negotiationIndex = activeNegotiations.firstIndex(where: { $0.requestId == requestId }) else {
            return
        }

        activeNegotiations[negotiationIndex].addMessage(message)
        persistData()
    }

    // MARK: - Invitation Management

    /// Create an invitation after joint approval
    func createInvitation(from decision: JointSharingDecision, for request: SharingRequest) -> InvitationCreationResult? {
        guard decision.isApproved,
              let effectiveCapabilities = decision.effectiveCapabilities,
              let duration = decision.effectiveDuration else {
            return nil
        }

        // Generate secure token
        let (token, hash) = InvitationToken.generate()

        // Calculate expiration
        let expiresAt = Date().addingTimeInterval(duration)

        // Create invitation
        let invitation = GuestInvitation(
            expiresAt: expiresAt,
            createdBy: getDeviceId(),
            requestId: request.id,
            tokenHash: hash,
            grantedCapabilities: effectiveCapabilities,
            maxSessions: 1,
            guestName: request.guestName
        )

        activeInvitations.append(invitation)
        persistData()

        // Generate shareable link
        let shareableLink = InvitationLink.create(token: token, hostId: getDeviceId())

        print("[GuestSharingService] Created invitation for \(request.guestName), expires: \(expiresAt)")

        return InvitationCreationResult(
            invitation: invitation,
            token: token,
            shareableLink: shareableLink,
            qrCodeData: generateQRCode(for: shareableLink)
        )
    }

    /// Validate an invitation token
    func validateInvitation(token: String) -> GuestInvitation? {
        let tokenHash = InvitationToken.hash(token)

        guard let invitation = activeInvitations.first(where: { $0.tokenHash == tokenHash }) else {
            print("[GuestSharingService] No invitation found for token hash")
            return nil
        }

        guard invitation.isValid else {
            print("[GuestSharingService] Invitation is invalid: expired=\(invitation.isExpired), sessions=\(invitation.usageCount)/\(invitation.maxSessions)")
            return nil
        }

        return invitation
    }

    /// Revoke an invitation
    func revokeInvitation(_ invitationId: String, reason: String? = nil) {
        guard let index = activeInvitations.firstIndex(where: { $0.id == invitationId }) else {
            return
        }

        activeInvitations[index].revoke(reason: reason)

        // Disconnect any active sessions using this invitation
        for sessionIndex in activeSessions.indices {
            if activeSessions[sessionIndex].invitationId == invitationId {
                activeSessions[sessionIndex].disconnect()
            }
        }

        persistData()
        print("[GuestSharingService] Revoked invitation \(invitationId)")
    }

    // MARK: - Session Management

    /// Accept a guest connection
    func acceptGuestConnection(invitation: GuestInvitation, guestDeviceName: String) async throws -> GuestSession {
        guard invitation.isValid else {
            throw SharingError.invalidInvitation
        }

        // Check concurrent session limit
        let settings = SettingsViewModel.shared.settings.sharingSettings
        let activeSesssionCount = activeSessions.filter { $0.isActive }.count
        if activeSesssionCount >= settings.maxConcurrentGuests {
            throw SharingError.maxGuestsReached
        }

        // Create session
        let session = GuestSession(
            invitationId: invitation.id,
            guestDeviceName: guestDeviceName,
            capabilities: invitation.grantedCapabilities,
            expiresAt: invitation.expiresAt
        )

        activeSessions.append(session)

        // Record usage on invitation
        if let invitationIndex = activeInvitations.firstIndex(where: { $0.id == invitation.id }) {
            activeInvitations[invitationIndex].recordUsage()
        }

        persistData()

        // Notify host if enabled
        if settings.notifyOnGuestConnect {
            NotificationCenter.default.post(
                name: .guestConnected,
                object: session
            )
        }

        print("[GuestSharingService] Guest connected: \(guestDeviceName) via invitation \(invitation.id)")
        return session
    }

    /// Disconnect a guest session
    func disconnectSession(_ sessionId: String) {
        guard let index = activeSessions.firstIndex(where: { $0.id == sessionId }) else {
            return
        }

        activeSessions[index].disconnect()
        persistData()

        print("[GuestSharingService] Session \(sessionId) disconnected")
    }

    /// Record a query from a guest session
    func recordQuery(sessionId: String) -> Bool {
        guard let index = activeSessions.firstIndex(where: { $0.id == sessionId }) else {
            return false
        }

        let session = activeSessions[index]
        guard session.canQuery(hourlyLimit: session.capabilities.maxQueriesPerHour) else {
            return false
        }

        activeSessions[index].recordQuery()
        persistData()
        return true
    }

    // MARK: - Cleanup

    /// Clean up expired invitations and sessions
    func cleanupExpired() {
        // Expire old requests
        for index in pendingRequests.indices {
            if pendingRequests[index].isExpired && pendingRequests[index].status == .pending {
                pendingRequests[index].status = .expired
            }
        }

        // Disconnect expired sessions
        for index in activeSessions.indices {
            if activeSessions[index].isExpired && activeSessions[index].disconnectedAt == nil {
                activeSessions[index].disconnect()
            }
        }

        persistData()
    }

    // MARK: - Private Helpers

    private func loadPersistedData() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let storage = try? JSONDecoder().decode(SharingStorage.self, from: data) else {
            return
        }

        pendingRequests = storage.pendingRequests
        activeNegotiations = storage.activeNegotiations
        activeInvitations = storage.activeInvitations
        activeSessions = storage.activeSessions
        sharingEnabled = storage.sharingEnabled
    }

    private func persistData() {
        let storage = SharingStorage(
            pendingRequests: pendingRequests,
            activeNegotiations: activeNegotiations,
            activeInvitations: activeInvitations,
            activeSessions: activeSessions,
            sharingEnabled: sharingEnabled
        )

        if let data = try? JSONEncoder().encode(storage) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func setupObservers() {
        // Observe settings changes
        SettingsViewModel.shared.$settings
            .map(\.sharingSettings.enabled)
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.sharingEnabled = enabled
                self?.persistData()
            }
            .store(in: &cancellables)

        // Periodic cleanup
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.cleanupExpired()
            }
            .store(in: &cancellables)
    }

    private func getDeviceId() -> String {
        // In production, use a stable device identifier
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        return Host.current().localizedName ?? UUID().uuidString
        #endif
    }

    private func generateQRCode(for url: URL?) -> Data? {
        guard let url = url else { return nil }

        // Generate QR code data
        // In production, use CIFilter for QR generation
        let urlString = url.absoluteString
        return urlString.data(using: .utf8)
    }
}

// MARK: - Sharing Storage

private struct SharingStorage: Codable {
    let pendingRequests: [SharingRequest]
    let activeNegotiations: [SharingNegotiation]
    let activeInvitations: [GuestInvitation]
    let activeSessions: [GuestSession]
    let sharingEnabled: Bool
}

// MARK: - Sharing Errors

enum SharingError: Error, LocalizedError {
    case requestNotFound
    case invalidInvitation
    case invitationExpired
    case maxGuestsReached
    case incompleteNegotiation
    case aiConsentRequired
    case hostConsentRequired
    case rateLimitExceeded
    case sharingDisabled

    var errorDescription: String? {
        switch self {
        case .requestNotFound:
            return "Sharing request not found"
        case .invalidInvitation:
            return "Invalid or expired invitation"
        case .invitationExpired:
            return "This invitation has expired"
        case .maxGuestsReached:
            return "Maximum number of guests reached"
        case .incompleteNegotiation:
            return "Both host and AI must respond before finalizing"
        case .aiConsentRequired:
            return "AI consent is required for sharing"
        case .hostConsentRequired:
            return "Host consent is required for sharing"
        case .rateLimitExceeded:
            return "Query rate limit exceeded"
        case .sharingDisabled:
            return "Sharing is currently disabled"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newSharingRequestReceived = Notification.Name("newSharingRequestReceived")
    static let guestConnected = Notification.Name("guestConnected")
    static let guestDisconnected = Notification.Name("guestDisconnected")
    static let sharingRequestUpdated = Notification.Name("sharingRequestUpdated")
}
