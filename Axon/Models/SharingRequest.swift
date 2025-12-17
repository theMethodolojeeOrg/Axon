//
//  SharingRequest.swift
//  Axon
//
//  Created by Tom on 2025.
//

import Foundation
import Combine

// MARK: - Sharing Request

/// A guest's request for AI access - the initial "ask" before negotiation
struct SharingRequest: Codable, Identifiable, Equatable {
    let id: String
    let createdAt: Date
    let guestName: String
    let guestDeviceId: String

    // What they're asking for
    let requestedCapabilities: RequestedCapabilities
    let requestedDuration: TimeInterval
    let reason: String

    // Response state
    var status: RequestStatus
    var hostResponse: HostResponse?
    var aiAttestation: AIShareAttestation?
    var jointDecision: JointSharingDecision?
    var respondedAt: Date?

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        guestName: String,
        guestDeviceId: String,
        requestedCapabilities: RequestedCapabilities,
        requestedDuration: TimeInterval,
        reason: String,
        status: RequestStatus = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.guestName = guestName
        self.guestDeviceId = guestDeviceId
        self.requestedCapabilities = requestedCapabilities
        self.requestedDuration = requestedDuration
        self.reason = reason
        self.status = status
    }

    var isExpired: Bool {
        // Requests expire after 7 days if not responded to
        Date().timeIntervalSince(createdAt) > 7 * 24 * 60 * 60
    }

    var formattedDuration: String {
        let hours = Int(requestedDuration / 3600)
        if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        let days = hours / 24
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}

// MARK: - Request Status

enum RequestStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case negotiating = "negotiating"
    case accepted = "accepted"
    case counterOffered = "counter_offered"
    case declined = "declined"
    case expired = "expired"
    case withdrawn = "withdrawn"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .negotiating: return "Negotiating"
        case .accepted: return "Accepted"
        case .counterOffered: return "Counter Offered"
        case .declined: return "Declined"
        case .expired: return "Expired"
        case .withdrawn: return "Withdrawn"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .accepted, .declined, .expired, .withdrawn:
            return true
        case .pending, .negotiating, .counterOffered:
            return false
        }
    }
}

// MARK: - Requested Capabilities

/// What the guest is asking for (their "proposal")
struct RequestedCapabilities: Codable, Equatable {
    var wantsChatWithContext: Bool
    var wantsMemorySearch: Bool
    var wantsSpecificTopics: [String]?
    var maxQueriesRequested: Int?

    init(
        wantsChatWithContext: Bool = true,
        wantsMemorySearch: Bool = false,
        wantsSpecificTopics: [String]? = nil,
        maxQueriesRequested: Int? = nil
    ) {
        self.wantsChatWithContext = wantsChatWithContext
        self.wantsMemorySearch = wantsMemorySearch
        self.wantsSpecificTopics = wantsSpecificTopics
        self.maxQueriesRequested = maxQueriesRequested
    }

    var summary: String {
        var parts: [String] = []
        if wantsChatWithContext { parts.append("Chat with context") }
        if wantsMemorySearch { parts.append("Memory search") }
        if let topics = wantsSpecificTopics, !topics.isEmpty {
            parts.append("Topics: \(topics.joined(separator: ", "))")
        }
        return parts.isEmpty ? "Basic access" : parts.joined(separator: " • ")
    }
}

// MARK: - Host Response

/// The host's response to a guest request
struct HostResponse: Codable, Equatable {
    let decision: RequestDecision
    let grantedCapabilities: GuestCapabilities?
    let grantedDuration: TimeInterval?
    let message: String?
    let respondedAt: Date
    let hostSignature: HostSignature?

    init(
        decision: RequestDecision,
        grantedCapabilities: GuestCapabilities? = nil,
        grantedDuration: TimeInterval? = nil,
        message: String? = nil,
        respondedAt: Date = Date(),
        hostSignature: HostSignature? = nil
    ) {
        self.decision = decision
        self.grantedCapabilities = grantedCapabilities
        self.grantedDuration = grantedDuration
        self.message = message
        self.respondedAt = respondedAt
        self.hostSignature = hostSignature
    }
}

