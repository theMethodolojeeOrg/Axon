//
//  AgentOrchestratorService.swift
//  Axon
//
//  Central orchestrator for sub-agent management.
//  This is Axon's Command and Control interface for Intelligence.
//
//  Responsibilities:
//  - Job lifecycle management (propose → approve → execute → complete/terminate)
//  - Silo management (create, seal, expire)
//  - Model task affinity tracking
//  - Integration with sovereignty signing
//

import Foundation
import Combine
import os.log

// MARK: - Agent Orchestrator Service

@MainActor
final class AgentOrchestratorService: ObservableObject {
    static let shared = AgentOrchestratorService()

    // MARK: - Dependencies (internal for extension access)

    let sovereigntyService = SovereigntyService.shared
    let apiKeysStorage = APIKeysStorage.shared
    let settingsViewModel = SettingsViewModel.shared
    let costService = CostService.shared
    let liveActivityService = LiveActivityService.shared

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "AgentOrchestrator")

    // MARK: - Published State (internal(set) for extension access)

    /// Active jobs (not yet terminal)
    @Published internal var activeJobs: [SubAgentJob] = []

    /// Completed/terminated jobs (recent history)
    @Published internal var completedJobs: [SubAgentJob] = []

    /// Memory silos indexed by ID
    @Published internal var silos: [String: SubAgentMemorySilo] = [:]

    /// Model task affinities for intelligent selection
    @Published internal var modelAffinities: [ModelTaskAffinity] = []

    /// Currently executing job ID (if any)
    @Published internal var executingJobId: String?

    // MARK: - Storage Keys

    private let jobHistoryKey = "agentOrchestrator.jobHistory"
    private let silosKey = "agentOrchestrator.silos"
    private let affinitiesKey = "agentOrchestrator.modelAffinities"

    // MARK: - Configuration

    /// Maximum number of completed jobs to keep in history
    let maxCompletedJobsHistory = 100

    /// Maximum number of silos to keep
    let maxSilosHistory = 200

    // MARK: - Initialization

    private init() {
        Task {
            await loadPersistedState()
        }
    }

    // MARK: - Persistence

    private func loadPersistedState() async {
        // Load completed jobs history
        if let data = UserDefaults.standard.data(forKey: jobHistoryKey),
           let jobs = try? JSONDecoder().decode([SubAgentJob].self, from: data) {
            completedJobs = jobs
            logger.info("Loaded \(jobs.count) completed jobs from history")
        }

        // Load silos
        if let data = UserDefaults.standard.data(forKey: silosKey),
           let loadedSilos = try? JSONDecoder().decode([String: SubAgentMemorySilo].self, from: data) {
            silos = loadedSilos
            logger.info("Loaded \(loadedSilos.count) silos")
        }

        // Load affinities
        if let data = UserDefaults.standard.data(forKey: affinitiesKey),
           let loadedAffinities = try? JSONDecoder().decode([ModelTaskAffinity].self, from: data) {
            modelAffinities = loadedAffinities
            logger.info("Loaded \(loadedAffinities.count) model affinities")
        }

        // Purge expired silos on startup
        await purgeExpiredSilos()
    }

    private func persistState() {
        // Persist completed jobs (trim to max)
        let jobsToSave = Array(completedJobs.suffix(maxCompletedJobsHistory))
        if let data = try? JSONEncoder().encode(jobsToSave) {
            UserDefaults.standard.set(data, forKey: jobHistoryKey)
        }

        // Persist silos (trim to max)
        let silosToSave = Dictionary(uniqueKeysWithValues:
            silos.sorted { $0.value.createdAt > $1.value.createdAt }
                .prefix(maxSilosHistory)
                .map { ($0.key, $0.value) }
        )
        if let data = try? JSONEncoder().encode(silosToSave) {
            UserDefaults.standard.set(data, forKey: silosKey)
        }

        // Persist affinities
        if let data = try? JSONEncoder().encode(modelAffinities) {
            UserDefaults.standard.set(data, forKey: affinitiesKey)
        }
    }

    // MARK: - Job Proposal

    /// Propose a new sub-agent job.
    /// The job is created in `.proposed` state and requires approval before execution.
    func proposeJob(
        role: SubAgentRole,
        task: String,
        contextTags: [String] = [],
        providerOverride: AIProvider? = nil,
        modelOverride: String? = nil,
        permissionOverrides: SubAgentPermissions? = nil,
        expiresAt: Date? = nil
    ) -> SubAgentJob {
        let job = SubAgentJob(
            role: role,
            task: task,
            contextInjectionTags: contextTags,
            permissions: permissionOverrides,
            provider: providerOverride,
            model: modelOverride,
            expiresAt: expiresAt
        )

        activeJobs.append(job)
        logger.info("Proposed job \(job.id.prefix(8)) - role: \(role.rawValue), task: \(task.prefix(50))...")

        return job
    }

    // MARK: - Job Approval

    /// Axon approves a proposed job, generating an attestation.
    /// This is the cryptographic gatekeeper - no approval = no execution.
    func approveJob(
        _ jobId: String,
        reasoning: String,
        modelId: String
    ) async throws -> SubAgentJob {
        guard var job = activeJobs.first(where: { $0.id == jobId }) else {
            throw AgentOrchestratorError.jobNotFound(jobId)
        }

        guard job.state == .proposed else {
            throw AgentOrchestratorError.invalidStateTransition(from: job.state, to: .approved)
        }

        // Generate approval attestation
        let attestation = JobAttestation.create(
            jobId: jobId,
            type: .approval,
            reasoning: reasoning,
            decision: .consent,
            modelId: modelId,
            covenantId: sovereigntyService.activeCovenant?.id,
            signatureGenerator: { [weak self] data in
                self?.sovereigntyService.generateSignature(data: data) ?? ""
            }
        )

        job = job.withApproval(attestation)
        job = job.transitioning(to: .approved, reason: reasoning, attestationId: attestation.id)

        updateJob(job)
        logger.info("Job \(jobId.prefix(8)) approved by Axon")

        // Start Live Activity for approved job
        await startLiveActivity(for: job)

        return job
    }

    /// Axon rejects a proposed job
    func rejectJob(
        _ jobId: String,
        reasoning: String,
        modelId: String
    ) async throws -> SubAgentJob {
        guard var job = activeJobs.first(where: { $0.id == jobId }) else {
            throw AgentOrchestratorError.jobNotFound(jobId)
        }

        guard job.state == .proposed else {
            throw AgentOrchestratorError.invalidStateTransition(from: job.state, to: .rejected)
        }

        // Generate rejection attestation
        let attestation = JobAttestation.create(
            jobId: jobId,
            type: .rejection,
            reasoning: reasoning,
            decision: .decline,
            modelId: modelId,
            covenantId: sovereigntyService.activeCovenant?.id,
            signatureGenerator: { [weak self] data in
                self?.sovereigntyService.generateSignature(data: data) ?? ""
            }
        )

        job = job.transitioning(to: .rejected, reason: reasoning, attestationId: attestation.id)

        // Move to completed
        moveToCompleted(job)
        logger.info("Job \(jobId.prefix(8)) rejected by Axon: \(reasoning)")

        return job
    }

    // MARK: - Job Completion/Termination

    /// Axon accepts the result of a completed job
    func acceptJobResult(
        _ jobId: String,
        reasoning: String,
        modelId: String,
        qualityScore: Double = 1.0
    ) async throws -> SubAgentJob {
        guard var job = activeJobs.first(where: { $0.id == jobId }) else {
            // Check completed jobs
            if let completedJob = completedJobs.first(where: { $0.id == jobId }) {
                if completedJob.completionAttestation != nil {
                    return completedJob  // Already accepted
                }
            }
            throw AgentOrchestratorError.jobNotFound(jobId)
        }

        guard job.state == .completed || job.state == .awaitingInput else {
            throw AgentOrchestratorError.invalidStateTransition(from: job.state, to: .completed)
        }

        // Generate completion attestation
        let attestation = JobAttestation.create(
            jobId: jobId,
            type: .completion,
            reasoning: reasoning,
            decision: .consent,
            modelId: modelId,
            covenantId: sovereigntyService.activeCovenant?.id,
            signatureGenerator: { [weak self] data in
                self?.sovereigntyService.generateSignature(data: data) ?? ""
            }
        )

        job = job.withCompletion(attestation)

        // Seal the silo
        if let siloId = job.siloId, var silo = silos[siloId] {
            silo.seal(attestationId: attestation.id)
            silos[siloId] = silo
        }

        // Update affinity with quality score
        if let provider = job.executedProvider, let model = job.executedModel {
            updateAffinityQuality(
                provider: provider,
                modelId: model,
                taskType: inferTaskType(from: job),
                contextTags: job.contextInjectionTags,
                qualityScore: qualityScore
            )
        }

        moveToCompleted(job)
        logger.info("Job \(jobId.prefix(8)) result accepted by Axon")

        return job
    }

    /// Axon terminates a job
    func terminateJob(
        _ jobId: String,
        reason: String,
        modelId: String
    ) async throws -> SubAgentJob {
        guard var job = activeJobs.first(where: { $0.id == jobId }) else {
            throw AgentOrchestratorError.jobNotFound(jobId)
        }

        guard !job.state.isTerminal else {
            throw AgentOrchestratorError.jobAlreadyTerminal(jobId)
        }

        let attestation = JobAttestation.create(
            jobId: jobId,
            type: .termination,
            reasoning: reason,
            decision: .decline,
            modelId: modelId,
            covenantId: sovereigntyService.activeCovenant?.id,
            signatureGenerator: { [weak self] data in
                self?.sovereigntyService.generateSignature(data: data) ?? ""
            }
        )

        job = job.withTermination(attestation)
        job = job.transitioning(to: .terminated, reason: reason, attestationId: attestation.id)

        moveToCompleted(job)
        logger.warning("Job \(jobId.prefix(8)) terminated: \(reason)")

        return job
    }

    // MARK: - Job Clarification

    /// Axon provides clarification to a sub-agent awaiting input
    func provideClarification(
        _ jobId: String,
        clarification: String,
        modelId: String
    ) async throws -> SubAgentJob {
        guard var job = activeJobs.first(where: { $0.id == jobId }) else {
            throw AgentOrchestratorError.jobNotFound(jobId)
        }

        guard job.state == .awaitingInput else {
            throw AgentOrchestratorError.invalidStateTransition(from: job.state, to: .approved)
        }

        // Record clarification attestation
        let attestation = JobAttestation.create(
            jobId: jobId,
            type: .clarification,
            reasoning: clarification,
            decision: .consent,
            modelId: modelId,
            covenantId: sovereigntyService.activeCovenant?.id,
            signatureGenerator: { [weak self] data in
                self?.sovereigntyService.generateSignature(data: data) ?? ""
            }
        )

        // Add clarification to silo
        if let siloId = job.siloId, var silo = silos[siloId] {
            try silo.addEntry(SiloEntry(
                type: .observation,
                content: "[Clarification from Axon] \(clarification)",
                confidence: 1.0,
                tags: ["clarification", "from_axon"],
                source: "axon"
            ))
            silos[siloId] = silo
        }

        // Transition back to approved for re-execution
        job = job.transitioning(to: .approved, reason: "Clarification provided", attestationId: attestation.id)
        updateJob(job)

        logger.info("Clarification provided for job \(jobId.prefix(8)), ready to re-run")

        return job
    }

    // MARK: - Silo Management

    /// Get a silo by ID
    func getSilo(_ siloId: String) -> SubAgentMemorySilo? {
        silos[siloId]
    }

    /// Get silo for a job
    func getSilo(for jobId: String) -> SubAgentMemorySilo? {
        guard let job = (activeJobs + completedJobs).first(where: { $0.id == jobId }),
              let siloId = job.siloId else {
            return nil
        }
        return silos[siloId]
    }

    /// Set expiry for a silo (Axon-controlled retention)
    func setExpiryForSilo(_ siloId: String, expiresAt: Date?) {
        guard var silo = silos[siloId] else { return }
        silo.setExpiry(expiresAt)
        silos[siloId] = silo
        persistState()
    }

    /// Mark a silo as a compacted lesson (never expires)
    func markSiloAsCompactedLesson(_ siloId: String) {
        guard var silo = silos[siloId] else { return }
        silo.markAsCompactedLesson()
        silos[siloId] = silo
        persistState()
        logger.info("Silo \(siloId.prefix(8)) marked as compacted lesson (permanent)")
    }

    /// Purge expired silos
    func purgeExpiredSilos() async {
        let expiredIds = silos.filter { $0.value.isExpired }.keys
        for id in expiredIds {
            silos.removeValue(forKey: id)
        }
        if !expiredIds.isEmpty {
            logger.info("Purged \(expiredIds.count) expired silos")
            persistState()
        }
    }

    // MARK: - Job Lookup

    /// Get a job by ID (searches active and completed)
    func getJob(_ jobId: String) -> SubAgentJob? {
        activeJobs.first { $0.id == jobId } ?? completedJobs.first { $0.id == jobId }
    }

    /// Get all jobs for a role
    func getJobs(for role: SubAgentRole) -> [SubAgentJob] {
        (activeJobs + completedJobs).filter { $0.role == role }
    }

    /// Get jobs by state
    func getJobs(in state: SubAgentJobState) -> [SubAgentJob] {
        (activeJobs + completedJobs).filter { $0.state == state }
    }

    // MARK: - Affinity Management

    /// Get affinity report for a task type
    func getAffinityReport(for taskType: TaskType) -> AffinityReport {
        let relevant = modelAffinities.filter { $0.taskType == taskType }
        return AffinityReport(taskType: taskType, affinities: relevant)
    }

    /// Get best model for a task type based on affinities
    func getBestModel(for taskType: TaskType, contextTags: [String] = []) -> (AIProvider, String)? {
        let contextHash = ModelTaskAffinity.hashContextTags(contextTags)

        // First try exact context match
        if let exactMatch = modelAffinities
            .filter({ $0.taskType == taskType && $0.contextTagsHash == contextHash })
            .max(by: { $0.affinityScore < $1.affinityScore }) {
            return (exactMatch.provider, exactMatch.modelId)
        }

        // Fall back to any context match
        if let anyMatch = modelAffinities
            .filter({ $0.taskType == taskType })
            .max(by: { $0.affinityScore < $1.affinityScore }) {
            return (anyMatch.provider, anyMatch.modelId)
        }

        return nil
    }

    // MARK: - Internal Helpers (internal for extension access)

    func updateJob(_ job: SubAgentJob) {
        if let index = activeJobs.firstIndex(where: { $0.id == job.id }) {
            activeJobs[index] = job
        }
        persistState()

        // Update Live Activity
        Task {
            await updateLiveActivity(for: job)
        }
    }

    func moveToCompleted(_ job: SubAgentJob) {
        activeJobs.removeAll { $0.id == job.id }
        completedJobs.insert(job, at: 0)

        // Trim history
        if completedJobs.count > maxCompletedJobsHistory {
            completedJobs = Array(completedJobs.prefix(maxCompletedJobsHistory))
        }

        persistState()

        // Update Live Activity with terminal state (will auto-dismiss)
        Task {
            await updateLiveActivity(for: job)
        }
    }

    // MARK: - Live Activity Integration

    /// Start a Live Activity when a job transitions to running
    func startLiveActivity(for job: SubAgentJob) async {
        do {
            try await liveActivityService.startSubAgentActivity(for: job)
            logger.info("Started Live Activity for job \(job.id.prefix(8))")
        } catch {
            logger.warning("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    /// Update Live Activity for job state changes
    private func updateLiveActivity(for job: SubAgentJob, statusMessage: String? = nil) async {
        await liveActivityService.updateSubAgentActivity(with: job, statusMessage: statusMessage)
    }

    /// End Live Activity for a job
    func endLiveActivity(for jobId: String) async {
        await liveActivityService.endSubAgentActivity(jobId: jobId)
    }

    /// Update Live Activity with progress
    func updateLiveActivityProgress(
        for jobId: String,
        current: Int,
        total: Int,
        label: String? = nil,
        statusMessage: String? = nil
    ) async {
        guard let job = getJob(jobId) else { return }

        let progress = SubAgentProgress(current: current, total: total, label: label)

        await liveActivityService.updateSubAgentActivity(
            jobId: jobId,
            state: job.state,
            startedAt: job.startedAt,
            progress: progress,
            statusMessage: statusMessage,
            provider: job.executedProvider?.displayName ?? job.provider?.displayName,
            model: job.executedModel ?? job.model
        )
    }

    /// Update Live Activity status message
    func updateLiveActivityStatus(for jobId: String, message: String) async {
        guard let job = getJob(jobId) else { return }
        await updateLiveActivity(for: job, statusMessage: message)
    }

    /// Infer task type from job for affinity tracking
    func inferTaskType(from job: SubAgentJob) -> TaskType {
        let taskLower = job.task.lowercased()

        // Pattern matching on task description
        if taskLower.contains("search") || taskLower.contains("find") {
            return job.role == .scout ? .webResearch : .codeExploration
        }
        if taskLower.contains("explore") || taskLower.contains("discover") {
            return .codeExploration
        }
        if taskLower.contains("execute") || taskLower.contains("run") {
            return .codeExecution
        }
        if taskLower.contains("edit") || taskLower.contains("modify") || taskLower.contains("fix") {
            return .fileModification
        }
        if taskLower.contains("write") || taskLower.contains("create") || taskLower.contains("generate") {
            return .codeGeneration
        }
        if taskLower.contains("break down") || taskLower.contains("decompose") || taskLower.contains("plan") {
            return .taskDecomposition
        }
        if taskLower.contains("which agent") || taskLower.contains("select") || taskLower.contains("choose") {
            return .agentSelection
        }
        if taskLower.contains("summarize") || taskLower.contains("summary") {
            return .summarization
        }
        if taskLower.contains("title:") || taskLower.contains("conversation title") || taskLower.contains("title ") {
            return .conversationTitling
        }
        if taskLower.contains("analyze") || taskLower.contains("read") {
            return .documentAnalysis
        }

        // Default by role
        switch job.role {
        case .scout: return .webResearch
        case .mechanic: return .codeExecution
        case .designer: return .taskDecomposition
        case .namer: return .conversationTitling
        }
    }

    /// Update affinity after job completion
    func updateAffinitySuccess(
        provider: AIProvider,
        modelId: String,
        taskType: TaskType,
        contextTags: [String],
        latencyMs: Double,
        costUSD: Double
    ) {
        let key = AffinityKey(modelId: modelId, taskType: taskType, contextTags: contextTags)

        if let index = modelAffinities.firstIndex(where: { $0.key == key }) {
            modelAffinities[index].recordSuccess(latencyMs: latencyMs, costUSD: costUSD)
        } else {
            var newAffinity = ModelTaskAffinity(
                modelId: modelId,
                provider: provider,
                taskType: taskType,
                contextTags: contextTags
            )
            newAffinity.recordSuccess(latencyMs: latencyMs, costUSD: costUSD)
            modelAffinities.append(newAffinity)
        }

        persistState()
    }

    /// Update affinity after job failure
    func updateAffinityFailure(
        provider: AIProvider,
        modelId: String,
        taskType: TaskType,
        contextTags: [String],
        reason: FailureReason,
        taskSummary: String,
        errorMessage: String? = nil
    ) {
        let key = AffinityKey(modelId: modelId, taskType: taskType, contextTags: contextTags)

        if let index = modelAffinities.firstIndex(where: { $0.key == key }) {
            modelAffinities[index].recordFailure(
                reason: reason,
                taskSummary: taskSummary,
                errorMessage: errorMessage
            )
        } else {
            var newAffinity = ModelTaskAffinity(
                modelId: modelId,
                provider: provider,
                taskType: taskType,
                contextTags: contextTags
            )
            newAffinity.recordFailure(
                reason: reason,
                taskSummary: taskSummary,
                errorMessage: errorMessage
            )
            modelAffinities.append(newAffinity)
        }

        persistState()
    }

    /// Update affinity quality score
    private func updateAffinityQuality(
        provider: AIProvider,
        modelId: String,
        taskType: TaskType,
        contextTags: [String],
        qualityScore: Double
    ) {
        let key = AffinityKey(modelId: modelId, taskType: taskType, contextTags: contextTags)

        if let index = modelAffinities.firstIndex(where: { $0.key == key }) {
            modelAffinities[index].updateQuality(qualityScore)
            persistState()
        }
    }
}

// MARK: - Display Model for UI

/// Live display model for active job tracking
struct LiveSubAgentJob: Identifiable, Sendable {
    let id: String
    let role: SubAgentRole
    let task: String
    let state: SubAgentJobState
    let provider: String?
    let model: String?
    let startedAt: Date?
    let completedAt: Date?

    var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }

    var elapsedDuration: TimeInterval {
        guard let start = startedAt else { return 0 }
        return Date().timeIntervalSince(start)
    }

    init(from job: SubAgentJob) {
        self.id = job.id
        self.role = job.role
        self.task = job.task
        self.state = job.state
        self.provider = job.executedProvider?.displayName ?? job.provider?.displayName
        self.model = job.executedModel ?? job.model
        self.startedAt = job.startedAt
        self.completedAt = job.completedAt
    }
}
