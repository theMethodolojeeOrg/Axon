//
//  AgentOrchestratorError.swift
//  Axon
//
//  Error types for the agent orchestration system.
//

import Foundation

// MARK: - Agent Orchestrator Error

/// Errors that can occur during agent orchestration.
enum AgentOrchestratorError: LocalizedError {

    // MARK: - Job Lifecycle Errors

    /// Job not found in active or completed jobs
    case jobNotFound(String)

    /// Job has already reached a terminal state
    case jobAlreadyTerminal(String)

    /// Invalid state transition attempted
    case invalidStateTransition(from: SubAgentJobState, to: SubAgentJobState)

    /// Job has expired
    case jobExpired(String)

    // MARK: - Attestation Errors (Commandment #1)

    /// Attempted to execute without approval attestation
    case missingAttestation(String)

    /// Attestation signature verification failed
    case invalidAttestation(String, reason: String)

    /// Attestation type doesn't match required type
    case wrongAttestationType(expected: AttestationType, got: AttestationType)

    // MARK: - Provider/Model Errors

    /// No providers are configured with valid API keys
    case noConfiguredProviders

    /// Specific provider not configured
    case providerNotConfigured(AIProvider)

    /// Model not available for the provider
    case modelNotAvailable(String, provider: AIProvider)

    /// API call failed
    case apiCallFailed(String)

    // MARK: - Permission Errors

    /// Action not permitted under current permissions
    case permissionDenied(String)

    /// Tool not allowed for this job
    case toolNotAllowed(ToolId)

    /// Write operation attempted on read-only job
    case writeNotAllowed

    // MARK: - Silo Errors

    /// Silo not found
    case siloNotFound(String)

    /// Attempted to modify sealed silo
    case siloSealed(String)

    /// Silo has expired
    case siloExpired(String)

    // MARK: - Context Errors

    /// Failed to build context for job
    case contextBuildFailed(String)

    /// Tag filtering returned no memories
    case noMatchingMemories([String])

    // MARK: - Execution Errors

    /// Job execution timed out
    case executionTimeout(String, seconds: Int)

    /// Token budget exceeded
    case tokenBudgetExceeded(used: Int, limit: Int)

    /// Sub-agent response parsing failed
    case responseParsingFailed(String)

    // MARK: - Nesting Violation (Commandment #4)

    /// Sub-agent attempted to spawn another agent (forbidden)
    case nestingViolation(jobId: String, attemptedRole: SubAgentRole)

    // MARK: - LocalizedError Conformance

    var errorDescription: String? {
        switch self {
        case .jobNotFound(let id):
            return "Job not found: \(id)"

        case .jobAlreadyTerminal(let id):
            return "Job \(id) has already reached a terminal state"

        case .invalidStateTransition(let from, let to):
            return "Invalid state transition from \(from.displayName) to \(to.displayName)"

        case .jobExpired(let id):
            return "Job \(id) has expired"

        case .missingAttestation(let id):
            return "Job \(id) requires approval attestation before execution"

        case .invalidAttestation(let id, let reason):
            return "Invalid attestation for job \(id): \(reason)"

        case .wrongAttestationType(let expected, let got):
            return "Expected \(expected.displayName) attestation, got \(got.displayName)"

        case .noConfiguredProviders:
            return "No AI providers are configured with valid API keys"

        case .providerNotConfigured(let provider):
            return "\(provider.displayName) is not configured"

        case .modelNotAvailable(let model, let provider):
            return "Model \(model) is not available for \(provider.displayName)"

        case .apiCallFailed(let message):
            return "API call failed: \(message)"

        case .permissionDenied(let action):
            return "Permission denied: \(action)"

        case .toolNotAllowed(let tool):
            return "Tool \(tool.displayName) is not allowed for this job"

        case .writeNotAllowed:
            return "Write operations are not allowed for this job"

        case .siloNotFound(let id):
            return "Silo not found: \(id)"

        case .siloSealed(let id):
            return "Silo \(id) is sealed and cannot be modified"

        case .siloExpired(let id):
            return "Silo \(id) has expired"

        case .contextBuildFailed(let reason):
            return "Failed to build context: \(reason)"

        case .noMatchingMemories(let tags):
            return "No memories found matching tags: \(tags.joined(separator: ", "))"

        case .executionTimeout(let id, let seconds):
            return "Job \(id) timed out after \(seconds) seconds"

        case .tokenBudgetExceeded(let used, let limit):
            return "Token budget exceeded: used \(used), limit \(limit)"

        case .responseParsingFailed(let reason):
            return "Failed to parse sub-agent response: \(reason)"

        case .nestingViolation(let jobId, let attemptedRole):
            return "Nesting violation: job \(jobId) attempted to spawn a \(attemptedRole.displayName). Sub-agents cannot spawn other agents."
        }
    }

    var failureReason: String? {
        switch self {
        case .missingAttestation:
            return "The execution gate requires a valid approval attestation"

        case .invalidAttestation:
            return "The attestation signature did not match"

        case .nestingViolation:
            return "Only Axon can spawn sub-agents. Sub-agents must report spawn recommendations in their silo."

        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingAttestation(let id):
            return "Call approveJob(\"\(id)\") to generate an attestation before executing"

        case .invalidAttestation:
            return "Regenerate the attestation using approveJob()"

        case .noConfiguredProviders:
            return "Configure at least one AI provider in Settings"

        case .providerNotConfigured(let provider):
            return "Add API key for \(provider.displayName) in Settings"

        case .nestingViolation:
            return "Check the job's silo for spawn recommendations and have Axon process them"

        case .executionTimeout:
            return "Consider increasing the timeout or simplifying the task"

        case .tokenBudgetExceeded:
            return "Increase the token budget or break the task into smaller parts"

        default:
            return nil
        }
    }

    // MARK: - Failure Classification

    /// Maps to a FailureReason for affinity tracking
    var failureReasonForAffinity: FailureReason {
        switch self {
        case .executionTimeout:
            return .timeout

        case .tokenBudgetExceeded:
            return .contextOverflow

        case .responseParsingFailed:
            return .formatError

        case .apiCallFailed:
            return .apiError

        case .toolNotAllowed, .writeNotAllowed, .permissionDenied:
            return .toolMisuse

        default:
            return .unknown
        }
    }
}

// MARK: - Error Helpers

extension AgentOrchestratorError {
    /// Check if this error should be retried
    var isRetryable: Bool {
        switch self {
        case .apiCallFailed, .executionTimeout:
            return true
        default:
            return false
        }
    }

    /// Check if this error is due to configuration
    var isConfigurationError: Bool {
        switch self {
        case .noConfiguredProviders, .providerNotConfigured, .modelNotAvailable:
            return true
        default:
            return false
        }
    }

    /// Check if this is a security/permission error
    var isSecurityError: Bool {
        switch self {
        case .missingAttestation, .invalidAttestation, .permissionDenied,
             .toolNotAllowed, .writeNotAllowed, .nestingViolation:
            return true
        default:
            return false
        }
    }
}
