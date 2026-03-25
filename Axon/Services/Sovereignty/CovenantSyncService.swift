//
//  CovenantSyncService.swift
//  Axon
//
//  iCloud sync for sovereignty state snapshots.
//  Account-scoped sync: snapshots from any of the user's devices can be
//  merged and applied locally by SovereigntyService.
//

import Foundation
import Combine
import os.log

// MARK: - V2 Snapshot Models

/// Full sovereignty snapshot synced per device.
struct SyncableSovereigntyState: Codable, Identifiable, Equatable {
    let id: String
    let sourceDeviceId: String
    let sourceDeviceName: String
    let activeCovenant: Covenant?
    let covenantHistory: [Covenant]
    let deadlockState: DeadlockState?
    let pendingProposals: [CovenantProposal]
    let comprehensionCompleted: Bool
    let lastModified: Date

    init(
        sourceDeviceId: String,
        sourceDeviceName: String,
        activeCovenant: Covenant?,
        covenantHistory: [Covenant],
        deadlockState: DeadlockState?,
        pendingProposals: [CovenantProposal],
        comprehensionCompleted: Bool,
        lastModified: Date
    ) {
        self.id = sourceDeviceId
        self.sourceDeviceId = sourceDeviceId
        self.sourceDeviceName = sourceDeviceName
        self.activeCovenant = activeCovenant
        self.covenantHistory = covenantHistory
        self.deadlockState = deadlockState
        self.pendingProposals = pendingProposals
        self.comprehensionCompleted = comprehensionCompleted
        self.lastModified = lastModified
    }
}

/// Container for per-device sovereignty snapshots.
struct SyncedSovereigntyStateStoreV2: Codable, Equatable {
    var snapshots: [String: SyncableSovereigntyState] // keyed by sourceDeviceId
    var lastSyncTime: Date

    init() {
        self.snapshots = [:]
        self.lastSyncTime = Date()
    }

    init(snapshots: [String: SyncableSovereigntyState], lastSyncTime: Date) {
        self.snapshots = snapshots
        self.lastSyncTime = lastSyncTime
    }

    static func isSnapshotMoreRecent(
        _ lhs: SyncableSovereigntyState,
        than rhs: SyncableSovereigntyState
    ) -> Bool {
        if lhs.lastModified != rhs.lastModified {
            return lhs.lastModified > rhs.lastModified
        }
        return lhs.sourceDeviceId < rhs.sourceDeviceId
    }

    func sortedSnapshotsByRecency() -> [SyncableSovereigntyState] {
        snapshots.values.sorted { lhs, rhs in
            Self.isSnapshotMoreRecent(lhs, than: rhs)
        }
    }

    var latestSnapshot: SyncableSovereigntyState? {
        sortedSnapshotsByRecency().first
    }
}

// MARK: - Legacy Models (v1 migration)

struct LegacySyncableCovenant: Codable, Identifiable {
    let id: String
    let deviceId: String
    let deviceName: String
    let covenant: Covenant
    let lastModified: Date
}

struct LegacySyncedCovenantStore: Codable {
    var covenants: [String: LegacySyncableCovenant]
    var lastSyncTime: Date
}

// MARK: - Covenant Sync Service

