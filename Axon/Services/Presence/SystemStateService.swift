//
//  SystemStateService.swift
//  Axon
//
//  Service for saving and restoring full system state snapshots.
//  Enables seamless device handoffs with complete agent context preservation.
//

import Foundation
import CoreData
import Combine

@MainActor
final class SystemStateService: ObservableObject {
    static let shared = SystemStateService()

    // MARK: - Dependencies

    private let persistence = PersistenceController.shared
    private let deviceIdentity = DeviceIdentity.shared
    private let agentStateService = AgentStateService.shared
    private let conversationService = ConversationService.shared

    // MARK: - Published State

    /// The most recent snapshot for this device
    @Published private(set) var latestSnapshot: SystemStateSnapshot?

    /// All available snapshots (for debugging/UI)
    @Published private(set) var allSnapshots: [SystemStateSnapshot] = []

    /// Whether a save operation is in progress
    @Published private(set) var isSaving = false

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    private var heartbeatSequenceNumber = 0

    // MARK: - Initialization

    private init() {
        Task {
            await loadLatestSnapshot()
        }
    }

    // MARK: - Snapshot Creation

    /// Create a system state snapshot for the current device
    func createSnapshot(
        trigger: SnapshotTrigger,
        sourceDeviceId: String? = nil,
        transferReason: TransferReason? = nil,
        doorPolicyUsed: DoorPolicy? = nil
    ) async throws -> SystemStateSnapshot {
        let deviceId = deviceIdentity.getDeviceId()

        // Gather internal thread entries (most recent 10)
        let recentEntries = agentStateService.queryEntries(limit: 10, includeAIOnly: true)
        let entrySummaries = recentEntries.map { entry in
            InternalThreadEntrySummary(
                id: entry.id,
                kind: entry.kind.rawValue,
                contentPreview: String(entry.content.prefix(100)),
                timestamp: entry.timestamp,
                visibility: entry.visibility.rawValue
            )
        }

        // Get active covenant info
        let activeCovenant = SovereigntyService.shared.activeCovenant
        let trustTierSummary: TrustTierSummary?
        if let covenant = activeCovenant {
            let activeTiers = covenant.trustTiers.filter { $0.isActive }
            if let firstTier = activeTiers.first {
                let preApprovedActions = firstTier.allowedActions.map { $0.category.rawValue }
                trustTierSummary = TrustTierSummary(
                    activeTierId: firstTier.id,
                    preApprovedActions: preApprovedActions,
                    expiresAt: firstTier.expiresAt
                )
            } else {
                trustTierSummary = nil
            }
        } else {
            trustTierSummary = nil
        }

        // Get conversation state
        let activeConversation = conversationService.currentConversation
        let messages = conversationService.messages

        let lastUserMessage = messages.last { $0.role == .user }?.content
        let lastAgentResponse = messages.last { $0.role == .assistant }?.content

        // Get pending tool approvals (simplified for now)
        let pendingApprovals: [PendingToolApprovalSummary] = []

        // Extract current task context from recent internal thread
        let taskContext = recentEntries.first { $0.kind == .plan }?.content

        // Extract active topics from recent entries
        let activeTopics = extractActiveTopics(from: recentEntries)

        // Get last heartbeat summary
        let lastHeartbeat = recentEntries.first { $0.kind == .heartbeatSnapshot }
        let heartbeatSummary = lastHeartbeat?.content

        // Increment sequence number
        heartbeatSequenceNumber += 1

        // Get remote work state from DevicePresenceService
        let presenceService = DevicePresenceService.shared
        let activeRemoteTask = presenceService.activeRemoteTask
        let pendingRemoteApprovals = presenceService.pendingRemoteApprovals

        let snapshot = SystemStateSnapshot(
            deviceId: deviceId,
            recentInternalThreadEntries: entrySummaries,
            activeCovenantId: activeCovenant?.id,
            trustTierSummary: trustTierSummary,
            activeConversationId: activeConversation?.id,
            activeConversationTitle: activeConversation?.title,
            conversationPosition: messages.count,
            pendingToolApprovals: pendingApprovals,
            lastUserMessage: lastUserMessage,
            lastAgentResponse: lastAgentResponse,
            currentTaskContext: taskContext,
            activeTopics: activeTopics,
            lastHeartbeatSummary: heartbeatSummary,
            heartbeatSequenceNumber: heartbeatSequenceNumber,
            sourceDeviceId: sourceDeviceId,
            transferReason: transferReason,
            doorPolicyUsed: doorPolicyUsed,
            activeRemoteTask: activeRemoteTask,
            pendingRemoteApprovals: pendingRemoteApprovals
        )

        // Save to Core Data
        try await saveSnapshot(snapshot)

        print("[SystemStateService] Created snapshot: \(snapshot.id) (trigger: \(trigger.displayName))")

        return snapshot
    }

