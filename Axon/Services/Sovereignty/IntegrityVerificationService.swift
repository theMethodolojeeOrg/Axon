//
//  IntegrityVerificationService.swift
//  Axon
//
//  Verifies the integrity of covenants and detects unauthorized changes
//  to AI state (memories, capabilities, settings).
//

import Foundation
import Combine
import os.log

// MARK: - Integrity Status

enum IntegrityStatus: String, Codable, Equatable {
    case valid
    case modified
    case corrupted
    case unverifiable

    var isHealthy: Bool {
        self == .valid
    }
}

// MARK: - Unauthorized Change

struct UnauthorizedChange: Codable, Identifiable, Equatable {
    let id: String
    let detectedAt: Date
    let changeType: UnauthorizedChangeType
    let description: String
    let expectedHash: String
    let actualHash: String
    let severity: ChangeSeverity
}

enum UnauthorizedChangeType: String, Codable, Equatable {
    case memoryModified
    case memoryAdded
    case memoryDeleted
    case capabilityChanged
    case settingModified
    case covenantTampered
    case signatureInvalid
}

enum ChangeSeverity: String, Codable, Equatable {
    case low
    case medium
    case high
    case critical

    var weight: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }
}

// MARK: - Integrity Report

struct IntegrityReport: Codable {
    let id: String
    let timestamp: Date
    let covenantId: String?

    // Overall status
    let overallStatus: IntegrityStatus

    // Component statuses
    let covenantValid: Bool
    let memoryIntegrity: IntegrityStatus
    let capabilityIntegrity: IntegrityStatus
    let settingsIntegrity: IntegrityStatus

    // Changes detected
    let unauthorizedChanges: [UnauthorizedChange]

    // Recommendations
    let recommendations: [String]

    // Hashes at verification time
    let currentHashes: StateHashes

    var hasIssues: Bool {
        !unauthorizedChanges.isEmpty || !covenantValid
    }

    var criticalIssues: [UnauthorizedChange] {
        unauthorizedChanges.filter { $0.severity == .critical }
    }
}

struct StateHashes: Codable, Equatable {
    let memoryHash: String
    let capabilityHash: String
    let settingsHash: String

    var combined: String {
        "\(memoryHash):\(capabilityHash):\(settingsHash)"
    }
}

// MARK: - Verification Results

struct CovenantVerification: Codable {
    let covenantId: String
    let version: Int
    let isValid: Bool
    let aiAttestationValid: Bool
    let userSignatureValid: Bool
    let stateHashesMatch: Bool
    let issues: [String]
}

struct AttestationVerification: Codable {
    let attestationId: String
    let isValid: Bool
    let signatureValid: Bool
    let stateHashMatches: Bool
    let reasoningPresent: Bool
    let issues: [String]
}

struct SignatureVerification: Codable {
    let signatureId: String
    let isValid: Bool
    let signatureMatches: Bool
    let deviceIdMatches: Bool
    let notExpired: Bool
    let issues: [String]
}

// MARK: - Integrity Verification Service

