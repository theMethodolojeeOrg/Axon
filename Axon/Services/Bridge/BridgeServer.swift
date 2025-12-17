//
//  BridgeServer.swift
//  Axon
//
//  WebSocket server using Network.framework that allows VS Code to connect
//  and receive commands from the AI. Axon is the "puppeteer", VS Code is the "puppet".
//
//  Supports multiple concurrent VS Code connections (multi-session).
//

import Foundation
import Network
import Combine

@MainActor
class BridgeServer: ObservableObject {
    static let shared = BridgeServer()

    // MARK: - Published State

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    /// All active sessions (keyed by session ID)
    @Published private(set) var sessions: [String: BridgeSession] = [:]

    /// Whether any VS Code is connected
    var isConnected: Bool {
        !connections.isEmpty
    }

    /// The first connected session (for backward compatibility with single-session code)
    var connectedSession: BridgeSession? {
        sessions.values.first
    }

    /// Number of active connections
    var connectionCount: Int {
        connections.count
    }

    // MARK: - Private Properties

    private var listener: NWListener?

    /// Active connections keyed by connection ID (UUID string)
    private var connections: [String: NWConnection] = [:]

    /// Maps connection ID to session ID (for reverse lookup)
    private var connectionToSession: [String: String] = [:]

    /// Maps session ID to connection ID (for sending to specific session)
    private var sessionToConnection: [String: String] = [:]

    /// Pending requests keyed by request ID
    private var pendingRequests: [String: PendingBridgeRequest] = [:]

    /// Message buffers per connection (keyed by connection ID)
    private var messageBuffers: [String: Data] = [:]

    private var port: UInt16 = 8081

    private let queue = DispatchQueue(label: "com.axon.bridge", qos: .userInitiated)

    // MARK: - Configuration

    private let defaultTimeout: TimeInterval = 30.0
    private let maxMessageSize = 10 * 1024 * 1024  // 10MB

    private init() {}

    // MARK: - Server Control

    /// Start the WebSocket server on the specified port
    func start(port: UInt16 = 8081) async {
        guard !isRunning else {
            print("[BridgeServer] Already running")
            return
        }

        self.port = port

        do {
            // Configure WebSocket parameters
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true

            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

            // Only listen on localhost for security
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    await self?.handleNewConnection(connection)
                }
            }