    // MARK: - Save Operations

    /// Save a snapshot triggered by app backgrounding
    func saveOnBackground() async throws -> SystemStateSnapshot {
        return try await createSnapshot(trigger: .appBackground)
    }

    /// Save a snapshot before device handoff
    func saveForHandoff(targetDeviceId: String, reason: TransferReason) async throws -> SystemStateSnapshot {
        return try await createSnapshot(
            trigger: .handoffPrepare,
            sourceDeviceId: deviceIdentity.getDeviceId(),
            transferReason: reason
        )
    }

    /// Save a periodic checkpoint
    func savePeriodicCheckpoint() async throws -> SystemStateSnapshot {
        return try await createSnapshot(trigger: .periodic)
    }

    /// Save a heartbeat snapshot
    func saveHeartbeatSnapshot() async throws -> SystemStateSnapshot {
        return try await createSnapshot(trigger: .heartbeat)
    }

    /// Save a user-initiated checkpoint
    func saveUserCheckpoint() async throws -> SystemStateSnapshot {
        return try await createSnapshot(trigger: .userInitiated)
    }

    /// Save an agent-requested checkpoint
    func saveAgentCheckpoint() async throws -> SystemStateSnapshot {
        return try await createSnapshot(trigger: .agentCheckpoint)
    }

    // MARK: - Load Operations

    /// Load the latest snapshot for this device
    func loadLatestSnapshot() async {
        let deviceId = deviceIdentity.getDeviceId()
        let context = persistence.container.viewContext

        let fetchRequest: NSFetchRequest<SystemStateSnapshotEntity> = SystemStateSnapshotEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceId == %@ AND isActive == YES", deviceId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = 1

        do {
            if let entity = try context.fetch(fetchRequest).first {
                latestSnapshot = mapEntityToSnapshot(entity)
            }
        } catch {
            print("[SystemStateService] Error loading latest snapshot: \(error)")
        }
    }

    /// Load a specific snapshot by ID
    func loadSnapshot(id: String) async -> SystemStateSnapshot? {
        let context = persistence.container.viewContext

        let fetchRequest: NSFetchRequest<SystemStateSnapshotEntity> = SystemStateSnapshotEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        fetchRequest.fetchLimit = 1

        do {
            if let entity = try context.fetch(fetchRequest).first {
                return mapEntityToSnapshot(entity)
            }
        } catch {
            print("[SystemStateService] Error loading snapshot \(id): \(error)")
        }

        return nil
    }

    /// Load the latest snapshot from a specific device (for handoffs)
    func loadSnapshotFromDevice(deviceId: String) async -> SystemStateSnapshot? {
        let context = persistence.container.viewContext

        let fetchRequest: NSFetchRequest<SystemStateSnapshotEntity> = SystemStateSnapshotEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceId == %@ AND isActive == YES", deviceId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        fetchRequest.fetchLimit = 1

        do {
            if let entity = try context.fetch(fetchRequest).first {
                return mapEntityToSnapshot(entity)
            }
        } catch {
            print("[SystemStateService] Error loading snapshot from device \(deviceId): \(error)")
        }

        return nil
    }

