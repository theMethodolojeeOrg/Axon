//
//  BridgeClient.swift
//  Axon
//
//  WebSocket client using Network.framework for Remote Mode.
//  In Remote Mode, VS Code acts as the server and Axon connects to it.
//  This enables using Axon from a phone to control VS Code on a desktop over LAN.
//

import Foundation
import Network
import Combine

@MainActor
class BridgeClient: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedSession: BridgeSession?
    @Published private(set) var lastError: String?

    // MARK: - Private Properties

    private var connection: NWConnection?
    private var pendingRequests: [String: PendingBridgeRequest] = [:]
    private var messageBuffer = Data()

    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0

    private let queue = DispatchQueue(label: "com.axon.bridge.client", qos: .userInitiated)

    // MARK: - Configuration

    private let defaultTimeout: TimeInterval = 30.0
    private let maxMessageSize = 10 * 1024 * 1024  // 10MB
    private let baseReconnectInterval: TimeInterval = 5.0
    private let maxReconnectInterval: TimeInterval = 60.0
    private let maxReconnectAttempts = 6

    // MARK: - Initialization

    init() {}

    // MARK: - Connection Control

    /// Connect to a VS Code server at the specified host and port
    func connect(host: String, port: UInt16, useTLS: Bool = false) async {
        guard !isConnecting && !isConnected else {
            print("[BridgeClient] Already connecting or connected")
            return
        }

        isConnecting = true
        lastError = nil

        print("[BridgeClient] Connecting to \(useTLS ? "wss" : "ws")://\(host):\(port)...")

        do {
            // Configure WebSocket parameters
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true

            let parameters: NWParameters
            if useTLS {
                parameters = NWParameters.tls
                // Configure TLS options if needed
                if let tlsOptions = parameters.defaultProtocolStack.applicationProtocols.first as? NWProtocolTLS.Options {
                    configureTLS(tlsOptions)
                }
            } else {
                parameters = NWParameters.tcp
            }

            parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

            // Create endpoint
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!
            )

            connection = NWConnection(to: endpoint, using: parameters)

            connection?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleConnectionState(state)
                }
            }

            connection?.start(queue: queue)

        } catch {
            isConnecting = false
            lastError = "Failed to create connection: \(error.localizedDescription)"
            print("[BridgeClient] Failed to create connection: \(error)")
        }
    }

    /// Connect using settings from BridgeSettingsStorage
    func connectUsingSettings() async {
        let settings = BridgeSettingsStorage.shared.settings
        guard settings.isRemoteModeConfigured else {
            lastError = "Remote Mode not configured. Please set host and port."
            return
        }

        await connect(
            host: settings.remoteHost,
            port: settings.remotePort,
            useTLS: settings.tlsEnabled
        )
    }

    /// Disconnect from the server
    func disconnect() {
        cancelReconnect()
        reconnectAttempts = 0

        connection?.cancel()
        cleanupConnection()

        print("[BridgeClient] Disconnected")
    }

    // MARK: - Message Sending

    /// Send a request to VS Code and wait for response
    func sendRequest(method: String, params: AnyCodable? = nil, timeout: TimeInterval? = nil) async throws -> BridgeResponse {
        guard isConnected, let connection = connection else {
            throw BridgeError(code: .notConnected, message: "Not connected to VS Code")
        }

        let request = BridgeRequest(method: method, params: params)
        let effectiveTimeout = timeout ?? defaultTimeout

        return try await withCheckedThrowingContinuation { continuation in
            // Track pending request
            let pending = PendingBridgeRequest(
                id: request.id,
                method: method,
                sentAt: Date(),
                continuation: continuation,
                timeout: effectiveTimeout
            )
            pendingRequests[request.id] = pending

            // Set up timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                await MainActor.run {
                    if let pending = self.pendingRequests.removeValue(forKey: request.id) {
                        pending.continuation.resume(throwing: BridgeError(code: .timeout, message: "Request timed out"))
                    }
                }
            }

            // Send request
            do {
                let data = try BridgeMessage.encode(request)
                self.sendWebSocketMessage(data, on: connection)
            } catch {
                pendingRequests.removeValue(forKey: request.id)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Send a notification (no response expected)
    func sendNotification(method: String, params: AnyCodable? = nil) {
        guard isConnected, let connection = connection else {
            print("[BridgeClient] Cannot send notification: not connected")
            return
        }

        let notification = BridgeNotification(method: method, params: params)

        do {
            let data = try BridgeMessage.encode(notification)
            sendWebSocketMessage(data, on: connection)
        } catch {
            print("[BridgeClient] Failed to encode notification: \(error)")
        }
    }

    // MARK: - Tool Execution (mirrors BridgeServer API)

    /// Execute a bridge method on VS Code
    func executeMethod(method: BridgeMethod, params: AnyCodable) async throws -> AnyCodable {
        let response = try await sendRequest(method: method.rawValue, params: params)

        if let error = response.error {
            throw error
        }

        return response.result ?? .null
    }

    /// Read a file from VS Code workspace
    func readFile(path: String) async throws -> FileReadResult {
        let params = FileReadParams(path: path)
        let paramsData = try JSONEncoder().encode(params)
        let paramsAny = try JSONDecoder().decode(AnyCodable.self, from: paramsData)

        let result = try await executeMethod(method: .fileRead, params: paramsAny)

        let resultData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(FileReadResult.self, from: resultData)
    }

    /// Write a file to VS Code workspace
    func writeFile(path: String, content: String) async throws -> FileWriteResult {
        let params = FileWriteParams(path: path, content: content)
        let paramsData = try JSONEncoder().encode(params)
        let paramsAny = try JSONDecoder().decode(AnyCodable.self, from: paramsData)

        let result = try await executeMethod(method: .fileWrite, params: paramsAny)

        let resultData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(FileWriteResult.self, from: resultData)
    }

    /// List files in VS Code workspace directory
    func listFiles(path: String, recursive: Bool = false) async throws -> FileListResult {
        let params = FileListParams(path: path, recursive: recursive)
        let paramsData = try JSONEncoder().encode(params)
        let paramsAny = try JSONDecoder().decode(AnyCodable.self, from: paramsData)

        let result = try await executeMethod(method: .fileList, params: paramsAny)

        let resultData = try JSONEncoder().encode(result)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FileListResult.self, from: resultData)
    }

    /// Run a terminal command in VS Code
    func runTerminal(command: String, cwd: String? = nil) async throws -> TerminalRunResult {
        let params = TerminalRunParams(command: command, cwd: cwd)
        let paramsData = try JSONEncoder().encode(params)
        let paramsAny = try JSONDecoder().decode(AnyCodable.self, from: paramsData)

        let result = try await executeMethod(method: .terminalRun, params: paramsAny)

        let resultData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TerminalRunResult.self, from: resultData)
    }

    func startTerminalSession(_ params: TerminalSessionStartParams) async throws -> TerminalSessionStartResult {
        let result = try await executeMethod(method: .terminalSessionStart, params: try params.bridgeAnyCodable())
        return try result.decodeBridgeValue(TerminalSessionStartResult.self)
    }

    func sendTerminalInput(_ params: TerminalSessionInputParams) async throws {
        _ = try await executeMethod(method: .terminalSessionInput, params: try params.bridgeAnyCodable())
    }

    func resizeTerminalSession(_ params: TerminalSessionResizeParams) async throws {
        _ = try await executeMethod(method: .terminalSessionResize, params: try params.bridgeAnyCodable())
    }

    func closeTerminalSession(_ params: TerminalSessionCloseParams) async throws {
        _ = try await executeMethod(method: .terminalSessionClose, params: try params.bridgeAnyCodable())
    }

    /// Get workspace info from VS Code
    func getWorkspaceInfo() async throws -> WorkspaceInfoResult {
        let result = try await executeMethod(method: .workspaceInfo, params: .null)

        let resultData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(WorkspaceInfoResult.self, from: resultData)
    }

    // MARK: - Connection State Handling

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            print("[BridgeClient] Connection ready")
            isConnecting = false
            // Send hello to establish session
            Task {
                await sendHello()
            }

        case .waiting(let error):
            print("[BridgeClient] Connection waiting: \(error)")
            if isTimeoutWaitingError(error) {
                lastError = "Connection timed out. Check host/IP and port, then try again."
                cleanupConnection()
                scheduleReconnect()
            } else {
                // Connection is waiting and might recover automatically.
                lastError = "Network is waiting: \(error.localizedDescription)"
            }

        case .failed(let error):
            print("[BridgeClient] Connection failed: \(error)")
            lastError = "Connection failed: \(error.localizedDescription)"
            cleanupConnection()
            scheduleReconnect()

        case .cancelled:
            print("[BridgeClient] Connection cancelled")
            cleanupConnection()

        default:
            break
        }
    }

    private func cleanupConnection() {
        let wasConnected = isConnected

        connection = nil
        connectedSession = nil
        isConnected = false
        isConnecting = false
        messageBuffer = Data()

        // Cancel pending requests
        for (_, pending) in pendingRequests {
            pending.continuation.resume(throwing: BridgeError(code: .notConnected, message: "Connection lost"))
        }
        pendingRequests.removeAll()

        // Notify observers
        if wasConnected {
            NotificationCenter.default.post(
                name: .bridgeConnectionDidChange,
                object: self,
                userInfo: ["connected": false, "mode": BridgeMode.remote]
            )
        }
    }

    // MARK: - Handshake

    private func sendHello() async {
        guard let connection = connection else { return }

        let settings = BridgeSettingsStorage.shared.settings
        let axonVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        let hello = BridgeHello.fromAxon(
            axonVersion: axonVersion,
            deviceName: settings.effectiveDeviceName,
            pairingToken: settings.requiredPairingToken.isEmpty ? nil : settings.requiredPairingToken
        )

        let request = BridgeRequest(id: "hello", method: "hello", params: try? {
            let data = try JSONEncoder().encode(hello)
            return try JSONDecoder().decode(AnyCodable.self, from: data)
        }())

        do {
            let data = try BridgeMessage.encode(request)
            sendWebSocketMessage(data, on: connection)
            startReceiving(on: connection)
        } catch {
            print("[BridgeClient] Failed to send hello: \(error)")
            lastError = "Handshake failed: \(error.localizedDescription)"
            disconnect()
        }
    }

    private func handleWelcome(_ welcome: BridgeWelcome) {
        // Create session from welcome response
        let session = BridgeSession(
            id: UUID(uuidString: welcome.sessionId) ?? UUID(),
            workspaceId: welcome.workspaceId ?? "unknown",
            workspaceName: welcome.workspaceName ?? "VS Code",
            workspaceRoot: welcome.workspaceRoot ?? "",
            capabilities: (welcome.capabilities ?? []).compactMap { BridgeCapability(rawValue: $0) },
            extensionVersion: welcome.extensionVersion ?? "unknown"
        )

        connectedSession = session
        isConnected = true
        reconnectAttempts = 0

        print("[BridgeClient] Connected to VS Code: \(session.displayName) (\(session.workspaceRoot))")

        // Notify observers
        NotificationCenter.default.post(
            name: .bridgeConnectionDidChange,
            object: self,
            userInfo: [
                "connected": true,
                "session": session,
                "mode": BridgeMode.remote
            ]
        )
    }

    // MARK: - WebSocket Message Handling

    private func sendWebSocketMessage(_ data: Data, on connection: NWConnection) {
        // Log outgoing message
        Task { @MainActor in
            BridgeLogService.shared.logOutgoing(data)
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "websocket", metadata: [metadata])

        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if let error = error {
                print("[BridgeClient] Send error: \(error)")
            }
        })
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[BridgeClient] Receive error: \(error)")
                Task { @MainActor in
                    self.cleanupConnection()
                    self.scheduleReconnect()
                }
                return
            }

            if let content = content, !content.isEmpty {
                Task { @MainActor in
                    BridgeLogService.shared.logIncoming(content)
                    self.handleReceivedData(content)
                }
            }

            // Continue receiving if still connected
            if self.connection != nil {
                self.startReceiving(on: connection)
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        do {
            let message = try BridgeMessage.decode(from: data)

            switch message {
            case .request(let request):
                handleIncomingRequest(request)

            case .response(let response):
                handleIncomingResponse(response)

            case .notification(let notification):
                handleIncomingNotification(notification)
            }
        } catch {
            print("[BridgeClient] Failed to decode message: \(error)")
            if let str = String(data: data, encoding: .utf8) {
                print("[BridgeClient] Raw message: \(str.prefix(200))")
            }
        }
    }

    private func handleIncomingRequest(_ request: BridgeRequest) {
        // In Remote Mode, Axon is the puppeteer, so we don't expect requests from VS Code
        // VS Code only sends responses
        print("[BridgeClient] Unexpected request from server: \(request.method)")
    }

    private func handleIncomingResponse(_ response: BridgeResponse) {
        // Special handling for hello response
        if response.id == "hello" {
            if let error = response.error {
                print("[BridgeClient] Hello failed: \(error.message)")
                lastError = "Connection rejected: \(error.message)"
                disconnect()
                return
            }

            if let result = response.result {
                do {
                    let resultData = try JSONEncoder().encode(result)
                    let welcome = try JSONDecoder().decode(BridgeWelcome.self, from: resultData)
                    handleWelcome(welcome)
                } catch {
                    print("[BridgeClient] Failed to decode welcome: \(error)")
                    lastError = "Invalid welcome response"
                    disconnect()
                }
            }
            return
        }

        // Handle normal responses
        guard let pending = pendingRequests.removeValue(forKey: response.id) else {
            print("[BridgeClient] Received response for unknown request: \(response.id)")
            return
        }

        pending.continuation.resume(returning: response)
    }

    private func handleIncomingNotification(_ notification: BridgeNotification) {
        print("[BridgeClient] Received notification: \(notification.method)")
        handleTerminalNotification(notification)
    }

    private func handleTerminalNotification(_ notification: BridgeNotification) {
        guard let params = notification.params else { return }

        do {
            switch notification.method {
            case TerminalBridgeMethod.output:
                let output = try params.decodeBridgeValue(TerminalSessionOutputNotification.self)
                NotificationCenter.default.post(name: .terminalSessionOutput, object: output)
            case TerminalBridgeMethod.exited:
                let exited = try params.decodeBridgeValue(TerminalSessionExitedNotification.self)
                NotificationCenter.default.post(name: .terminalSessionExited, object: exited)
            default:
                break
            }
        } catch {
            print("[BridgeClient] Failed to decode terminal notification: \(error)")
        }
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        guard reconnectTimer == nil else { return }

        let settings = BridgeSettingsStorage.shared.settings
        guard settings.enabled && settings.mode == .remote else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            isConnecting = false
            lastError = "Unable to reach VS Code after multiple retries. Verify the server address, then reconnect."
            print("[BridgeClient] Reconnect limit reached (\(maxReconnectAttempts))")
            return
        }

        // Exponential backoff
        let delay = min(baseReconnectInterval * pow(2.0, Double(reconnectAttempts)), maxReconnectInterval)
        reconnectAttempts += 1

        print("[BridgeClient] Scheduling reconnect in \(Int(delay))s (attempt \(reconnectAttempts))...")

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.reconnectTimer = nil
                await self?.connectUsingSettings()
            }
        }
    }

    private func cancelReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - TLS Configuration

    private func configureTLS(_ options: NWProtocolTLS.Options) {
        // Configure TLS for self-signed certificates
        let settings = BridgeSettingsStorage.shared.settings

        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { (_, trust, completionHandler) in
            // For self-signed certs, we could verify the fingerprint here
            // For now, allow any certificate (user should be on trusted LAN)
            // TODO: Implement fingerprint pinning using settings.trustedCertFingerprints

            completionHandler(true)
        }, queue)
    }

    private func isTimeoutWaitingError(_ error: NWError) -> Bool {
        switch error {
        case .posix(let code):
            return code == .ETIMEDOUT
        default:
            return false
        }
    }
}
