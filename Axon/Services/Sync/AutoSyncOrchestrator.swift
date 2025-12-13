//
//  AutoSyncOrchestrator.swift
//  Axon
//
//  Central coordinator for cross-device sync.
//
//  Goals:
//  - Make “switching devices just works” for iCloud users.
//  - Run a pull/merge on app launch + when returning to foreground.
//  - Optionally run periodic pulls while active.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class AutoSyncOrchestrator: ObservableObject {
    static let shared = AutoSyncOrchestrator()

    private let settingsVM = SettingsViewModel.shared
    private let settingsCoordinator = SettingsSyncCoordinator.shared
    private let iCloudKV = iCloudKeyValueSync.shared
    private let cloudKit = CloudKitSyncService.shared

    private var periodicTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // Status
    @Published private(set) var lastPullAt: Date?
    @Published private(set) var lastPullError: String?

    private init() {}

    func start() {
        // Start scheduled settings sync loop (push) if a provider is selected.
        settingsCoordinator.start()

        // React to settings changes (e.g. switching providers, intervals).
        settingsVM.$settings
            .map { $0.deviceModeConfig }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.restartPeriodicIfNeeded()
            }
            .store(in: &cancellables)

        restartPeriodicIfNeeded()
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task { await pullOnActive() }
        case .inactive:
            break
        case .background:
            break
        @unknown default:
            break
        }
    }

    /// Manual “pull now” entrypoint (e.g. pull-to-refresh).
    func pullNow() async {
        await performPull(reason: "manual")
    }

    // MARK: - Internals

    private func pullOnActive() async {
        // If the app just launched, this still runs once it becomes active.
        await performPull(reason: "appActive")
    }

    private func restartPeriodicIfNeeded() {
        periodicTask?.cancel()
        periodicTask = nil

        let config = settingsVM.settings.deviceModeConfig
        guard config.cloudSyncProvider == .iCloud else {
            return
        }
        guard config.autoSyncOnConnect else {
            return
        }

        // Keep this conservative; we can expose to UI later if desired.
        let intervalSeconds = max(120, min(600, config.settingsSyncIntervalSeconds))

        periodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
                await self.performPull(reason: "periodic")
            }
        }
    }

    private func performPull(reason: String) async {
        let provider = settingsVM.settings.deviceModeConfig.cloudSyncProvider
        guard provider == .iCloud else {
            return
        }

        // 1) Pull settings from iCloud KV (best-effort).
        iCloudKV.forceSync()

        // 2) CloudKit availability refresh (async)
        await cloudKit.checkCloudKitAvailability()
        guard cloudKit.isCloudKitAvailable else {
            lastPullError = cloudKit.syncError
            return
        }

        // 3) Full sync (bidirectional merge)
        // If the Core Data store is already CloudKit-backed, Core Data will sync automatically.
        // The legacy CKRecord-based CloudKitSyncService is not needed and can error if record
        // types aren’t provisioned in the CloudKit dashboard.
        guard !PersistenceController.shared.isCloudKitEnabled else {
            lastPullAt = Date()
            lastPullError = nil
            print("[AutoSyncOrchestrator] ✅ Pull skipped (\(reason)) - CoreData CloudKit store is enabled")
            return
        }

        do {
            try await cloudKit.performFullSync()
            lastPullAt = Date()
            lastPullError = nil
            print("[AutoSyncOrchestrator] ✅ Pull succeeded (\(reason))")
        } catch {
            lastPullAt = Date()
            lastPullError = error.localizedDescription
            print("[AutoSyncOrchestrator] ❌ Pull failed (\(reason)): \(error)")
        }
    }
}