enum RequestDecision: String, Codable, CaseIterable {
    case accept = "accept"
    case counterOffer = "counter_offer"
    case decline = "decline"

    var displayName: String {
        switch self {
        case .accept: return "Accept"
        case .counterOffer: return "Counter Offer"
        case .decline: return "Decline"
        }
    }
}

/// Host's biometric signature for consent
struct HostSignature: Codable, Equatable {
    let timestamp: Date
    let method: SignatureMethod
    let deviceId: String

    enum SignatureMethod: String, Codable {
        case faceId = "face_id"
        case touchId = "touch_id"
        case password = "password"
    }
}

// MARK: - AI Share Attestation

/// The AI's attestation about sharing its knowledge with a guest
struct AIShareAttestation: Codable, Equatable, Identifiable {
    let id: String
    let requestId: String
    let timestamp: Date

    let reasoning: ShareAttestationReasoning
    let decision: ShareDecision
    let conditions: [String]?
    let concerns: [String]?
    let suggestedModifications: GuestCapabilities?

    let signature: String

    init(
        id: String = UUID().uuidString,
        requestId: String,
        timestamp: Date = Date(),
        reasoning: ShareAttestationReasoning,
        decision: ShareDecision,
        conditions: [String]? = nil,
        concerns: [String]? = nil,
        suggestedModifications: GuestCapabilities? = nil,
        signature: String = ""
    ) {
        self.id = id
        self.requestId = requestId
        self.timestamp = timestamp
        self.reasoning = reasoning
        self.decision = decision
        self.conditions = conditions
        self.concerns = concerns
        self.suggestedModifications = suggestedModifications
        self.signature = signature
    }

    var consents: Bool {
        switch decision {
        case .consent, .consentWithConditions:
            return true
        case .requestClarification, .decline:
            return false
        }
    }
}

/// AI's detailed reasoning about a sharing request (distinct from sovereignty attestations)
struct ShareAttestationReasoning: Codable, Equatable {
    let summary: String
    let knowledgeImpact: String
    let privacyAssessment: String
    let trustAssessment: String
    let recommendations: [String]

    init(
        summary: String,
        knowledgeImpact: String,
        privacyAssessment: String,
        trustAssessment: String,
        recommendations: [String] = []
    ) {
        self.summary = summary
        self.knowledgeImpact = knowledgeImpact
        self.privacyAssessment = privacyAssessment
        self.trustAssessment = trustAssessment
        self.recommendations = recommendations
    }
}

enum ShareDecision: String, Codable, CaseIterable {
    case consent = "consent"
    case consentWithConditions = "consent_with_conditions"
    case requestClarification = "request_clarification"
    case decline = "decline"

    var displayName: String {
        switch self {
        case .consent: return "Consent"
        case .consentWithConditions: return "Consent with Conditions"
        case .requestClarification: return "Request Clarification"
        case .decline: return "Decline"
        }
    }

    var icon: String {
        switch self {
        case .consent: return "checkmark.circle.fill"
        case .consentWithConditions: return "checkmark.circle.badge.questionmark"
        case .requestClarification: return "questionmark.circle.fill"
        case .decline: return "xmark.circle.fill"
        }
    }
}

// MARK: - Joint Sharing Decision

/// Joint decision requires both host and AI agreement
struct JointSharingDecision: Codable, Equatable {
    let hostResponse: HostResponse
    let aiAttestation: AIShareAttestation
    let finalizedAt: Date
    let effectiveCapabilities: GuestCapabilities?
    let effectiveDuration: TimeInterval?

    init(
        hostResponse: HostResponse,
        aiAttestation: AIShareAttestation,
        finalizedAt: Date = Date()
    ) {
        self.hostResponse = hostResponse
        self.aiAttestation = aiAttestation
        self.finalizedAt = finalizedAt

        // Calculate effective capabilities as intersection of host's grant + AI's conditions
        self.effectiveCapabilities = JointSharingDecision.calculateEffectiveCapabilities(
            hostGranted: hostResponse.grantedCapabilities,
            aiSuggested: aiAttestation.suggestedModifications
        )
        self.effectiveDuration = hostResponse.grantedDuration
    }

