//
//  DeviceMode.swift
//  Axon
//
//  Device mode and data management configuration
//

import Foundation

// MARK: - Device Mode

/// Primary toggle: Cloud vs On-Device
enum DeviceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case cloud = "cloud"
    case onDevice = "onDevice"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cloud: return "Cloud"
        case .onDevice: return "On-Device"
        }
    }

    var icon: String {
        switch self {
        case .cloud: return "cloud.fill"
        case .onDevice: return "iphone.gen3"
        }
    }

    var description: String {
        switch self {
        case .cloud:
            return "Conversations sync to your server. Full cloud features enabled."
        case .onDevice:
            return "Local-first operation. Configure what syncs in settings."
        }
    }
}

// MARK: - Device Mode Config

/// Unified data management configuration
/// This is the single source of truth for all data storage, sync, and AI processing settings.
/// The legacy DeviceMode toggle and useOnDeviceOrchestration flag are deprecated.
struct DeviceModeConfig: Codable, Equatable, Sendable {
    /// How conversation data is stored
    /// Default: localFirst - works offline, syncs when connected
    var dataStorage: DataStorageMode = .localFirst

    /// Where AI orchestration (prompt routing, tool calls) runs
    /// Default: onDevice - direct API calls to providers (no backend needed)
    var aiProcessing: AIProcessingMode = .onDevice

    /// How memory/learning data is handled
    /// Default: cloudSync - memories sync across devices for seamless experience
    var memoryStorage: MemoryStorageMode = .cloudSync

    /// Cloud sync provider (when sync is enabled)
    /// Default: iCloud for seamless cross-device sync on Apple platforms
    var cloudSyncProvider: CloudSyncProvider = .iCloud

    /// Settings sync interval (seconds). Used for scheduled sync when a provider is selected.
    /// Default: 60s
    var settingsSyncIntervalSeconds: Int = 60

    /// Whether to show sync status indicators in UI
    var showSyncStatus: Bool = true

    /// Auto-sync when network becomes available
    var autoSyncOnConnect: Bool = true
}

// MARK: - Cloud Sync Provider

/// Which cloud service to use for syncing (if any)
enum CloudSyncProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case iCloud = "iCloud"
    case firestore = "firestore"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .iCloud: return "iCloud"
        case .firestore: return "Custom Server"
        }
    }

    var description: String {
        switch self {
        case .none:
            return "Data stays on this device only."
        case .iCloud:
            return "Sync across your Apple devices via iCloud."
        case .firestore:
            return "Sync to your own server (Firestore/custom API)."
        }
    }

    var icon: String {
        switch self {
        case .none: return "iphone"
        case .iCloud: return "icloud.fill"
        case .firestore: return "server.rack"
        }
    }

    var requiresSetup: Bool {
        switch self {
        case .none, .iCloud: return false
        case .firestore: return true
        }
    }
}

// MARK: - Data Storage Mode

/// How conversation data is stored
enum DataStorageMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case localOnly = "localOnly"
    case localFirst = "localFirst"
    case syncRequired = "syncRequired"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localOnly: return "Local Only"
        case .localFirst: return "Local-First"
        case .syncRequired: return "Sync Required"
        }
    }

    var description: String {
        switch self {
        case .localOnly:
            return "Data never leaves device. No cloud backup."
        case .localFirst:
            return "Works offline, syncs when connected."
        case .syncRequired:
            return "Requires network. Traditional cloud mode."
        }
    }

    var icon: String {
        switch self {
        case .localOnly: return "lock.iphone"
        case .localFirst: return "arrow.triangle.2.circlepath"
        case .syncRequired: return "wifi"
        }
    }
}

// MARK: - AI Processing Mode

/// Where AI orchestration runs
enum AIProcessingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case onDevice = "onDevice"
    case cloud = "cloud"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice: return "On-Device"
        case .cloud: return "Cloud"
        }
    }

    var description: String {
        switch self {
        case .onDevice:
            return "AI calls made directly from device to providers."
        case .cloud:
            return "AI orchestration handled by your server."
        }
    }

    var icon: String {
        switch self {
        case .onDevice: return "cpu"
        case .cloud: return "cloud"
        }
    }
}

// MARK: - Memory Storage Mode

/// How memory/learning data is handled
enum MemoryStorageMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case localOnly = "localOnly"
    case cloudSync = "cloudSync"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localOnly: return "Local Memory"
        case .cloudSync: return "Cloud Sync"
        }
    }

    var description: String {
        switch self {
        case .localOnly:
            return "Memories stored only on this device."
        case .cloudSync:
            return "Memories sync across your devices."
        }
    }

    var icon: String {
        switch self {
        case .localOnly: return "brain.head.profile"
        case .cloudSync: return "brain"
        }
    }
}