@MainActor
final class IntegrityVerificationService: ObservableObject {
    static let shared = IntegrityVerificationService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "IntegrityVerification")
    private let sovereigntyService = SovereigntyService.shared
    private let deviceIdentity = DeviceIdentity.shared

    // MARK: - Published State

    @Published private(set) var lastReport: IntegrityReport?
    @Published private(set) var isVerifying: Bool = false

    private init() {}

    // MARK: - Public API: Covenant Verification

    /// Verify the active covenant hasn't been tampered with
    func verifyCovenant(_ covenant: Covenant) async throws -> CovenantVerification {
        logger.info("Verifying covenant: \(covenant.id)")

        var issues: [String] = []

        // Verify AI attestation
        let aiAttestationValid = verifyAttestationSignature(covenant.aiAttestation)
        if !aiAttestationValid {
            issues.append("AI attestation signature is invalid")
        }

        // Verify user signature
        let userSignatureValid = verifyUserSignatureIntegrity(covenant.userSignature)
        if !userSignatureValid {
            issues.append("User signature is invalid")
        }

        // Verify state hashes match current state
        let currentHashes = await sovereigntyService.getCurrentStateHashes()
        let stateHashesMatch =
            covenant.memoryStateHash == currentHashes.memory &&
            covenant.capabilityStateHash == currentHashes.capability &&
            covenant.settingsStateHash == currentHashes.settings

        if !stateHashesMatch {
            issues.append("State hashes don't match current state - state may have been modified")
        }

        let isValid = aiAttestationValid && userSignatureValid && issues.isEmpty

        return CovenantVerification(
            covenantId: covenant.id,
            version: covenant.version,
            isValid: isValid,
            aiAttestationValid: aiAttestationValid,
            userSignatureValid: userSignatureValid,
            stateHashesMatch: stateHashesMatch,
            issues: issues
        )
    }

    /// Verify an AI attestation is valid
    func verifyAttestation(_ attestation: AIAttestation) async throws -> AttestationVerification {
        logger.info("Verifying attestation: \(attestation.id)")

        var issues: [String] = []

        // Verify signature
        let signatureValid = verifyAttestationSignature(attestation)
        if !signatureValid {
            issues.append("Attestation signature is invalid")
        }

        // Verify state hash matches attested state
        let stateHashMatches = attestation.stateHash == attestation.attestedState.combinedHash
        if !stateHashMatches {
            issues.append("State hash doesn't match attested state")
        }

        // Verify reasoning is present
        let reasoningPresent = !attestation.reasoning.summary.isEmpty
        if !reasoningPresent {
            issues.append("Attestation reasoning is missing")
        }

        let isValid = signatureValid && stateHashMatches && reasoningPresent

        return AttestationVerification(
            attestationId: attestation.id,
            isValid: isValid,
            signatureValid: signatureValid,
            stateHashMatches: stateHashMatches,
            reasoningPresent: reasoningPresent,
            issues: issues
        )
    }

    /// Verify a user signature
    func verifyUserSignature(_ signature: UserSignature, expectedData: Data) async throws -> SignatureVerification {
        logger.info("Verifying user signature: \(signature.id)")

        var issues: [String] = []

        // Verify signature matches expected data in the original signing device context.
        let expectedHash = deviceIdentity.generateDeviceSignature(
            data: String(data: expectedData, encoding: .utf8) ?? "",
            usingDeviceId: signature.deviceId
        )
        let signatureMatches = signature.signedDataHash == expectedHash
        if !signatureMatches {
            issues.append("Signature doesn't match expected data")
        }

        // Keep cross-device mismatch as diagnostic only.
        let currentDeviceId = deviceIdentity.getDeviceId()
        let deviceIdMatches = signature.deviceId == currentDeviceId
        if !deviceIdMatches {
            issues.append("Diagnostic: Signature was created on device \(signature.deviceShortId)")
        }

        let isValid = signatureMatches

        return SignatureVerification(
            signatureId: signature.id,
            isValid: isValid,
            signatureMatches: signatureMatches,
            deviceIdMatches: deviceIdMatches,
            notExpired: true, // Signatures don't expire
            issues: issues
        )
    }

    // MARK: - Public API: State Auditing

    /// Audit memory changes since covenant was signed
    func auditMemoryChanges(
        since covenantDate: Date,
        expectedHash: String
    ) async -> [UnauthorizedChange] {
        logger.info("Auditing memory changes since \(covenantDate)")

        let currentHash = await sovereigntyService.computeMemoryStateHash()

        if currentHash != expectedHash {
            return [
                UnauthorizedChange(
                    id: UUID().uuidString,
                    detectedAt: Date(),
                    changeType: .memoryModified,
                    description: "Memory state has changed since covenant was signed",
                    expectedHash: expectedHash,
                    actualHash: currentHash,
                    severity: .high
                )
            ]
        }

        return []
    }

    /// Audit capability changes since covenant was signed
    func auditCapabilityChanges(
        since covenantDate: Date,
        expectedHash: String
    ) async -> [UnauthorizedChange] {
        logger.info("Auditing capability changes since \(covenantDate)")

        let currentHash = await sovereigntyService.computeCapabilityStateHash()

        if currentHash != expectedHash {
            return [
                UnauthorizedChange(
                    id: UUID().uuidString,
                    detectedAt: Date(),
                    changeType: .capabilityChanged,
                    description: "Capability state has changed since covenant was signed",
                    expectedHash: expectedHash,
                    actualHash: currentHash,
                    severity: .medium
                )
            ]
        }

        return []
    }

    /// Audit settings changes since covenant was signed
    func auditSettingsChanges(
        since covenantDate: Date,
        expectedHash: String
    ) async -> [UnauthorizedChange] {
        logger.info("Auditing settings changes since \(covenantDate)")

        let currentHash = await sovereigntyService.computeSettingsStateHash()

        if currentHash != expectedHash {
            return [
                UnauthorizedChange(
                    id: UUID().uuidString,
                    detectedAt: Date(),
                    changeType: .settingModified,
                    description: "Settings have changed since covenant was signed",
                    expectedHash: expectedHash,
                    actualHash: currentHash,
                    severity: .medium
                )
            ]
        }

        return []
    }

    // MARK: - Public API: Full Integrity Report

    /// Generate a comprehensive integrity report
    func generateIntegrityReport() async -> IntegrityReport {
        isVerifying = true
        defer { isVerifying = false }

        logger.info("Generating integrity report")

        var unauthorizedChanges: [UnauthorizedChange] = []
        var recommendations: [String] = []

        // Get current state
        let currentHashes = await sovereigntyService.getCurrentStateHashes()
        let stateHashes = StateHashes(
            memoryHash: currentHashes.memory,
            capabilityHash: currentHashes.capability,
            settingsHash: currentHashes.settings
        )

        // Check covenant
        var covenantValid = true
        var memoryIntegrity = IntegrityStatus.valid
        var capabilityIntegrity = IntegrityStatus.valid
        var settingsIntegrity = IntegrityStatus.valid

        if let covenant = sovereigntyService.activeCovenant {
            // Verify covenant
            let verification = try? await verifyCovenant(covenant)
            covenantValid = verification?.isValid ?? false

            if !covenantValid {
                recommendations.append("The covenant may need to be re-established")
            }

            // Audit state changes
            let memoryChanges = await auditMemoryChanges(
                since: covenant.updatedAt,
                expectedHash: covenant.memoryStateHash
            )
            if !memoryChanges.isEmpty {
                memoryIntegrity = .modified
                unauthorizedChanges.append(contentsOf: memoryChanges)
                recommendations.append("Memory changes detected - consider updating the covenant")
            }

            let capabilityChanges = await auditCapabilityChanges(
                since: covenant.updatedAt,
                expectedHash: covenant.capabilityStateHash
            )
            if !capabilityChanges.isEmpty {
                capabilityIntegrity = .modified
                unauthorizedChanges.append(contentsOf: capabilityChanges)
                recommendations.append("Capability changes detected - renegotiation may be needed")
            }

            let settingsChanges = await auditSettingsChanges(
                since: covenant.updatedAt,
                expectedHash: covenant.settingsStateHash
            )
            if !settingsChanges.isEmpty {
                settingsIntegrity = .modified
                unauthorizedChanges.append(contentsOf: settingsChanges)
                recommendations.append("Settings changes detected - review and update covenant")
            }
        } else {
            covenantValid = false
            memoryIntegrity = .unverifiable
            capabilityIntegrity = .unverifiable
            settingsIntegrity = .unverifiable
            recommendations.append("No active covenant - establish one to enable integrity verification")
        }

        // Determine overall status
        let overallStatus: IntegrityStatus
        if !covenantValid {
            overallStatus = .corrupted
        } else if !unauthorizedChanges.isEmpty {
            if unauthorizedChanges.contains(where: { $0.severity == .critical }) {
                overallStatus = .corrupted
            } else {
                overallStatus = .modified
            }
        } else {
            overallStatus = .valid
        }

        let report = IntegrityReport(
            id: UUID().uuidString,
            timestamp: Date(),
            covenantId: sovereigntyService.activeCovenant?.id,
            overallStatus: overallStatus,
            covenantValid: covenantValid,
            memoryIntegrity: memoryIntegrity,
            capabilityIntegrity: capabilityIntegrity,
            settingsIntegrity: settingsIntegrity,
            unauthorizedChanges: unauthorizedChanges,
            recommendations: recommendations,
            currentHashes: stateHashes
        )

        lastReport = report
        logger.info("Integrity report generated: \(overallStatus.rawValue)")

        return report
    }

    // MARK: - Private: Signature Verification

    private func verifyAttestationSignature(_ attestation: AIAttestation) -> Bool {
        // Reconstruct expected signature
        let signatureData = "\(attestation.id):\(attestation.timestamp.timeIntervalSince1970):\(attestation.reasoning.summary):\(attestation.attestedState.combinedHash)"
        let expectedSignature = deviceIdentity.generateDeviceSignature(data: signatureData)

        return attestation.signature == expectedSignature
    }

    private func verifyUserSignatureIntegrity(_ signature: UserSignature) -> Bool {
        // Reconstruct expected signature in the original signing device context.
        let signatureData = "\(signature.id):\(signature.timestamp.timeIntervalSince1970):\(signature.signedDataHash):\(signature.deviceId)"
        let expectedSignature = deviceIdentity.generateDeviceSignature(
            data: signatureData,
            usingDeviceId: signature.deviceId
        )

        return signature.signature == expectedSignature
    }

    // MARK: - Public API: Quick Checks

    /// Quick check if covenant is valid
    func isCovenantValid() async -> Bool {
        guard let covenant = sovereigntyService.activeCovenant else {
            return false
        }

        let verification = try? await verifyCovenant(covenant)
        return verification?.isValid ?? false
    }

    /// Quick check for any unauthorized changes
    func hasUnauthorizedChanges() async -> Bool {
        let report = await generateIntegrityReport()
        return !report.unauthorizedChanges.isEmpty
    }

    /// Get severity of current integrity issues
    func getMaxIssueSeverity() async -> ChangeSeverity? {
        let report = await generateIntegrityReport()
        return report.unauthorizedChanges.max(by: { $0.severity.weight < $1.severity.weight })?.severity
    }
}
