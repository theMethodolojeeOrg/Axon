//
//  LocalServerSettingsViewModel.swift
//  Axon
//
//  Local API server settings management
//

import SwiftUI
import Combine

/// View model for local API server settings
@MainActor
class LocalServerSettingsViewModel: ObservableObject {
    @Published var isServerRunning = false
    @Published var serverError: String?
    @Published var serverLocalURL: String = ""
    @Published var serverNetworkURL: String = ""
    
    private weak var core: SettingsViewModelCoreProtocol?
    private let apiServer = APIServer.shared
    
    init(core: SettingsViewModelCoreProtocol) {
        self.core = core
    }
    
    // MARK: - Server Control
    
    func startServer() async {
        guard let core = core else { return }
        
        await apiServer.start(
            port: UInt16(core.settings.serverPort),
            password: core.settings.serverPassword,
            allowExternal: core.settings.serverAllowExternal
        )
        
        // Sync server state
        syncServerState()
        
        if isServerRunning {
            core.showSuccessMessage("Server started successfully")
        }
    }
    
    func stopServer() async {
        guard let core = core else { return }
        
        await apiServer.stop()
        
        // Sync server state
        syncServerState()
        
        core.showSuccessMessage("Server stopped")
    }
    
    private func syncServerState() {
        isServerRunning = apiServer.isRunning
        serverError = apiServer.error
        serverLocalURL = apiServer.localURL
        serverNetworkURL = apiServer.networkURL
    }
    
    // MARK: - Server Configuration
    
    func updateServerPort(_ port: Int) async {
        guard let core = core else { return }
        
        await core.updateSetting(\.serverPort, port)
        
        // Restart server if running
        if isServerRunning {
            await stopServer()
            await startServer()
        }
    }
    
    func updateServerPassword(_ password: String?) async {
        guard let core = core else { return }
        
        await core.updateSetting(\.serverPassword, password)
        
        // Restart server if running
        if isServerRunning {
            await stopServer()
            await startServer()
        }
    }
    
    func updateServerAllowExternal(_ allow: Bool) async {
        guard let core = core else { return }
        
        await core.updateSetting(\.serverAllowExternal, allow)
        
        // Restart server if running
        if isServerRunning {
            await stopServer()
            await startServer()
        }
    }
    
    func generateServerPassword() async {
        let password = generateRandomPassword()
        await updateServerPassword(password)
        core?.showSuccessMessage("Password generated: \(password)")
    }
    
    private func generateRandomPassword(length: Int = 24) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}
