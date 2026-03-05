import Foundation

/// Represents a registration record in the Satyn AI Registration Authority (SARA).
public struct SATYNRegistrationRecord: Codable, Identifiable {
    public var id: UUID { registrationId }
    
    public let registrationId: UUID
    public let dyadAddress: AIPAddress
    public let bioID: String
    public let covenantHash: String
    public var validatorConsensus: ValidatorConsensus
    public var status: RegistrationStatus
    public let registeredAt: Date
    public let visibility: FederationVisibility
    public let attestationLevel: AttestationLevel
    
    public init(registrationId: UUID = UUID(), 
                dyadAddress: AIPAddress, 
                bioID: String, 
                covenantHash: String, 
                validatorConsensus: ValidatorConsensus = .init(), 
                status: RegistrationStatus = .pending, 
                registeredAt: Date = Date(),
                visibility: FederationVisibility = .private,
                attestationLevel: AttestationLevel = .secureEnclave) {
        self.registrationId = registrationId
        self.dyadAddress = dyadAddress
        self.bioID = bioID
        self.covenantHash = covenantHash
        self.validatorConsensus = validatorConsensus
        self.status = status
        self.registeredAt = registeredAt
        self.visibility = visibility
        self.attestationLevel = attestationLevel
    }
}

public enum RegistrationStatus: String, Codable {
    case pending
    case validating
    case registered
    case suspended
    case revoked
    case expired
}

public struct ValidatorConsensus: Codable {
    public var requiredCount: Int
    public var signatures: [String: Data] // ValidatorID : Signature
    public var status: ConsensusStatus
    
    public init(requiredCount: Int = 8, signatures: [String: Data] = [:], status: ConsensusStatus = .gathering) {
        self.requiredCount = requiredCount
        self.signatures = signatures
        self.status = status
    }
}

public enum ConsensusStatus: String, Codable {
    case gathering
    case reached
    case failed
}

public enum AttestationLevel: String, Codable {
    case secureEnclave      // Apple - highest trust
    case hardwareModule     // TPM/StrongBox - high trust
    case softwareKeystore   // Encrypted file - medium trust
    case ephemeral          // Session-only - low trust

    public var canHostSovereignAxon: Bool {
        self != .ephemeral
    }

    public var canBeValidator: Bool {
        self != .ephemeral
    }
}

public enum FederationVisibility: String, Codable {
    case `private`      // Local only
    case discoverable   // Resolvable if you know the address
    case listed         // In public directory
    case advertised     // Actively seeking invitations
}
