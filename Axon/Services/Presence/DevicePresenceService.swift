//
//  DevicePresenceService.swift
//  Axon
//
//  Core service for multi-device presence management.
//  Implements the "doors" paradigm for agent movement between device "rooms".
//

import Foundation
import CoreData
import Combine

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class DevicePresenceService: ObservableObject {
    static let shared = DevicePresenceService()

    // MARK: - Dependencies

    private let persistence = PersistenceController.shared
    private let deviceIdentity = DeviceIdentity.shared

    // MARK: - Published State

    /// The current device's presence
    @Published private(set) var currentDevice: DevicePresence?

    /// All registered devices
    @Published private(set) var allDevices: [DevicePresence] = []

    /// The currently active device (where agent is)
    @Published private(set) var activeDevice: DevicePresence?

    /// Whether this device is currently active
    @Published private(set) var isActive: Bool = false

    /// Pending remote approvals for this device to respond to
    @Published private(set) var pendingRemoteApprovals: [RemoteToolApproval] = []

    /// Active remote task (if agent is working elsewhere)
    @Published private(set) var activeRemoteTask: RemoteTaskContext?

    /// Last state snapshot for this device
    @Published private(set) var lastSnapshot: SystemStateSnapshot?

    // MARK: - Private State

    private var cancellables = Set<AnyCancellable>()
    private var lastSyncTime: Date?

    // MARK: - Initialization

    private init() {
        Task {
            await initialize()
        }
    }

    private func initialize() async {
        // Register this device
        do {
            try await registerCurrentDevice()
            await loadAllDevices()
            await syncPresenceState()
        } catch {
            print("[DevicePresenceService] Initialization error: \(error)")
        }
    }

    // MARK: - Device Registration

    /// Register the current device in the presence system
    func registerCurrentDevice() async throws {
        let deviceId = deviceIdentity.getDeviceId()
        guard let deviceInfo = deviceIdentity.getDeviceInfo() else {
            throw PresenceError.deviceInfoUnavailable
        }

        let context = persistence.newBackgroundContext()

        try await context.perform {
            // Check if device already exists
            let fetchRequest: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deviceId == %@", deviceId)

            let existing = try context.fetch(fetchRequest)

            let entity: DevicePresenceEntity
            if let existingEntity = existing.first {
                entity = existingEntity
            } else {
                entity = DevicePresenceEntity(context: context)
                entity.deviceId = deviceId
            }

            // Update device info
            entity.deviceName = deviceInfo.deviceName
            entity.platform = DevicePlatform.current.rawValue
            entity.osVersion = deviceInfo.systemVersion
            entity.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            entity.updatedAt = Date()

            // Set capabilities and constraints
            let (capabilities, constraints) = self.detectCapabilitiesAndConstraints()
            entity.capabilitiesJSON = try? JSONEncoder().encode(capabilities).base64EncodedString()
            entity.constraintsJSON = try? JSONEncoder().encode(constraints).base64EncodedString()

            try context.save()
        }

        // Load current device
        await loadCurrentDevice()

        print("[DevicePresenceService] Registered device: \(deviceId)")
    }

    /// Load the current device from Core Data
    private func loadCurrentDevice() async {
        let deviceId = deviceIdentity.getDeviceId()
        let context = persistence.container.viewContext

        let fetchRequest: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceId == %@", deviceId)

        do {
            if let entity = try context.fetch(fetchRequest).first {
                var presence = mapEntityToPresence(entity)
                presence.isCurrentDevice = true
                self.currentDevice = presence
                self.isActive = presence.presenceState == .active
            }
        } catch {
            print("[DevicePresenceService] Error loading current device: \(error)")
        }
    }

    /// Load all devices from Core Data
    func loadAllDevices() async {
        let context = persistence.container.viewContext
        let currentDeviceId = deviceIdentity.getDeviceId()

        let fetchRequest: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "lastActiveAt", ascending: false)]

        do {
            let entities = try context.fetch(fetchRequest)
            self.allDevices = entities.map { entity in
                var presence = mapEntityToPresence(entity)
                presence.isCurrentDevice = (entity.deviceId == currentDeviceId)
                return presence
            }

            // Update active device
            self.activeDevice = allDevices.first { $0.presenceState == .active }
        } catch {
            print("[DevicePresenceService] Error loading devices: \(error)")
        }
    }

    // MARK: - Presence State Management

    /// Request activation for this device (agent enters this "room")
    func requestActivation() async throws -> ActivationResult {
        guard let current = currentDevice else {
            throw PresenceError.deviceNotRegistered
        }

        let settings = SettingsViewModel.shared.settings.presenceSettings
        let doorPolicy = settings.doorSettings.policy(for: current.id)

        // Check door policy
        switch doorPolicy {
        case .locked:
            return .locked

        case .invitation:
            // Check if there's a user invitation (e.g., they started typing)
            // For now, treat opening the app as an invitation
            return try await performActivation(reason: .userInvitation)

        case .knockFirst:
            // If another device is active, request approval
            if let active = activeDevice, active.id != current.id {
                return .pendingApproval(activeDevice: active)
            }
            return try await performActivation(reason: .userRequest)

        case .openDoor:
            return try await performActivation(reason: .autonomousMove)
        }
    }

    /// Perform the actual activation
    private func performActivation(reason: TransferReason) async throws -> ActivationResult {
        guard let current = currentDevice else {
            throw PresenceError.deviceNotRegistered
        }

        let previousActive = activeDevice
        let context = persistence.newBackgroundContext()

        try await context.perform {
            // Deactivate any currently active device
            let fetchRequest: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "presenceState == %@", PresenceState.active.rawValue)

            let activeEntities = try context.fetch(fetchRequest)
            for entity in activeEntities {
                entity.presenceState = PresenceState.standby.rawValue
                entity.updatedAt = Date()
            }

            // Activate current device
            let currentFetch: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
            currentFetch.predicate = NSPredicate(format: "deviceId == %@", current.id)

            if let currentEntity = try context.fetch(currentFetch).first {
                currentEntity.presenceState = PresenceState.active.rawValue
                currentEntity.activatedAt = Date()
                currentEntity.lastActiveAt = Date()
                currentEntity.updatedAt = Date()
            }

            try context.save()
        }

        // Reload state
        await loadCurrentDevice()
        await loadAllDevices()

        print("[DevicePresenceService] Activated device: \(current.id) (reason: \(reason.displayName))")

        return .activated(previousDevice: previousActive)
    }

    /// Relinquish activation (agent leaves this "room")
    func relinquishActivation(reason: ExitReason) async throws {
        guard let current = currentDevice, current.presenceState == .active else {
            return // Already not active
        }

        let context = persistence.newBackgroundContext()
        let deviceId = current.id

        try await context.perform {
            let fetchRequest: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deviceId == %@", deviceId)

            if let entity = try context.fetch(fetchRequest).first {
                entity.presenceState = PresenceState.standby.rawValue
                entity.updatedAt = Date()
                try context.save()
            }
        }

        await loadCurrentDevice()
        await loadAllDevices()

        print("[DevicePresenceService] Relinquished activation: \(deviceId) (reason: \(reason.displayName))")
    }

    /// Update presence state
    func updatePresenceState(_ state: PresenceState) async throws {
        guard let current = currentDevice else {
            throw PresenceError.deviceNotRegistered
        }

        let context = persistence.newBackgroundContext()
        let deviceId = current.id

        try await context.perform {
            let fetchRequest: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deviceId == %@", deviceId)

            if let entity = try context.fetch(fetchRequest).first {
                entity.presenceState = state.rawValue
                entity.updatedAt = Date()

                if state == .active {
                    entity.activatedAt = Date()
                    entity.lastActiveAt = Date()
                }

                try context.save()
            }
        }

        await loadCurrentDevice()
        await loadAllDevices()
    }

    /// Record user interaction (updates lastActiveAt)
    func recordUserInteraction() async {
        guard let current = currentDevice else { return }

        let context = persistence.newBackgroundContext()
        let deviceId = current.id

        await context.perform {
            let fetchRequest: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deviceId == %@", deviceId)

            if let entity = try? context.fetch(fetchRequest).first {
                entity.lastActiveAt = Date()
                entity.updatedAt = Date()
                try? context.save()
            }
        }
    }

    // MARK: - Door Policy Management

    /// Set door policy for a device
    func setDoorPolicy(_ policy: DoorPolicy, for deviceId: String) async throws {
        let context = persistence.newBackgroundContext()

        try await context.perform {
            let fetchRequest: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "deviceId == %@", deviceId)

            if let entity = try context.fetch(fetchRequest).first {
                entity.doorPolicy = policy.rawValue
                entity.updatedAt = Date()
                try context.save()
            }
        }

        await loadAllDevices()
    }

    // MARK: - Sync

    /// Sync presence state with other devices
    func syncPresenceState() async {
        // This is called during the regular sync cycle
        // Pull presence updates from other devices
        await loadAllDevices()

        // Check for stale active devices (no heartbeat in 5 minutes)
        await cleanupStalePresence()

        lastSyncTime = Date()
    }

    /// Clean up stale presence states
    private func cleanupStalePresence() async {
        let context = persistence.newBackgroundContext()
        let staleThreshold = Date().addingTimeInterval(-300) // 5 minutes
        let currentDeviceId = deviceIdentity.getDeviceId()

        await context.perform {
            let fetchRequest: NSFetchRequest<DevicePresenceEntity> = DevicePresenceEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "presenceState == %@ AND lastActiveAt < %@ AND deviceId != %@",
                PresenceState.active.rawValue,
                staleThreshold as NSDate,
                currentDeviceId
            )

            if let staleEntities = try? context.fetch(fetchRequest) {
                for entity in staleEntities {
                    entity.presenceState = PresenceState.dormant.rawValue
                    entity.updatedAt = Date()
                    print("[DevicePresenceService] Marked stale device as dormant: \(entity.deviceId ?? "?")")
                }
                try? context.save()
            }
        }
    }

    // MARK: - Environment Generation

    /// Generate the current device environment for prompt injection
    func generateEnvironment() -> DeviceEnvironment? {
        guard let current = currentDevice else { return nil }

        let otherDevices = allDevices.filter { !$0.isCurrentDevice }

        return DeviceEnvironment(
            deviceId: current.id,
            deviceName: current.deviceName,
            platform: current.platform,
            osVersion: current.osVersion,
            capabilities: current.capabilities,
            constraints: current.constraints,
            sessionDuration: current.activatedAt.map { Date().timeIntervalSince($0) },
            previousDeviceId: lastSnapshot?.sourceDeviceId,
            previousDeviceName: lastSnapshot?.sourceDeviceId.flatMap { id in
                allDevices.first { $0.id == id }?.deviceName
            },
            transferReason: lastSnapshot?.transferReason
        )
    }

    /// Generate presence context for agent prompts
    func generatePresencePromptContext() -> String? {
        guard let env = generateEnvironment() else { return nil }
        let otherDevices = allDevices.filter { !$0.isCurrentDevice }
        return env.generatePromptContext(otherDevices: otherDevices)
    }

    // MARK: - Capability Detection

    private func detectCapabilitiesAndConstraints() -> (Set<DeviceCapability>, Set<DeviceConstraint>) {
        var capabilities = Set<DeviceCapability>()
        var constraints = Set<DeviceConstraint>()

        #if os(iOS)
        let device = UIDevice.current

        // Capabilities
        capabilities.insert(.microphone)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            capabilities.insert(.camera)
        }

        if device.userInterfaceIdiom == .pad {
            capabilities.insert(.largeScreen)
        }

        // Check for cellular
        // Note: This is a simplified check
        capabilities.insert(.haptics)

        // Constraints
        if device.userInterfaceIdiom == .phone {
            constraints.insert(.limitedScreen)
        }
        constraints.insert(.noKeyboard)
        constraints.insert(.batteryPowered)
        constraints.insert(.backgroundLimited)

        #elseif os(macOS)
        capabilities.insert(.keyboard)
        capabilities.insert(.largeScreen)
        capabilities.insert(.continuousPower)

        // Check for camera
        // Simplified - most Macs have cameras
        capabilities.insert(.camera)
        capabilities.insert(.microphone)
        #endif

        return (capabilities, constraints)
    }

    // MARK: - Entity Mapping

    private func mapEntityToPresence(_ entity: DevicePresenceEntity) -> DevicePresence {
        let capabilities: Set<DeviceCapability>
        if let json = entity.capabilitiesJSON,
           let data = Data(base64Encoded: json),
           let decoded = try? JSONDecoder().decode(Set<DeviceCapability>.self, from: data) {
            capabilities = decoded
        } else {
            capabilities = []
        }

        let constraints: Set<DeviceConstraint>
        if let json = entity.constraintsJSON,
           let data = Data(base64Encoded: json),
           let decoded = try? JSONDecoder().decode(Set<DeviceConstraint>.self, from: data) {
            constraints = decoded
        } else {
            constraints = []
        }

        return DevicePresence(
            id: entity.deviceId ?? "",
            deviceName: entity.deviceName ?? "Unknown Device",
            platform: DevicePlatform(rawValue: entity.platform ?? "iOS") ?? .iOS,
            osVersion: entity.osVersion ?? "",
            appVersion: entity.appVersion ?? "",
            presenceState: PresenceState(rawValue: entity.presenceState ?? "dormant") ?? .dormant,
            doorPolicy: DoorPolicy(rawValue: entity.doorPolicy ?? "invitation") ?? .invitation,
            lastActiveAt: entity.lastActiveAt,
            lastHeartbeatAt: entity.lastHeartbeatAt,
            activatedAt: entity.activatedAt,
            capabilities: capabilities,
            constraints: constraints,
            exitStateId: entity.exitStateId
        )
    }

    // MARK: - Snapshot Management

    /// Set the last snapshot (called by SystemStateService during restoration)
    func setLastSnapshot(_ snapshot: SystemStateSnapshot) {
        self.lastSnapshot = snapshot
    }
}

// MARK: - Errors

enum PresenceError: LocalizedError {
    case deviceNotRegistered
    case deviceInfoUnavailable
    case activationDenied(String)
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotRegistered:
            return "Device not registered in presence system"
        case .deviceInfoUnavailable:
            return "Device information unavailable"
        case .activationDenied(let reason):
            return "Activation denied: \(reason)"
        case .transferFailed(let reason):
            return "Transfer failed: \(reason)"
        }
    }
}
