//
//  BridgeConnectionManager.swift
//  Axon
//
//  Unified interface for Bridge connections that works in both Local and Remote modes.
//  Delegates to either BridgeServer (Local Mode) or BridgeClient (Remote Mode) based on settings.
//
//  This allows the rest of the app to use a single API regardless of connection direction.
//

import Foundation
import Combine

@MainActor
class BridgeConnectionManager: ObservableObject {
    static let shared = BridgeConnectionManager()

    // MARK: - Published State

    /// Current connection mode
    @Published private(set) var mode: BridgeMode = .local

    /// Whether any connection is active
    @Published private(set) var isConnected = false

    /// Whether we're currently trying to connect
    @Published private(set) var isConnecting = false

    /// Whether the bridge is running (server listening or client connecting)
    @Published private(set) var isRunning = false

    /// All active sessions (may be multiple in Local Mode with multi-session)
    @Published private(set) var sessions: [String: BridgeSession] = [:]

    /// Most recent error message
    @Published private(set) var lastError: String?

    // MARK: - Computed Properties

    /// The first/primary connected session (for simple single-session access)
    var connectedSession: BridgeSession? {
        sessions.values.first
    }

    /// Number of active sessions
    var sessionCount: Int {
        sessions.count
    }

    /// All sessions as a sorted array
    var allSessions: [BridgeSession] {
        sessions.values.sorted { $0.connectedAt < $1.connectedAt }
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var pendingRemoteProfileId: UUID?
    private var lastAutoConnectAttemptAt: Date?

    // MARK: - Initialization

    private init() {
        // Observe BridgeServer state
        BridgeServer.shared.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self = self, self.mode == .local else { return }
                self.isRunning = running
            }
            .store(in: &cancellables)

        BridgeServer.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                guard let self = self, self.mode == .local else { return }
                self.sessions = sessions
                self.isConnected = !sessions.isEmpty
            }
            .store(in: &cancellables)

