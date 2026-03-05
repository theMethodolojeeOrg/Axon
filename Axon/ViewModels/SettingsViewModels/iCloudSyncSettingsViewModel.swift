//
//  iCloudSyncSettingsViewModel.swift
//  Axon
//
//  iCloud sync settings management
//

import SwiftUI
import Combine

/// View model for iCloud sync settings and operations
@MainActor
class iCloudSyncSettingsViewModel: ObservableObject {
    @Published var iCloudSyncEnabled = false
    
    private weak var core: SettingsViewModelCoreProtocol?
    private let iCloudSync = iCloudKeyValueSync.shared
    private var cancellables = Set<AnyCancellable>()
    
    init(core: SettingsViewModelCoreProtocol) {
        self.core = core
        setupiCloudSync()
    }
    
    // MARK: - Setup
    
    private func setupiCloudSync() {
        guard let core = core else { return }
        
        // Listen for settings changes from other devices
        iCloudSync.settingsChangedFromCloud
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak core] cloudSettings in
                guard let self = self, let core = core else { return }
                
                // Update local settings with cloud values
                core.settings = cloudSettings
                try? core.storageService.saveSettings(cloudSettings)
                
                // Show notification to user
                core.showSuccessMessage("Settings synced from another device")
            }
            .store(in: &cancellables)
        
        // Track availability changes
        iCloudSync.$isAvailable
            .receive(on: DispatchQueue.main)
            .assign(to: &$iCloudSyncEnabled)
    }
    
    // MARK: - Actions
    
    /// Force sync settings to/from iCloud
    func forceiCloudSync() {
        iCloudSync.forceSync()
    }
    
    /// Check if iCloud is available
    var isAvailable: Bool {
        iCloudSync.isAvailable
    }
}
