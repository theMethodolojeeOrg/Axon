//
//  CovenantSyncService.swift
//  Axon
//
//  iCloud sync for covenants with device-scoping.
//  Syncs all covenants across devices but only applies covenants
//  that pertain to the current device.
//

import Foundation
import Combine
import os.log

// MARK: - Syncable Covenant

/// A covenant wrapper that includes device information for scoping
struct SyncableCovenant: Codable, Identifiable {
    let id: String
    let deviceId: String
    let deviceName: String
    let covenant: Covenant
    let lastModified: Date

    init(covenant: Covenant, deviceId: String, deviceName: String) {
        self.id = covenant.id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.covenant = covenant
        self.lastModified = Date()
    }
}

/// Container for all synced covenants across devices
struct SyncedCovenantStore: Codable {
    var covenants: [String: SyncableCovenant] // keyed by covenant ID
    var lastSyncTime: Date

    init() {
        self.covenants = [:]
        self.lastSyncTime = Date()
    }

    /// Get covenants for a specific device
    func covenants(forDevice deviceId: String) -> [SyncableCovenant] {
        covenants.values.filter { $0.deviceId == deviceId }
    }

    /// Get all covenants grouped by device
    func covenantsByDevice() -> [String: [SyncableCovenant]] {
        Dictionary(grouping: covenants.values, by: { $0.deviceId })
    }

    /// Get the most recent covenant for a device
    func latestCovenant(forDevice deviceId: String) -> SyncableCovenant? {
        covenants(forDevice: deviceId)
            .sorted { $0.lastModified > $1.lastModified }
            .first
    }
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
    private let covenantStoreKey = "sovereignty.covenantStore"

    // Published state
    @Published private(set) var isAvailable = false
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var syncError: String?
    @Published private(set) var allDeviceCovenants: [String: [SyncableCovenant]] = [:]

    // Notification for covenant changes from other devices
    let covenantChangedFromCloud = PassthroughSubject<SyncableCovenant, Never>()

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
            if changedKeys.contains(covenantStoreKey) {
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

    // MARK: - Save Covenant to Cloud

    /// Save a covenant to iCloud, scoped to the current device
    func saveCovenantToCloud(_ covenant: Covenant) {
        guard isAvailable else {
            logger.warning("Covenant sync not available - skipping cloud save")
            return
        }

        let deviceId = deviceIdentity.getDeviceId()
        let deviceName = deviceIdentity.getDeviceInfo()?.deviceName ?? "Unknown Device"

        let syncable = SyncableCovenant(
            covenant: covenant,
            deviceId: deviceId,
            deviceName: deviceName
        )

        // Load existing store
        var store = loadCovenantStore() ?? SyncedCovenantStore()

        // Update or add the covenant
        store.covenants[covenant.id] = syncable
        store.lastSyncTime = Date()

        // Save back to cloud
        saveCovenantStore(store)

        logger.info("Covenant \(covenant.id) saved to iCloud for device \(deviceName)")
    }

    /// Remove a covenant from iCloud
    func removeCovenantFromCloud(_ covenantId: String) {
        guard isAvailable else { return }

        var store = loadCovenantStore() ?? SyncedCovenantStore()
        store.covenants.removeValue(forKey: covenantId)
        store.lastSyncTime = Date()

        saveCovenantStore(store)

        logger.info("Covenant \(covenantId) removed from iCloud")
    }

    // MARK: - Load from Cloud

    private func loadFromCloud() {
        guard let store = loadCovenantStore() else {
            logger.info("No covenant store found in iCloud")
            return
        }

        lastSyncTime = store.lastSyncTime
        allDeviceCovenants = store.covenantsByDevice()

        // Check if there's a newer covenant for this device from another sync
        let currentDeviceId = deviceIdentity.getDeviceId()
        if let latestForDevice = store.latestCovenant(forDevice: currentDeviceId) {
            // Notify that a covenant was received from cloud
            covenantChangedFromCloud.send(latestForDevice)
        }

        syncError = nil
        logger.info("Loaded \(store.covenants.count) covenants from iCloud")
    }

    // MARK: - Storage Helpers

    private func loadCovenantStore() -> SyncedCovenantStore? {
        guard let data = kvStore.data(forKey: covenantStoreKey) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(SyncedCovenantStore.self, from: data)
        } catch {
            logger.error("Failed to decode covenant store: \(error.localizedDescription)")
            syncError = "Failed to load covenants: \(error.localizedDescription)"
            return nil
        }
    }

    private func saveCovenantStore(_ store: SyncedCovenantStore) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(store)

            kvStore.set(data, forKey: covenantStoreKey)
            kvStore.synchronize()

            lastSyncTime = store.lastSyncTime
            allDeviceCovenants = store.covenantsByDevice()
            syncError = nil
        } catch {
            logger.error("Failed to save covenant store: \(error.localizedDescription)")
            syncError = "Failed to save covenants: \(error.localizedDescription)"
        }
    }

    // MARK: - Manual Sync

    func forceSync() {
        kvStore.synchronize()
        checkAvailability()

        if isAvailable {
            loadFromCloud()
        }
    }

    // MARK: - Device Info

    /// Get all devices that have covenants
    func devicesWithCovenants() -> [(deviceId: String, deviceName: String, covenantCount: Int)] {
        var result: [(String, String, Int)] = []

        for (deviceId, covenants) in allDeviceCovenants {
            let deviceName = covenants.first?.deviceName ?? "Unknown Device"
            result.append((deviceId, deviceName, covenants.count))
        }

        return result.sorted { $0.1 < $1.1 }
    }

    /// Check if the current device has a synced covenant
    func hasCovenantForCurrentDevice() -> Bool {
        let currentDeviceId = deviceIdentity.getDeviceId()
        return allDeviceCovenants[currentDeviceId]?.isEmpty == false
    }

    /// Get the latest covenant for the current device from cloud
    func latestCovenantForCurrentDevice() -> Covenant? {
        let currentDeviceId = deviceIdentity.getDeviceId()
        guard let store = loadCovenantStore() else { return nil }
        return store.latestCovenant(forDevice: currentDeviceId)?.covenant
    }
}