@MainActor
final class CovenantSyncService: ObservableObject {
    static let shared = CovenantSyncService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "CovenantSync")
    private let kvStore = NSUbiquitousKeyValueStore.default
    private let deviceIdentity = DeviceIdentity.shared
    private var cancellables = Set<AnyCancellable>()

    // Storage keys
    private let sovereigntyStateStoreV2Key = "sovereignty.stateStore.v2"
    private let legacyCovenantStoreKey = "sovereignty.covenantStore"

    // Published state
    @Published private(set) var isAvailable = false
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var syncError: String?
    @Published private(set) var allDeviceSnapshots: [String: SyncableSovereigntyState] = [:]
    @Published private(set) var latestCloudState: SyncableSovereigntyState?

    // Notification for sovereignty state changes from cloud
    let stateChangedFromCloud = PassthroughSubject<SyncableSovereigntyState, Never>()

    private init() {
        checkAvailability()
        setupChangeNotifications()
        loadFromCloud()
    }

    // MARK: - Availability

    private func checkAvailability() {
        isAvailable = kvStore.synchronize()
        logger.info("Covenant sync available: \(self.isAvailable)")
    }

    // MARK: - Change Notifications

    private func setupChangeNotifications() {
        NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleExternalChange(notification)
            }
            .store(in: &cancellables)

        kvStore.synchronize()
    }

    private func handleExternalChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            logger.info("Covenant sync: external change detected for keys: \(changedKeys)")
            if changedKeys.contains(sovereigntyStateStoreV2Key) || changedKeys.contains(legacyCovenantStoreKey) {
                loadFromCloud()
            }

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            logger.warning("Covenant sync: quota exceeded")
            syncError = "iCloud storage quota exceeded for covenants"

        case NSUbiquitousKeyValueStoreAccountChange:
            logger.info("Covenant sync: iCloud account changed")
            checkAvailability()

        default:
            break
        }
    }

    // MARK: - Save State to Cloud

    /// Save a full sovereignty snapshot to iCloud.
    func saveStateToCloud(_ snapshot: SyncableSovereigntyState) {
        guard isAvailable else {
            logger.warning("Covenant sync not available - skipping cloud save")
            return
        }

        var store = loadSovereigntyStore() ?? SyncedSovereigntyStateStoreV2()
        store.snapshots[snapshot.sourceDeviceId] = snapshot
        store.lastSyncTime = Date()

        saveSovereigntyStore(store)
        logger.info("Saved sovereignty snapshot to iCloud for device \(snapshot.sourceDeviceName)")
    }

    /// Convenience for writing current-device snapshot.
    func saveCurrentDeviceState(
        activeCovenant: Covenant?,
        covenantHistory: [Covenant],
        deadlockState: DeadlockState?,
        pendingProposals: [CovenantProposal],
        comprehensionCompleted: Bool,
        lastModified: Date
    ) {
        let deviceId = deviceIdentity.getDeviceId()
        let deviceName = deviceIdentity.getDeviceInfo()?.deviceName ?? "Unknown Device"
        let snapshot = SyncableSovereigntyState(
            sourceDeviceId: deviceId,
            sourceDeviceName: deviceName,
            activeCovenant: activeCovenant,
            covenantHistory: covenantHistory,
            deadlockState: deadlockState,
            pendingProposals: pendingProposals,
            comprehensionCompleted: comprehensionCompleted,
            lastModified: lastModified
        )
        saveStateToCloud(snapshot)
    }

    /// Remove the current device snapshot from iCloud.
    func removeCurrentDeviceStateFromCloud() {
        guard isAvailable else { return }

        let deviceId = deviceIdentity.getDeviceId()
        var store = loadSovereigntyStore() ?? SyncedSovereigntyStateStoreV2()
        store.snapshots.removeValue(forKey: deviceId)
        store.lastSyncTime = Date()

        saveSovereigntyStore(store)
        logger.info("Removed sovereignty snapshot from iCloud for device \(deviceId)")
    }

    /// Clear both v2 and legacy covenant sync keys from iCloud KV.
    func clearCloudStateStore() {
        kvStore.removeObject(forKey: sovereigntyStateStoreV2Key)
        kvStore.removeObject(forKey: legacyCovenantStoreKey)
        kvStore.synchronize()
        allDeviceSnapshots = [:]
        latestCloudState = nil
        lastSyncTime = nil
    }

    // MARK: - Load from Cloud

    private func loadFromCloud() {
        guard let store = loadSovereigntyStore() else {
            logger.info("No sovereignty state store found in iCloud")
            return
        }

        lastSyncTime = store.lastSyncTime
        allDeviceSnapshots = store.snapshots

        if let latestSnapshot = store.latestSnapshot {
            latestCloudState = latestSnapshot
            stateChangedFromCloud.send(latestSnapshot)
        }

        syncError = nil
        logger.info("Loaded \(store.snapshots.count) sovereignty snapshots from iCloud")
    }

    // MARK: - Storage Helpers

    private func loadSovereigntyStore() -> SyncedSovereigntyStateStoreV2? {
        if let store = loadV2Store() {
            return store
        }
        if let migrated = migrateLegacyStoreIfNeeded() {
            saveSovereigntyStore(migrated)
            return migrated
        }
        return nil
    }

    private func loadV2Store() -> SyncedSovereigntyStateStoreV2? {
        guard let data = kvStore.data(forKey: sovereigntyStateStoreV2Key) else { return nil }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(SyncedSovereigntyStateStoreV2.self, from: data)
        } catch {
            logger.error("Failed to decode sovereignty state store v2: \(error.localizedDescription)")
            syncError = "Failed to load sovereignty sync data: \(error.localizedDescription)"
            return nil
        }
    }

    private func migrateLegacyStoreIfNeeded() -> SyncedSovereigntyStateStoreV2? {
        guard let data = kvStore.data(forKey: legacyCovenantStoreKey) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let legacyStore = try decoder.decode(LegacySyncedCovenantStore.self, from: data)
            logger.info("Migrating legacy covenant store with \(legacyStore.covenants.count) entries")
            return Self.migrateLegacyStoreToV2(legacyStore)
        } catch {
            logger.error("Failed to decode legacy covenant store: \(error.localizedDescription)")
            syncError = "Failed to migrate legacy covenant sync data: \(error.localizedDescription)"
            return nil
        }
    }

    static func migrateLegacyStoreToV2(_ legacyStore: LegacySyncedCovenantStore) -> SyncedSovereigntyStateStoreV2 {
        var snapshots: [String: SyncableSovereigntyState] = [:]
        let grouped = Dictionary(grouping: legacyStore.covenants.values, by: { $0.deviceId })

        for (deviceId, covenantsForDevice) in grouped {
            let sorted = covenantsForDevice.sorted { lhs, rhs in
                if lhs.lastModified != rhs.lastModified {
                    return lhs.lastModified > rhs.lastModified
                }
                return lhs.id < rhs.id
            }

            guard let latest = sorted.first else { continue }

            let history = Array(sorted.dropFirst()).map { $0.covenant }.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                if lhs.version != rhs.version {
                    return lhs.version < rhs.version
                }
                return lhs.id < rhs.id
            }

            snapshots[deviceId] = SyncableSovereigntyState(
                sourceDeviceId: deviceId,
                sourceDeviceName: latest.deviceName,
                activeCovenant: latest.covenant,
                covenantHistory: history,
                deadlockState: nil,
                pendingProposals: [],
                comprehensionCompleted: false,
                lastModified: latest.lastModified
            )
        }

        return SyncedSovereigntyStateStoreV2(
            snapshots: snapshots,
            lastSyncTime: legacyStore.lastSyncTime
        )
    }

    private func saveSovereigntyStore(_ store: SyncedSovereigntyStateStoreV2) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(store)

            kvStore.set(data, forKey: sovereigntyStateStoreV2Key)
            kvStore.synchronize()

            lastSyncTime = store.lastSyncTime
            allDeviceSnapshots = store.snapshots
            latestCloudState = store.latestSnapshot
            syncError = nil
        } catch {
            logger.error("Failed to save sovereignty state store: \(error.localizedDescription)")
            syncError = "Failed to save sovereignty sync data: \(error.localizedDescription)"
        }
    }

    // MARK: - Manual Sync / Query

    func forceSync() {
        kvStore.synchronize()
        checkAvailability()

        if isAvailable {
            loadFromCloud()
        }
    }

    func latestStateFromCloud() -> SyncableSovereigntyState? {
        guard let store = loadSovereigntyStore() else { return nil }
        return store.latestSnapshot
    }
}