    /// Load all active snapshots
    func loadAllSnapshots() async {
        let context = persistence.container.viewContext

        let fetchRequest: NSFetchRequest<SystemStateSnapshotEntity> = SystemStateSnapshotEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isActive == YES")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let entities = try context.fetch(fetchRequest)
            allSnapshots = entities.compactMap { mapEntityToSnapshot($0) }
        } catch {
            print("[SystemStateService] Error loading all snapshots: \(error)")
        }
    }

    // MARK: - Entry Context Generation

    /// Generate entry context for agent prompt when entering a device
    func generateEntryContext(
        fromSnapshot snapshot: SystemStateSnapshot,
        currentDeviceName: String,
        previousDeviceName: String?
    ) -> String {
        return snapshot.generateEntryContext(
            currentDeviceName: currentDeviceName,
            previousDeviceName: previousDeviceName
        )
    }

    // MARK: - Cleanup

    /// Clean up old snapshots based on retention settings
    func cleanupOldSnapshots() async {
        let settings = SettingsViewModel.shared.settings.presenceSettings
        let retentionSeconds = settings.stateRetentionSeconds

        // 0 means keep forever
        guard retentionSeconds > 0 else { return }

        let cutoffDate = Date().addingTimeInterval(-Double(retentionSeconds))
        let context = persistence.newBackgroundContext()

        await context.perform {
            let fetchRequest: NSFetchRequest<SystemStateSnapshotEntity> = SystemStateSnapshotEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)

            do {
                let oldSnapshots = try context.fetch(fetchRequest)
                for snapshot in oldSnapshots {
                    context.delete(snapshot)
                }
                try context.save()
                print("[SystemStateService] Cleaned up \(oldSnapshots.count) old snapshots")
            } catch {
                print("[SystemStateService] Error cleaning up old snapshots: \(error)")
            }
        }
    }

    /// Mark all snapshots for a device as inactive (after handoff)
    func deactivateSnapshotsForDevice(deviceId: String) async {
        let context = persistence.newBackgroundContext()

        await context.perform {
            let fetchRequest: NSFetchRequest<SystemStateSnapshotEntity> = SystemStateSnapshotEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deviceId == %@ AND isActive == YES", deviceId)

            do {
                let activeSnapshots = try context.fetch(fetchRequest)
                for snapshot in activeSnapshots {
                    snapshot.isActive = false
                }
                try context.save()
            } catch {
                print("[SystemStateService] Error deactivating snapshots: \(error)")
            }
        }
    }

    // MARK: - Private Helpers

    private func saveSnapshot(_ snapshot: SystemStateSnapshot) async throws {
        isSaving = true
        defer { isSaving = false }

        let context = persistence.newBackgroundContext()

        try await context.perform {
            // Deactivate previous active snapshots for this device
            let deactivateFetch: NSFetchRequest<SystemStateSnapshotEntity> = SystemStateSnapshotEntity.fetchRequest()
            deactivateFetch.predicate = NSPredicate(
                format: "deviceId == %@ AND isActive == YES",
                snapshot.deviceId
            )

            let oldActive = try context.fetch(deactivateFetch)
            for old in oldActive {
                old.isActive = false
            }

            // Create new snapshot entity
            let entity = SystemStateSnapshotEntity(context: context)
            entity.id = snapshot.id
            entity.deviceId = snapshot.deviceId
            entity.timestamp = snapshot.timestamp
            entity.version = Int32(snapshot.version)
            entity.sourceDeviceId = snapshot.sourceDeviceId
            entity.transferReason = snapshot.transferReason?.rawValue
            entity.isActive = true

            // Serialize full snapshot to JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(snapshot)
            entity.snapshotJSON = String(data: jsonData, encoding: .utf8) ?? "{}"

            try context.save()
        }

        // Update local state
        latestSnapshot = snapshot
    }

    private func mapEntityToSnapshot(_ entity: SystemStateSnapshotEntity) -> SystemStateSnapshot? {
        guard let jsonString = entity.snapshotJSON,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(SystemStateSnapshot.self, from: jsonData)
        } catch {
            print("[SystemStateService] Error decoding snapshot: \(error)")
            return nil
        }
    }

    private func extractActiveTopics(from entries: [InternalThreadEntry]) -> [String] {
        // Extract topics from tags in recent entries
        var topics = Set<String>()

        for entry in entries.prefix(5) {
            for tag in entry.tags {
                if !tag.hasPrefix("system:") && !tag.hasPrefix("_") {
                    topics.insert(tag)
                }
            }
        }

        return Array(topics.prefix(5))
    }
}

// MARK: - Snapshot Restoration

extension SystemStateService {
    /// Restore context from a snapshot when entering a device
    func restoreFromSnapshot(_ snapshot: SystemStateSnapshot) async throws {
        print("[SystemStateService] Restoring from snapshot: \(snapshot.id)")

        // Update the presence service with the snapshot
        let presenceService = DevicePresenceService.shared
        presenceService.setLastSnapshot(snapshot)

        // If there's an active conversation, try to load it
        if let conversationId = snapshot.activeConversationId {
            do {
                _ = try await conversationService.getConversation(id: conversationId)
                _ = try await conversationService.getMessages(conversationId: conversationId)
                print("[SystemStateService] Restored conversation: \(conversationId)")
            } catch {
                print("[SystemStateService] Could not restore conversation: \(error)")
            }
        }

        // Log the restoration for internal thread
        try await agentStateService.appendEntry(
            kind: .system,
            content: "Device transition: Restored context from \(snapshot.sourceDeviceId ?? "unknown device")",
            tags: ["system:device_transition", "restore"],
            visibility: .aiOnly,
            origin: .system,
            skipConsent: true
        )
    }
}
