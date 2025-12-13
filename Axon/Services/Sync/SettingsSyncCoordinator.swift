//
//  SettingsSyncCoordinator.swift
//  Axon
//
//  Unifies scheduled + debounced settings sync across providers (iCloud KV / backend)
//

import Foundation
import Combine

@MainActor
final class SettingsSyncCoordinator: ObservableObject {
    static let shared = SettingsSyncCoordinator()

    private let settingsStorage = SettingsStorage.shared
    private let backendConfig = BackendConfig.shared
    private let iCloudKV = iCloudKeyValueSync.shared

    private var cancellables = Set<AnyCancellable>()

    // Debounce/timer state
    private var debounceTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    // Public status
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncError: String?

    private init() {}

    /// Call once at app start.
    func start() {
        // Avoid multiple timer loops
        if timerTask != nil { return }

        // Timer loop (interval can change at runtime based on settings)
        timerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let interval = max(15, self.currentIntervalSeconds())
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                await self.syncIfNeeded(reason: .scheduled)
            }
        }
    }

    /// Call when settings are changed/saved locally.
    func markDirty() {
        // Debounced sync after last change
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s debounce
            await self.syncIfNeeded(reason: .debounced)
        }
    }

    enum SyncReason {
        case debounced
        case scheduled
        case appForeground
    }

    private func currentIntervalSeconds() -> Int {
        settingsStorage.loadSettings()?.deviceModeConfig.settingsSyncIntervalSeconds ?? 60
    }

    private func currentProvider() -> CloudSyncProvider {
        settingsStorage.loadSettings()?.deviceModeConfig.cloudSyncProvider ?? .none
    }

    private func syncIfNeeded(reason: SyncReason) async {
        let provider = currentProvider()

        switch provider {
        case .none:
            return

        case .iCloud:
            guard let settings = settingsStorage.loadSettings() else { return }
            iCloudKV.saveSettingsToCloud(settings)
            lastSyncDate = Date()
            lastSyncError = iCloudKV.syncError

        case .firestore:
            // If there is no backend, this should be impossible to select via UI.
            // Still guard defensively.
            guard backendConfig.isBackendConfigured else {
                lastSyncError = "Backend not configured"
                return
            }
            guard let settings = settingsStorage.loadSettings() else { return }

            do {
                // Push a syncable subset (mirrors iCloud behavior / avoids destructive overwrite)
                try await SettingsCloudSyncService.shared.pushSettings(settings)
                lastSyncDate = Date()
                lastSyncError = nil
            } catch {
                lastSyncError = error.localizedDescription
            }
        }
    }
}
