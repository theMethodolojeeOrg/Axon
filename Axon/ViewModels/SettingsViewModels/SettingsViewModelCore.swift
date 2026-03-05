//
//  SettingsViewModelCore.swift
//  Axon
//
//  Core settings view model with shared state and dependencies
//

import SwiftUI
import Combine

/// Protocol defining core settings functionality that all sub-modules can access
@MainActor
protocol SettingsViewModelCoreProtocol: AnyObject {
    var settings: AppSettings { get set }
    var isLoading: Bool { get set }
    var error: String? { get set }
    var successMessage: String? { get set }
    
    var storageService: SettingsStorage { get }
    var apiKeysStorage: APIKeysStorage { get }
    
    func updateSetting<T: Encodable & Equatable>(
        _ keyPath: WritableKeyPath<AppSettings, T>,
        _ newValue: T
    ) async
    
    func showSuccessMessage(_ message: String)
    func syncToiCloudIfEnabled()
}

/// Core settings view model containing shared state and base functionality
@MainActor
class SettingsViewModelCore: ObservableObject, SettingsViewModelCoreProtocol {
    @Published var settings: AppSettings = AppSettings()
    @Published var isLoading = false
    @Published var error: String?
    @Published var successMessage: String?
    
    let storageService = SettingsStorage.shared
    let apiKeysStorage = APIKeysStorage.shared
    let iCloudSync = iCloudKeyValueSync.shared
    
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Update Settings
    
    func updateSetting<T: Encodable & Equatable>(
        _ keyPath: WritableKeyPath<AppSettings, T>,
        _ newValue: T
    ) async {
        guard settings[keyPath: keyPath] != newValue else { return }
        
        settings[keyPath: keyPath] = newValue
        settings.lastUpdated = Date()
        
        // Persist to UserDefaults
        do {
            try storageService.saveSettings(settings)
            
            // Sync to iCloud if enabled
            syncToiCloudIfEnabled()
            
            // Unified sync (debounced + scheduled) based on DeviceModeConfig
            SettingsSyncCoordinator.shared.markDirty()
        } catch {
            self.error = "Failed to save settings: \(error.localizedDescription)"
        }
    }
    
    // MARK: - iCloud Sync Helper
    
    func syncToiCloudIfEnabled() {
        // Only sync if user has iCloud sync enabled in device mode config
        guard settings.deviceModeConfig.cloudSyncProvider == .iCloud ||
              settings.deviceMode == .cloud else {
            return
        }
        
        iCloudSync.saveSettingsToCloud(settings)
    }
    
    // MARK: - Messages
    
    func showSuccessMessage(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.successMessage = nil
        }
    }
}