            listener?.start(queue: queue)
            isRunning = true
            lastError = nil
            print("[BridgeServer] Started on port \(port)")

        } catch {
            lastError = "Failed to start: \(error.localizedDescription)"
            print("[BridgeServer] Failed to start: \(error)")
        }
    }

    /// Stop the server and disconnect all clients
    func stop() async {
        guard isRunning else { return }

        // Cancel pending requests
        for (_, pending) in pendingRequests {
            pending.continuation.resume(throwing: BridgeError(code: .notConnected, message: "Server stopped"))
        }
        pendingRequests.removeAll()

        // Close all connections
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        sessions.removeAll()
        connectionToSession.removeAll()
        sessionToConnection.removeAll()
        messageBuffers.removeAll()

        // Stop listener
        listener?.cancel()
        listener = nil
        isRunning = false

        print("[BridgeServer] Stopped")
    }

    /// Disconnect a specific session
    func disconnectSession(_ sessionId: String) {
        guard let connectionId = sessionToConnection[sessionId],
              let connection = connections[connectionId] else {
            return
        }
        connection.cancel()
        cleanupConnection(connectionId: connectionId)
    }

    // MARK: - Message Sending

    /// Send a request to VS Code and wait for response
    /// - Parameters:
    ///   - method: The bridge method to call
    ///   - params: Optional parameters
    ///   - sessionId: Target a specific session (nil = first available)
    ///   - timeout: Request timeout
    func sendRequest(method: String, params: AnyCodable? = nil, sessionId: String? = nil, timeout: TimeInterval? = nil) async throws -> BridgeResponse {
        // Find the target connection
        let targetConnection: NWConnection
        if let sessionId = sessionId {
            guard let connectionId = sessionToConnection[sessionId],
                  let connection = connections[connectionId] else {
                throw BridgeError(code: .notConnected, message: "Session not found: \(sessionId)")
            }
            targetConnection = connection
        } else {
            // Use first available connection (backward compatibility)
            guard let firstConnection = connections.values.first else {
                throw BridgeError(code: .notConnected, message: "No VS Code connection")
            }
            targetConnection = firstConnection
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
                self.sendWebSocketMessage(data, on: targetConnection)
            } catch {
                pendingRequests.removeValue(forKey: request.id)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Send a notification (no response expected)
    /// - Parameters:
    ///   - method: The notification method
    ///   - params: Optional parameters
    ///   - sessionId: Target a specific session (nil = broadcast to all)
    func sendNotification(method: String, params: AnyCodable? = nil, sessionId: String? = nil) {
        let notification = BridgeNotification(method: method, params: params)

        do {
            let data = try BridgeMessage.encode(notification)

            if let sessionId = sessionId {
                // Send to specific session
                guard let connectionId = sessionToConnection[sessionId],
                      let connection = connections[connectionId] else {
                    print("[BridgeServer] Cannot send notification: session not found")
                    return
                }
                sendWebSocketMessage(data, on: connection)
            } else {
                // Broadcast to all connections
                for connection in connections.values {
                    sendWebSocketMessage(data, on: connection)
                }
            }
        } catch {
            print("[BridgeServer] Failed to encode notification: \(error)")
        }
    }

    /// Send a response to an incoming request
    private func sendResponse(_ response: BridgeResponse, on connection: NWConnection) {
        do {
            let data = try BridgeMessage.encode(response)
            sendWebSocketMessage(data, on: connection)
        } catch {
            print("[BridgeServer] Failed to encode response: \(error)")
        }
    }

    // MARK: - Session Lookup

    /// Get a session by ID
    func session(for sessionId: String) -> BridgeSession? {
        sessions[sessionId]
    }

    /// Get a session by workspace ID (e.g., "sha256:...")
    func session(forWorkspaceId workspaceId: String) -> BridgeSession? {
        sessions.values.first { $0.workspaceId == workspaceId }
    }

    /// Get all sessions as an array (sorted by connected time)
    var allSessions: [BridgeSession] {
        sessions.values.sorted { $0.connectedAt < $1.connectedAt }
    }

    // MARK: - Tool Execution

    /// Execute a bridge method on VS Code (called by ToolProxyService)
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
        let jsonString = String(data: resultData, encoding: .utf8) ?? "(unable to decode)"

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(FileListResult.self, from: resultData)
        } catch {
            // Wrap the error with the raw JSON for debugging
            throw BridgeDecodingError(underlying: error, rawJSON: String(jsonString.prefix(1000)))
        }
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

    /// Get workspace info from VS Code
    func getWorkspaceInfo() async throws -> WorkspaceInfoResult {
        let result = try await executeMethod(method: .workspaceInfo, params: .null)

        let resultData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(WorkspaceInfoResult.self, from: resultData)
    }

    // MARK: - Connection Handling

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("[BridgeServer] Listener ready on port \(port)")
        case .failed(let error):
            lastError = "Listener failed: \(error.localizedDescription)"
            print("[BridgeServer] Listener failed: \(error)")
            isRunning = false
        case .cancelled:
            print("[BridgeServer] Listener cancelled")
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ newConnection: NWConnection) async {
        let settings = BridgeSettingsStorage.shared.settings

        // Check if we allow multiple sessions
        if !settings.allowMultipleSessions && !connections.isEmpty {
            print("[BridgeServer] Rejecting connection: already connected (multi-session disabled)")
            newConnection.cancel()
            return
        }

        // Generate a unique connection ID
        let connectionId = UUID().uuidString
        print("[BridgeServer] New connection from VS Code (connectionId: \(connectionId.prefix(8)))")

        connections[connectionId] = newConnection
        messageBuffers[connectionId] = Data()

        newConnection.stateUpdateHandler = { [weak self, connectionId] state in
            Task { @MainActor in
                self?.handleConnectionState(state, connectionId: connectionId)
            }
        }

        newConnection.start(queue: queue)
        startReceiving(on: newConnection, connectionId: connectionId)
    }

    private func handleConnectionState(_ state: NWConnection.State, connectionId: String) {
        switch state {
        case .ready:
            print("[BridgeServer] Connection ready (connectionId: \(connectionId.prefix(8)))")
            // Don't consider connected yet - wait for handshake

        case .failed(let error):
            print("[BridgeServer] Connection failed: \(error) (connectionId: \(connectionId.prefix(8)))")
            lastError = "Connection failed: \(error.localizedDescription)"
            cleanupConnection(connectionId: connectionId)

        case .cancelled:
            print("[BridgeServer] Connection cancelled (connectionId: \(connectionId.prefix(8)))")
            cleanupConnection(connectionId: connectionId)

        default:
            break
        }
    }

    /// Clean up a disconnected connection and its associated session
    private func cleanupConnection(connectionId: String) {
        // Remove connection
        connections.removeValue(forKey: connectionId)
        messageBuffers.removeValue(forKey: connectionId)

        // Find and remove associated session
        if let sessionId = connectionToSession.removeValue(forKey: connectionId) {
            let session = sessions.removeValue(forKey: sessionId)
            sessionToConnection.removeValue(forKey: sessionId)

            // Notify observers
            NotificationCenter.default.post(
                name: .bridgeConnectionDidChange,
                object: self,
                userInfo: [
                    "connected": false,
                    "sessionId": sessionId,
                    "session": session as Any,
                    "remainingSessions": sessions.count
                ]
            )

            print("[BridgeServer] Session disconnected: \(session?.displayName ?? sessionId) (\(sessions.count) remaining)")
        }

        // Note: We don't cancel pending requests here because they're keyed by request ID,
        // not connection ID. In a multi-session setup, we'd need to track which requests
        // belong to which session if we wanted to cancel them on disconnect.
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
                print("[BridgeServer] Send error: \(error)")
            }
        })
    }

    private func startReceiving(on connection: NWConnection, connectionId: String) {
        connection.receiveMessage { [weak self, connectionId] content, context, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[BridgeServer] Receive error: \(error) (connectionId: \(connectionId.prefix(8)))")
                Task { @MainActor in
                    self.cleanupConnection(connectionId: connectionId)
                }
                return
            }

            if let content = content, !content.isEmpty {
                Task { @MainActor in
                    // Log incoming message
                    BridgeLogService.shared.logIncoming(content)
                    await self.handleReceivedData(content, connectionId: connectionId)
                }
            }

            // Continue receiving if connection still exists
            if self.connections[connectionId] != nil {
                self.startReceiving(on: connection, connectionId: connectionId)
            }
        }
    }

    private func handleReceivedData(_ data: Data, connectionId: String) async {
        do {
            let message = try BridgeMessage.decode(from: data)

            switch message {
            case .request(let request):
                await handleIncomingRequest(request, connectionId: connectionId)

            case .response(let response):
                handleIncomingResponse(response)

            case .notification(let notification):
                handleIncomingNotification(notification, connectionId: connectionId)
            }
        } catch {
            print("[BridgeServer] Failed to decode message: \(error) (connectionId: \(connectionId.prefix(8)))")
            if let str = String(data: data, encoding: .utf8) {
                print("[BridgeServer] Raw message: \(str.prefix(200))")
            }
        }
    }

    private func handleIncomingRequest(_ request: BridgeRequest, connectionId: String) async {
        print("[BridgeServer] Received request: \(request.method) (connectionId: \(connectionId.prefix(8)))")

        guard let connection = connections[connectionId] else { return }

        // Handle handshake specially
        if request.method == BridgeMethod.hello.rawValue {
            await handleHello(request, on: connection, connectionId: connectionId)
            return
        }

        // For other methods, we don't expect requests FROM VS Code in MVP
        // VS Code only sends responses to our requests
        let error = BridgeError(code: .methodNotFound, message: "Unexpected request from client")
        sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
    }

    private func handleIncomingResponse(_ response: BridgeResponse) {
        guard let pending = pendingRequests.removeValue(forKey: response.id) else {
            print("[BridgeServer] Received response for unknown request: \(response.id)")
            return
        }

        pending.continuation.resume(returning: response)
    }

    private func handleIncomingNotification(_ notification: BridgeNotification, connectionId: String) {
        print("[BridgeServer] Received notification: \(notification.method) (connectionId: \(connectionId.prefix(8)))")
        // Handle notifications from VS Code if needed (e.g., file changed events)
    }

    private func handleHello(_ request: BridgeRequest, on connection: NWConnection, connectionId: String) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing hello parameters")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let helloData = try JSONEncoder().encode(params)
            let hello = try JSONDecoder().decode(BridgeHello.self, from: helloData)

            // Enforce optional pairing token (defense-in-depth against arbitrary localhost clients)
            let requiredToken = BridgeSettingsStorage.shared.settings.requiredPairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !requiredToken.isEmpty {
                let presentedToken = (hello.pairingToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if presentedToken != requiredToken {
                    let error = BridgeError(code: .invalidRequest, message: "Pairing token mismatch. Set axonBridge.pairingToken in VS Code to match Axon Bridge settings.")
                    sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
                    connection.cancel()
                    cleanupConnection(connectionId: connectionId)
                    return
                }
            }

            // Create session - handle both old and new BridgeHello formats
            let capabilities = (hello.capabilities ?? []).compactMap { BridgeCapability(rawValue: $0) }

            let session = BridgeSession(
                workspaceId: hello.workspaceId ?? "unknown",
                workspaceName: hello.workspaceName ?? "VS Code",
                workspaceRoot: hello.workspaceRoot ?? "",
                capabilities: capabilities.isEmpty ? BridgeCapability.allCases : capabilities,
                extensionVersion: hello.extensionVersion ?? "unknown"
            )

            let sessionId = session.id.uuidString

            // Store session and mappings
            sessions[sessionId] = session
            connectionToSession[connectionId] = sessionId
            sessionToConnection[sessionId] = connectionId

            print("[BridgeServer] VS Code connected: \(session.displayName) (\(session.workspaceRoot)) [session: \(sessionId.prefix(8)), total: \(sessions.count)]")

            // Record in settings for auto-reconnect
            BridgeSettingsStorage.shared.recordConnection(session)

            // Notify observers that VS Code connected
            NotificationCenter.default.post(
                name: .bridgeConnectionDidChange,
                object: self,
                userInfo: [
                    "connected": true,
                    "session": session,
                    "sessionId": sessionId,
                    "totalSessions": sessions.count
                ]
            )

            // Send welcome response using the new format
            let welcome = BridgeWelcome.fromAxon(
                sessionId: sessionId,
                axonVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                supportedMethods: BridgeMethod.allCases.map { $0.rawValue }
            )

            let welcomeData = try JSONEncoder().encode(welcome)
            let welcomeAny = try JSONDecoder().decode(AnyCodable.self, from: welcomeData)

            sendResponse(BridgeResponse.success(id: request.id, result: welcomeAny), on: connection)

        } catch {
            print("[BridgeServer] Failed to parse hello: \(error)")
            let bridgeError = BridgeError(code: .invalidParams, message: "Invalid hello parameters")
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when VS Code bridge connection state changes
    /// userInfo: ["connected": Bool, "session": BridgeSession?]
    static let bridgeConnectionDidChange = Notification.Name("BridgeConnectionDidChange")
}

// MARK: - Decoding Error with Raw JSON

/// Error that wraps a decoding error with the raw JSON for debugging
struct BridgeDecodingError: Error, LocalizedError {
    let underlying: Error
    let rawJSON: String

    var errorDescription: String? {
        """
        Failed to decode response: \(underlying.localizedDescription)

        Raw JSON (truncated):
        \(rawJSON)
        """
    }
}
