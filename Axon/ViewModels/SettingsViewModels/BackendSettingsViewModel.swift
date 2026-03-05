//
//  BackendSettingsViewModel.swift
//  Axon
//
//  Backend API settings management
//

import SwiftUI
import Combine

/// View model for backend API settings
@MainActor
class BackendSettingsViewModel: ObservableObject {
    private weak var core: SettingsViewModelCoreProtocol?
    
    init(core: SettingsViewModelCoreProtocol) {
        self.core = core
    }
    
    // MARK: - Backend Settings
    
    func updateBackendURL(_ url: String?) async {
        guard let core = core else { return }
        
        await core.updateSetting(\.backendAPIURL, url)
        if url != nil {
            core.showSuccessMessage("Backend URL saved")
        } else {
            core.showSuccessMessage("Backend URL cleared - running in local-only mode")
        }
    }
    
    func updateBackendAuthToken(_ token: String?) async {
        guard let core = core else { return }
        
        await core.updateSetting(\.backendAuthToken, token)
        core.showSuccessMessage("Auth token updated")
    }
}