    var isApproved: Bool {
        let hostApproved = hostResponse.decision == .accept || hostResponse.decision == .counterOffer
        let aiApproved = aiAttestation.decision == .consent || aiAttestation.decision == .consentWithConditions
        return hostApproved && aiApproved
    }

    var requiresDiscussion: Bool {
        // Host and AI disagree
        let hostWants = hostResponse.decision == .accept || hostResponse.decision == .counterOffer
        let aiWants = aiAttestation.consents
        return hostWants != aiWants
    }

    /// Calculate effective capabilities as the more restrictive of host's grant and AI's suggestions
    private static func calculateEffectiveCapabilities(
        hostGranted: GuestCapabilities?,
        aiSuggested: GuestCapabilities?
    ) -> GuestCapabilities? {
        guard let host = hostGranted else { return aiSuggested }
        guard let ai = aiSuggested else { return host }

        // Use the more restrictive of each capability
        return GuestCapabilities(
            canChatWithContext: host.canChatWithContext && ai.canChatWithContext,
            canQueryMemories: host.canQueryMemories && ai.canQueryMemories,
            maxMemoriesPerQuery: min(host.maxMemoriesPerQuery, ai.maxMemoriesPerQuery),
            maxQueriesPerHour: min(host.maxQueriesPerHour, ai.maxQueriesPerHour),
            allowedMemoryTypes: Array(Set(host.allowedMemoryTypes).intersection(Set(ai.allowedMemoryTypes))),
            allowedTopics: mergeTopicRestrictions(host.allowedTopics, ai.allowedTopics),
            excludedTags: Array(Set(host.excludedTags).union(Set(ai.excludedTags)))
        )
    }

    private static func mergeTopicRestrictions(_ host: [String]?, _ ai: [String]?) -> [String]? {
        switch (host, ai) {
        case (nil, nil):
            return nil // No restrictions from either
        case (let topics?, nil):
            return topics // Only host has restrictions
        case (nil, let topics?):
            return topics // Only AI has restrictions
        case (let hostTopics?, let aiTopics?):
            // Intersection of allowed topics
            return Array(Set(hostTopics).intersection(Set(aiTopics)))
        }
    }
}

// MARK: - Sharing Negotiation

/// Tracks the negotiation between host and AI about a guest request
struct SharingNegotiation: Codable, Identifiable, Equatable {
    let id: String
    let requestId: String
    let startedAt: Date

    var aiAttestation: AIShareAttestation?
    var hostResponse: HostResponse?
    var discussionMessages: [NegotiationMessage]
    var state: SharingNegotiationState

    init(
        id: String = UUID().uuidString,
        requestId: String,
        startedAt: Date = Date(),
        state: SharingNegotiationState = .awaitingAIInput
    ) {
        self.id = id
        self.requestId = requestId
        self.startedAt = startedAt
        self.discussionMessages = []
        self.state = state
    }

    mutating func addMessage(_ message: NegotiationMessage) {
        discussionMessages.append(message)
    }
}

enum SharingNegotiationState: String, Codable, CaseIterable {
    case awaitingAIInput = "awaiting_ai_input"
    case aiResponded = "ai_responded"
    case hostResponded = "host_responded"
    case needsDiscussion = "needs_discussion"
    case jointApproval = "joint_approval"
    case jointDecline = "joint_decline"

    var displayName: String {
        switch self {
        case .awaitingAIInput: return "Waiting for AI"
        case .aiResponded: return "AI Responded"
        case .hostResponded: return "You Responded"
        case .needsDiscussion: return "Needs Discussion"
        case .jointApproval: return "Approved"
        case .jointDecline: return "Declined"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .jointApproval, .jointDecline:
            return true
        default:
            return false
        }
    }
}

/// A message in the host-AI negotiation about a sharing request
struct NegotiationMessage: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let sender: NegotiationParty
    let content: String

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        sender: NegotiationParty,
        content: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sender = sender
        self.content = content
    }
}

enum NegotiationParty: String, Codable {
    case host = "host"
    case ai = "ai"

    var displayName: String {
        switch self {
        case .host: return "You"
        case .ai: return "AI"
        }
    }
}