        BridgeServer.shared.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self = self, self.mode == .local else { return }
                self.lastError = error
            }
            .store(in: &cancellables)

        // Load initial mode from settings
        mode = BridgeSettingsStorage.shared.settings.mode
    }

    // MARK: - Connection Control

    /// Start the bridge based on current mode settings
    func start() async {
        let settings = BridgeSettingsStorage.shared.settings
        mode = settings.mode

        switch mode {
        case .local:
            await startLocalMode(port: settings.port)
        case .remote:
            await startRemoteMode()
        }
    }

    /// Stop the bridge
    func stop() async {
        switch mode {
        case .local:
            await BridgeServer.shared.stop()
        case .remote:
            bridgeClient?.disconnect()
        }

        isRunning = false
        isConnected = false
        isConnecting = false
        sessions.removeAll()
    }

    /// Switch connection mode (stops current connection if any)
    func setMode(_ newMode: BridgeMode) async {
        guard newMode != mode else { return }

        // Stop current connection
        await stop()

        // Update mode
        mode = newMode
        BridgeSettingsStorage.shared.setMode(newMode)
    }

    // MARK: - Profile-Driven Connection Control

    func connectToProfile(profileId: UUID) async {
        let storage = BridgeSettingsStorage.shared

        guard storage.connectionProfile(id: profileId) != nil else {
            lastError = "Connection profile not found."
            return
        }

        pendingRemoteProfileId = profileId
        _ = storage.applyConnectionProfileToActiveRemoteConfig(profileId: profileId)
        storage.setMode(.remote)
        storage.setEnabled(true)

        if mode != .remote {
            await setMode(.remote)
        } else if isRunning || isConnecting || isConnected {
            await stop()
        }

        await start()
    }

    func connectToDefaultProfile() async {
        let storage = BridgeSettingsStorage.shared
        guard let defaultProfile = storage.resolveDefaultConnectionProfile() else {
            lastError = "No default bridge profile selected."
            return
        }

        await connectToProfile(profileId: defaultProfile.id)
    }

    func disconnectAndDisableBridge() async {
        BridgeSettingsStorage.shared.setEnabled(false)
        await stop()
    }

    func handleAppDidBecomeActive() async {
        let settings = BridgeSettingsStorage.shared.settings

        guard settings.autoConnectDefaultOnActive else { return }
        guard settings.defaultConnectionProfileId != nil else { return }
        guard !isConnected && !isConnecting else { return }

        let now = Date()
        if let lastAttempt = lastAutoConnectAttemptAt, now.timeIntervalSince(lastAttempt) < 3 {
            return
        }
        lastAutoConnectAttemptAt = now

        await connectToDefaultProfile()
    }

    // MARK: - Host Mode (Axon as Server)

    /// Explicitly start host mode (Axon runs the WebSocket server).
    /// Switches to local mode if not already, then starts the server.
    func startHostMode() async {
        if mode != .local {
            await setMode(.local)
        }
        let settings = BridgeSettingsStorage.shared.settings
        BridgeSettingsStorage.shared.setEnabled(true)
        await startLocalMode(port: settings.port)
    }

    /// Explicitly stop host mode.
    func stopHostMode() async {
        guard mode == .local else { return }
        await BridgeServer.shared.stop()
        isRunning = false
        isConnected = false
        sessions.removeAll()
    }

    private func startLocalMode(port: UInt16) async {
        print("[BridgeConnectionManager] Starting Local Mode on port \(port)")
        await BridgeServer.shared.start(port: port)
        isRunning = BridgeServer.shared.isRunning
    }

    // MARK: - Remote Mode (Axon as Client)

    /// Lazily created client for Remote Mode
    private var bridgeClient: BridgeClient?

    private func startRemoteMode() async {
        let settings = BridgeSettingsStorage.shared.settings

        guard settings.isRemoteModeConfigured else {
            lastError = "Remote Mode not configured. Please set VS Code host and port."
            print("[BridgeConnectionManager] Remote Mode not configured")
            return
        }

        print("[BridgeConnectionManager] Starting Remote Mode, connecting to \(settings.remoteURL)")

        if bridgeClient == nil {
            bridgeClient = BridgeClient()
            observeBridgeClient()
        }

        isConnecting = true
        isRunning = true

        await bridgeClient?.connect(
            host: settings.remoteHost,
            port: settings.remotePort,
            useTLS: settings.tlsEnabled
        )
    }

    private func observeBridgeClient() {
        guard let client = bridgeClient else { return }

        client.$isConnecting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connecting in
                guard let self = self, self.mode == .remote else { return }
                self.isConnecting = connecting
                self.isRunning = connecting || self.isConnected
            }
            .store(in: &cancellables)

        client.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self = self, self.mode == .remote else { return }
                self.isConnected = connected
                self.isRunning = connected || self.isConnecting
            }
            .store(in: &cancellables)

        client.$connectedSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self = self, self.mode == .remote else { return }
                if let session = session {
                    self.sessions = [session.id.uuidString: session]

                    let storage = BridgeSettingsStorage.shared
                    let profileId = self.pendingRemoteProfileId ?? storage.profileIdMatchingActiveRemoteConfig()
                    if let profileId {
                        storage.markConnectedProfile(profileId)
                    }
                    self.pendingRemoteProfileId = nil
                } else {
                    self.sessions.removeAll()
                }
            }
            .store(in: &cancellables)

        client.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self = self, self.mode == .remote else { return }
                self.lastError = error
            }
            .store(in: &cancellables)
    }

    // MARK: - Message Sending (Unified API)

    /// Send a request and wait for response
    /// In Local Mode: sends to specified session or first available
    /// In Remote Mode: sends to the connected VS Code
    func sendRequest(method: String, params: AnyCodable? = nil, sessionId: String? = nil, timeout: TimeInterval? = nil) async throws -> BridgeResponse {
        switch mode {
        case .local:
            return try await BridgeServer.shared.sendRequest(method: method, params: params, sessionId: sessionId, timeout: timeout)
        case .remote:
            guard let client = bridgeClient else {
                throw BridgeError(code: .notConnected, message: "Not connected")
            }
            return try await client.sendRequest(method: method, params: params, timeout: timeout)
        }
    }

    /// Send a notification (no response expected)
    func sendNotification(method: String, params: AnyCodable? = nil, sessionId: String? = nil) {
        switch mode {
        case .local:
            BridgeServer.shared.sendNotification(method: method, params: params, sessionId: sessionId)
        case .remote:
            bridgeClient?.sendNotification(method: method, params: params)
        }
    }

    /// Execute a bridge method
    func executeMethod(method: BridgeMethod, params: AnyCodable, sessionId: String? = nil) async throws -> AnyCodable {
        let response = try await sendRequest(method: method.rawValue, params: params, sessionId: sessionId)

        if let error = response.error {
            throw error
        }

        return response.result ?? .null
    }

    // MARK: - Convenience Methods (File Operations, etc.)

    /// Read a file from VS Code workspace
    func readFile(path: String, sessionId: String? = nil) async throws -> FileReadResult {
        switch mode {
        case .local:
            // For local mode, use BridgeServer directly (it handles session routing)
            return try await BridgeServer.shared.readFile(path: path)
        case .remote:
            guard let client = bridgeClient else {
                throw BridgeError(code: .notConnected, message: "Not connected")
            }
            return try await client.readFile(path: path)
        }
    }

    /// Write a file to VS Code workspace
    func writeFile(path: String, content: String, sessionId: String? = nil) async throws -> FileWriteResult {
        switch mode {
        case .local:
            return try await BridgeServer.shared.writeFile(path: path, content: content)
        case .remote:
            guard let client = bridgeClient else {
                throw BridgeError(code: .notConnected, message: "Not connected")
            }
            return try await client.writeFile(path: path, content: content)
        }
    }

    /// List files in VS Code workspace directory
    func listFiles(path: String, recursive: Bool = false, sessionId: String? = nil) async throws -> FileListResult {
        switch mode {
        case .local:
            return try await BridgeServer.shared.listFiles(path: path, recursive: recursive)
        case .remote:
            guard let client = bridgeClient else {
                throw BridgeError(code: .notConnected, message: "Not connected")
            }
            return try await client.listFiles(path: path, recursive: recursive)
        }
    }

    /// Run a terminal command in VS Code
    func runTerminal(command: String, cwd: String? = nil, sessionId: String? = nil) async throws -> TerminalRunResult {
        switch mode {
        case .local:
            return try await BridgeServer.shared.runTerminal(command: command, cwd: cwd)
        case .remote:
            guard let client = bridgeClient else {
                throw BridgeError(code: .notConnected, message: "Not connected")
            }
            return try await client.runTerminal(command: command, cwd: cwd)
        }
    }

    /// Get workspace info from VS Code
    func getWorkspaceInfo(sessionId: String? = nil) async throws -> WorkspaceInfoResult {
        switch mode {
        case .local:
            return try await BridgeServer.shared.getWorkspaceInfo()
        case .remote:
            guard let client = bridgeClient else {
                throw BridgeError(code: .notConnected, message: "Not connected")
            }
            return try await client.getWorkspaceInfo()
        }
    }

    // MARK: - Session Management

    /// Get a specific session by ID
    func session(for sessionId: String) -> BridgeSession? {
        sessions[sessionId]
    }

    /// Disconnect a specific session (Local Mode only)
    func disconnectSession(_ sessionId: String) {
        guard mode == .local else { return }
        BridgeServer.shared.disconnectSession(sessionId)
    }
}
