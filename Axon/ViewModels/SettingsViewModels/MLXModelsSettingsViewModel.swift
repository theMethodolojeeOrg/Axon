//
//  MLXModelsSettingsViewModel.swift
//  Axon
//
//  Local MLX model management
//

import SwiftUI
import Combine

/// View model for managing user-downloaded MLX models
@MainActor
class MLXModelsSettingsViewModel: ObservableObject {
    private weak var core: SettingsViewModelCoreProtocol?
    
    init(core: SettingsViewModelCoreProtocol) {
        self.core = core
    }
    
    // MARK: - User MLX Models
    
    /// Add a user-downloaded MLX model to settings
    func addUserMLXModel(_ model: UserMLXModel) async {
        guard let core = core else { return }
        
        // Check if already exists
        guard !core.settings.userMLXModels.contains(where: { $0.repoId == model.repoId }) else {
            // Update existing
            if let index = core.settings.userMLXModels.firstIndex(where: { $0.repoId == model.repoId }) {
                core.settings.userMLXModels[index] = model
            }
            do {
                try core.storageService.saveSettings(core.settings)
                core.syncToiCloudIfEnabled()
                SettingsSyncCoordinator.shared.markDirty()
            } catch {
                core.error = "Failed to update model: \(error.localizedDescription)"
            }
            return
        }
        
        core.settings.userMLXModels.append(model)
        core.settings.lastUpdated = Date()
        
        do {
            try core.storageService.saveSettings(core.settings)
            core.syncToiCloudIfEnabled()
            SettingsSyncCoordinator.shared.markDirty()
            core.showSuccessMessage("Model \(model.displayName) added")
        } catch {
            core.error = "Failed to save model: \(error.localizedDescription)"
        }
    }
    
    /// Remove a user-downloaded MLX model from settings
    func removeUserMLXModel(repoId: String) async {
        guard let core = core else { return }
        
        core.settings.userMLXModels.removeAll { $0.repoId == repoId }
        
        // If this was the selected model, clear selection
        if core.settings.selectedMLXModelId == repoId {
            core.settings.selectedMLXModelId = nil
        }
        
        core.settings.lastUpdated = Date()
        
        do {
            try core.storageService.saveSettings(core.settings)
            core.syncToiCloudIfEnabled()
            SettingsSyncCoordinator.shared.markDirty()
            core.showSuccessMessage("Model removed")
        } catch {
            core.error = "Failed to remove model: \(error.localizedDescription)"
        }
    }
    
    /// Update download status for a user MLX model
    func updateUserMLXModelStatus(repoId: String, status: UserMLXModel.DownloadStatus, sizeBytes: Int64? = nil) async {
        guard let core = core else { return }
        guard let index = core.settings.userMLXModels.firstIndex(where: { $0.repoId == repoId }) else { return }
        
        core.settings.userMLXModels[index].downloadStatus = status
        if let size = sizeBytes {
            core.settings.userMLXModels[index].sizeBytes = size
        }
        
        do {
            try core.storageService.saveSettings(core.settings)
        } catch {
            core.error = "Failed to update model status: \(error.localizedDescription)"
        }
    }
    
    /// Select an MLX model for use
    func selectMLXModel(repoId: String) async {
        guard let core = core else { return }
        
        await core.updateSetting(\.selectedMLXModelId, repoId)
        core.showSuccessMessage("Model selected")
    }
    
    /// Get all available MLX models (built-in + user-added)
    func allMLXModels() -> [AIModel] {
        guard let core = core else { return AIProvider.localMLX.availableModels }
        
        // Built-in models
        var models = AIProvider.localMLX.availableModels
        
        // Add user models that are downloaded
        for userModel in core.settings.userMLXModels where userModel.downloadStatus == .downloaded {
            // Don't duplicate if already in built-in list
            if !models.contains(where: { $0.id == userModel.repoId }) {
                models.append(userModel.toAIModel())
            }
        }
        
        return models
    }
    
    /// Get the currently selected MLX model ID (defaults to bundled model)
    func selectedMLXModelId() -> String {
        core?.settings.selectedMLXModelId ?? LocalMLXModel.defaultModel.rawValue
    }
}
