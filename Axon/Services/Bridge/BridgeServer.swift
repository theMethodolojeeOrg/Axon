//
//  BridgeServer.swift
//  Axon
//
//  WebSocket server using Network.framework that allows VS Code to connect
//  and receive commands from Axon. Axon is the "puppeteer", VS Code is the "puppet".
//
//  Supports multiple concurrent VS Code connections (multi-session).
//

import Foundation
import Network
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

    /// LAN addresses the server is reachable on (populated when running)
    @Published private(set) var localAddresses: [BridgeNetworkAddress] = []

    /// The server's TLS certificate fingerprint (SHA-256 hex), if TLS is active
    @Published private(set) var certificateFingerprint: String?

    // MARK: - Host Mode Helpers

    /// Generate a QR payload for this running server.
    /// Returns nil if the server is not running or no LAN address is available.
    func generateQRPayload() -> String? {
        guard isRunning else { return nil }
        guard let primaryIP = localAddresses.first?.ipAddress ?? BridgeNetworkUtils.primaryLANAddress() else { return nil }
        let settings = BridgeSettingsStorage.shared.settings
        return BridgeQRCodeGenerator.generatePayload(
            host: primaryIP,
            port: port,
            tlsEnabled: settings.tlsEnabled,
            pairingToken: settings.requiredPairingToken.isEmpty ? nil : settings.requiredPairingToken
        )
    }

    #if os(iOS)
    /// Generate a QR code image for this running server.
    func generateQRCodeImage(size: CGFloat = 200) -> UIImage? {
        guard let payload = generateQRPayload() else { return nil }
        return BridgeQRCodeGenerator.generateImage(from: payload, size: size)
    }
    #elseif os(macOS)
    /// Generate a QR code image for this running server.
    func generateQRCodeImage(size: CGFloat = 200) -> NSImage? {
        guard let payload = generateQRPayload() else { return nil }
        return BridgeQRCodeGenerator.generateImage(from: payload, size: size)
    }
    #endif

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
            localAddresses = BridgeNetworkUtils.getLocalIPv4Addresses()
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
        localAddresses = []
        certificateFingerprint = nil

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

    func startTerminalSession(_ params: TerminalSessionStartParams) async throws -> TerminalSessionStartResult {
        let result = try await sendRequest(method: BridgeMethod.terminalSessionStart.rawValue, params: try params.bridgeAnyCodable())
        if let error = result.error {
            throw error
        }
        guard let payload = result.result else {
            throw BridgeError(code: .terminalError, message: "Missing terminal session start result")
        }
        return try payload.decodeBridgeValue(TerminalSessionStartResult.self)
    }

    func sendTerminalInput(_ params: TerminalSessionInputParams) async throws {
        let result = try await sendRequest(method: BridgeMethod.terminalSessionInput.rawValue, params: try params.bridgeAnyCodable())
        if let error = result.error {
            throw error
        }
    }

    func resizeTerminalSession(_ params: TerminalSessionResizeParams) async throws {
        let result = try await sendRequest(method: BridgeMethod.terminalSessionResize.rawValue, params: try params.bridgeAnyCodable())
        if let error = result.error {
            throw error
        }
    }

    func closeTerminalSession(_ params: TerminalSessionCloseParams) async throws {
        let result = try await sendRequest(method: BridgeMethod.terminalSessionClose.rawValue, params: try params.bridgeAnyCodable())
        if let error = result.error {
            throw error
        }
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

        // Route guest sessions to guest handler (they have a different allowlist)
        if let sessionId = connectionToSession[connectionId],
           let session = sessions[sessionId],
           session.sessionType == .guest {
            await handleGuestRequest(request, session: session, on: connection)
            return
        }

        // Host sessions: allow a small set of Axon-originating APIs (setup + chat mirror)
        guard let method = BridgeMethod(rawValue: request.method) else {
            let error = BridgeError(code: .methodNotFound, message: "Unknown method: \(request.method)")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        switch method {
        case .getPairingInfo:
            await handleGetPairingInfo(request, on: connection)

        case .chatListConversations:
            await handleChatListConversations(request, on: connection)

        case .chatGetMessages:
            await handleChatGetMessages(request, on: connection)

        case .axonDiscoverActions:
            await handleAxonDiscoverActions(request, on: connection)

        case .axonInvokeAction:
            await handleAxonInvokeAction(request, on: connection)

        case .axonGetState:
            await handleAxonGetState(request, on: connection)

        // Mac System operations (iOS → Mac remote control)
        case .systemInfo:
            await handleSystemInfo(request, on: connection)
        case .systemProcesses:
            await handleSystemProcesses(request, on: connection)
        case .systemDiskUsage:
            await handleSystemDiskUsage(request, on: connection)
        case .clipboardRead:
            await handleClipboardRead(request, on: connection)
        case .clipboardWrite:
            await handleClipboardWrite(request, on: connection)
        case .notificationSend:
            await handleNotificationSend(request, on: connection)
        case .spotlightSearch:
            await handleSpotlightSearch(request, on: connection)
        case .fileFind:
            await handleFileFind(request, on: connection)
        case .fileMetadata:
            await handleFileMetadata(request, on: connection)
        case .appList:
            await handleAppList(request, on: connection)
        case .appLaunch:
            await handleAppLaunch(request, on: connection)
        case .screenshot:
            await handleScreenshot(request, on: connection)
        case .networkInfo:
            await handleNetworkInfo(request, on: connection)
        case .networkPing:
            await handleNetworkPing(request, on: connection)
        case .shellExecute:
            await handleShellExecute(request, on: connection)

        // Everything else is not allowed FROM VS Code.
        default:
            let error = BridgeError(code: .methodNotFound, message: "Unexpected request from client")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
        }
    }

    // MARK: - VS Code → Axon (Setup + Chat Mirror)

    private struct PairingInfo: Codable {
        let axonBridgeWsLocalhostUrl: String
        let axonBridgePort: UInt16
        let requiredPairingToken: String?
        let deviceName: String?
        let isRunning: Bool
        let connectionCount: Int
        let qrPayload: String
    }

    private func handleGetPairingInfo(_ request: BridgeRequest, on connection: NWConnection) async {
        // Note: Axon’s BridgeServer listens on localhost by design.
        // This info is still useful for showing the VSIX how to connect, and for QR payload.
        let settings = BridgeSettingsStorage.shared.settings
        let port = settings.port
        let token = settings.requiredPairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenOrNil: String? = token.isEmpty ? nil : token

        let wsUrl = "ws://localhost:\(port)"
        let deviceName = settings.effectiveDeviceName

        // Simple payload; the phone-side QR can interpret it however it wants.
        // We include token if present.
        var payload = wsUrl
        if let t = tokenOrNil {
            payload += "?pairingToken=\(t)"
        }

        let info = PairingInfo(
            axonBridgeWsLocalhostUrl: wsUrl,
            axonBridgePort: port,
            requiredPairingToken: tokenOrNil,
            deviceName: deviceName,
            isRunning: isRunning,
            connectionCount: connectionCount,
            qrPayload: payload
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(info)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: "Failed to encode pairing info: \(error.localizedDescription)")
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private struct ChatConversationSummary: Codable {
        let id: String
        let title: String
        let updatedAt: Date?
        let messageCount: Int?
    }

    private struct ChatListConversationsResult: Codable {
        let conversations: [ChatConversationSummary]
    }

    private func handleChatListConversations(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            // Ensure local list is up to date.
            try await ConversationService.shared.listConversations(limit: 50, offset: 0)

            let summaries = ConversationService.shared.conversations.map { c in
                ChatConversationSummary(
                    id: c.id,
                    title: c.title,
                    updatedAt: c.updatedAt,
                    messageCount: c.messageCount
                )
            }

            let result = ChatListConversationsResult(conversations: summaries)
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: "Failed to list conversations: \(error.localizedDescription)")
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private struct ChatGetMessagesParams: Codable {
        let conversationId: String
        let limit: Int?
    }

    private struct ChatMessageDTO: Codable {
        let id: String
        let role: String
        let content: String
        let createdAt: Date?
    }

    private struct ChatGetMessagesResult: Codable {
        let conversationId: String
        let messages: [ChatMessageDTO]
    }

    private func handleChatGetMessages(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let paramsAny = request.params else {
            let err = BridgeError(code: .invalidParams, message: "Missing params")
            sendResponse(BridgeResponse.failure(id: request.id, error: err), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(paramsAny)
            let params = try JSONDecoder().decode(ChatGetMessagesParams.self, from: paramsData)

            let limit = params.limit ?? 100
            let messages = try await ConversationService.shared.getMessages(conversationId: params.conversationId, limit: limit)

            let dtos = messages.map { m in
                ChatMessageDTO(
                    id: m.id,
                    role: m.role.rawValue,
                    content: m.content,
                    createdAt: m.timestamp
                )
            }

            let result = ChatGetMessagesResult(conversationId: params.conversationId, messages: dtos)
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: "Failed to get messages: \(error.localizedDescription)")
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleAxonDiscoverActions(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            var filter: String?
            var platform: String?
            var view: String?

            if let paramsAny = request.params {
                let paramsData = try JSONEncoder().encode(paramsAny)
                let decoded = try JSONDecoder().decode(AxonDiscoverActionsParams.self, from: paramsData)
                filter = decoded.filter
                platform = decoded.platform
                view = decoded.view
            }

            let actions = AgentActionRegistry.shared.discoverActions(
                filter: filter,
                platform: platform,
                view: view
            )
            let result = AxonDiscoverActionsResult(actions: actions)
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(
                code: .internalError,
                message: "Failed to discover Axon actions: \(error.localizedDescription)"
            )
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleAxonInvokeAction(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let paramsAny = request.params else {
            let err = BridgeError(code: .invalidParams, message: "Missing params")
            sendResponse(BridgeResponse.failure(id: request.id, error: err), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(paramsAny)
            let decoded = try JSONDecoder().decode(AxonInvokeActionParams.self, from: paramsData)

            let result = await AgentActionRegistry.shared.invokeAction(
                id: decoded.id,
                params: decoded.params ?? [:],
                context: decoded.context ?? AgentActionContext(source: "bridge")
            )

            let payload = AxonInvokeActionResult(result: result)
            let data = try JSONEncoder().encode(payload)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(
                code: .internalError,
                message: "Failed to invoke Axon action: \(error.localizedDescription)"
            )
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleAxonGetState(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            let state = await AgentActionRegistry.shared.getState()
            let payload = AxonGetStateResult(state: state)
            let data = try JSONEncoder().encode(payload)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(
                code: .internalError,
                message: "Failed to query Axon state: \(error.localizedDescription)"
            )
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
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
            print("[BridgeServer] Failed to decode terminal notification: \(error)")
        }
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

            // Check if this is a guest connection
            if hello.isGuestConnection {
                await handleGuestHello(request, hello: hello, on: connection, connectionId: connectionId)
                return
            }

            // Host connection - enforce optional pairing token
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

            // Create host session - handle both old and new BridgeHello formats
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

    // MARK: - Guest Connection Handling

    /// Handle a guest connection attempting to use a shared AI
    private func handleGuestHello(_ request: BridgeRequest, hello: BridgeHello, on connection: NWConnection, connectionId: String) async {
        // Check if sharing is enabled
        let sharingSettings = SettingsViewModel.shared.settings.sharingSettings
        guard sharingSettings.enabled else {
            let error = BridgeError(code: .invalidRequest, message: "AI sharing is not enabled")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            connection.cancel()
            cleanupConnection(connectionId: connectionId)
            return
        }

        // Validate invitation token
        guard let token = hello.invitationToken else {
            let error = BridgeError(code: .invalidParams, message: "Missing invitation token")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            connection.cancel()
            cleanupConnection(connectionId: connectionId)
            return
        }

        guard let invitation = GuestSharingService.shared.validateInvitation(token: token) else {
            let error = BridgeError(code: .invalidRequest, message: "Invalid or expired invitation")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            connection.cancel()
            cleanupConnection(connectionId: connectionId)
            return
        }

        // Accept the guest connection
        do {
            let guestSession = try await GuestSharingService.shared.acceptGuestConnection(
                invitation: invitation,
                guestDeviceName: hello.guestName ?? hello.deviceName ?? "Unknown Guest"
            )

            // Create BridgeSession with guest type
            let session = BridgeSession(
                guestName: invitation.guestName,
                invitationId: invitation.id,
                guestCapabilities: invitation.grantedCapabilities,
                extensionVersion: hello.axonVersion ?? "unknown"
            )

            let sessionId = session.id.uuidString

            // Store session and mappings
            sessions[sessionId] = session
            connectionToSession[connectionId] = sessionId
            sessionToConnection[sessionId] = connectionId

            print("[BridgeServer] Guest connected: \(invitation.guestName) [session: \(sessionId.prefix(8)), guest session: \(guestSession.id.prefix(8))]")

            // Notify observers
            NotificationCenter.default.post(
                name: .bridgeConnectionDidChange,
                object: self,
                userInfo: [
                    "connected": true,
                    "session": session,
                    "sessionId": sessionId,
                    "isGuest": true,
                    "guestSession": guestSession,
                    "totalSessions": sessions.count
                ]
            )

            // Send welcome with guest-specific methods only
            let guestMethods = BridgeMethod.guestMethods.map { $0.rawValue }
            let welcome = BridgeWelcome.fromAxon(
                sessionId: sessionId,
                axonVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                supportedMethods: guestMethods
            )

            let welcomeData = try JSONEncoder().encode(welcome)
            let welcomeAny = try JSONDecoder().decode(AnyCodable.self, from: welcomeData)

            sendResponse(BridgeResponse.success(id: request.id, result: welcomeAny), on: connection)

        } catch {
            print("[BridgeServer] Failed to accept guest connection: \(error)")
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
            connection.cancel()
            cleanupConnection(connectionId: connectionId)
        }
    }

    // MARK: - Guest Method Handling

    /// Handle a request from a guest session
    private func handleGuestRequest(_ request: BridgeRequest, session: BridgeSession, on connection: NWConnection) async {
        guard session.sessionType == .guest else { return }
        guard let guestCapabilities = session.guestCapabilities else {
            let error = BridgeError(code: .invalidRequest, message: "Guest session missing capabilities")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        // Check if the method is available to guests
        guard let method = BridgeMethod(rawValue: request.method),
              method.availableToGuests else {
            let error = BridgeError(code: .methodNotFound, message: "Method not available to guests")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        // Rate limiting check
        guard let invitationId = session.invitationId,
              GuestSharingService.shared.recordQuery(sessionId: invitationId) else {
            let error = BridgeError(code: .invalidRequest, message: "Rate limit exceeded")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        // Handle guest-specific methods
        switch method {
        case .guestQueryMemories:
            await handleGuestQueryMemories(request, capabilities: guestCapabilities, on: connection)
        case .guestGetContext:
            await handleGuestGetContext(request, capabilities: guestCapabilities, on: connection)
        case .guestChatWithContext:
            await handleGuestChatWithContext(request, capabilities: guestCapabilities, on: connection)
        case .guestDisconnect:
            handleGuestDisconnect(request, session: session, on: connection)
        default:
            let error = BridgeError(code: .methodNotFound, message: "Unknown guest method")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
        }
    }

    private func handleGuestQueryMemories(_ request: BridgeRequest, capabilities: GuestCapabilities, on connection: NWConnection) async {
        guard capabilities.canQueryMemories else {
            let error = BridgeError(code: .invalidRequest, message: "Memory query not permitted")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        // TODO: Implement memory query with scope filtering
        // This would integrate with MemoryService and apply egoic-only filtering
        let result = AnyCodable.object([
            "memories": .array([]),
            "message": .string("Memory query not yet implemented")
        ])
        sendResponse(BridgeResponse.success(id: request.id, result: result), on: connection)
    }

    private func handleGuestGetContext(_ request: BridgeRequest, capabilities: GuestCapabilities, on connection: NWConnection) async {
        // TODO: Implement context retrieval for guests
        let result = AnyCodable.object([
            "context": .string(""),
            "message": .string("Context retrieval not yet implemented")
        ])
        sendResponse(BridgeResponse.success(id: request.id, result: result), on: connection)
    }

    private func handleGuestChatWithContext(_ request: BridgeRequest, capabilities: GuestCapabilities, on connection: NWConnection) async {
        guard capabilities.canChatWithContext else {
            let error = BridgeError(code: .invalidRequest, message: "Chat with context not permitted")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        // TODO: Implement chat with context for guests
        // This would use Axon service with scoped memory injection
        let result = AnyCodable.object([
            "response": .string(""),
            "message": .string("Chat not yet implemented")
        ])
        sendResponse(BridgeResponse.success(id: request.id, result: result), on: connection)
    }

    private func handleGuestDisconnect(_ request: BridgeRequest, session: BridgeSession, on connection: NWConnection) {
        if let invitationId = session.invitationId {
            GuestSharingService.shared.disconnectSession(invitationId)
        }

        let result = AnyCodable.object(["status": .string("disconnected")])
        sendResponse(BridgeResponse.success(id: request.id, result: result), on: connection)

        connection.cancel()
    }

    // MARK: - Mac System Operations Handlers

    private func handleSystemInfo(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            let result = try await MacSystemService.shared.getSystemInfo()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleSystemProcesses(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            var limit = 20
            if let params = request.params,
               let paramsData = try? JSONEncoder().encode(params),
               let decoded = try? JSONDecoder().decode(ProcessListParams.self, from: paramsData) {
                limit = decoded.limit ?? 20
            }

            let result = try await MacSystemService.shared.getRunningProcesses(limit: limit)
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleSystemDiskUsage(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            var path = "/"
            if let params = request.params,
               let paramsData = try? JSONEncoder().encode(params),
               let decoded = try? JSONDecoder().decode(DiskUsageParams.self, from: paramsData) {
                path = decoded.path
            }

            let result = try await MacSystemService.shared.getDiskUsage(path: path)
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleClipboardRead(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            let result = try await MacSystemService.shared.getClipboardContent()
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleClipboardWrite(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing content parameter")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(params)
            let decoded = try JSONDecoder().decode(ClipboardWriteParams.self, from: paramsData)

            let result = try await MacSystemService.shared.setClipboardContent(decoded.content)
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleNotificationSend(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing notification parameters")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(params)
            let decoded = try JSONDecoder().decode(NotificationSendParams.self, from: paramsData)

            let result = try await MacSystemService.shared.sendNotification(
                title: decoded.title,
                message: decoded.message,
                subtitle: decoded.subtitle,
                soundName: decoded.soundName
            )
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleSpotlightSearch(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing query parameter")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(params)
            let decoded = try JSONDecoder().decode(SpotlightSearchParams.self, from: paramsData)

            let result = try await MacSystemService.shared.spotlightSearch(
                query: decoded.query,
                limit: decoded.limit ?? 20,
                contentType: decoded.contentType
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleFileFind(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing pattern parameter")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(params)
            let decoded = try JSONDecoder().decode(FileFindParams.self, from: paramsData)

            let result = try await MacSystemService.shared.findFiles(
                pattern: decoded.pattern,
                directory: decoded.directory ?? "~",
                maxDepth: decoded.maxDepth ?? 3
            )
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleFileMetadata(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing path parameter")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(params)
            let decoded = try JSONDecoder().decode(FileMetadataParams.self, from: paramsData)

            let result = try await MacSystemService.shared.getFileMetadata(path: decoded.path)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleAppList(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            let result = try await MacSystemService.shared.getRunningApplications()
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleAppLaunch(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing appName parameter")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(params)
            let decoded = try JSONDecoder().decode(AppLaunchParams.self, from: paramsData)

            let result = try await MacSystemService.shared.launchApplication(
                name: decoded.appName,
                arguments: decoded.arguments
            )
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleScreenshot(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            var path: String?
            var display: Int?
            var includeWindows = true

            if let params = request.params,
               let paramsData = try? JSONEncoder().encode(params),
               let decoded = try? JSONDecoder().decode(ScreenshotParams.self, from: paramsData) {
                path = decoded.path
                display = decoded.display
                includeWindows = decoded.includeWindows ?? true
            }

            let result = try await MacSystemService.shared.takeScreenshot(
                path: path,
                display: display,
                includeWindows: includeWindows
            )
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleNetworkInfo(_ request: BridgeRequest, on connection: NWConnection) async {
        do {
            let result = try await MacSystemService.shared.getNetworkInfo()
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleNetworkPing(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing host parameter")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(params)
            let decoded = try JSONDecoder().decode(PingParams.self, from: paramsData)

            let result = try await MacSystemService.shared.pingHost(
                host: decoded.host,
                count: decoded.count ?? 4,
                timeout: decoded.timeout ?? 5000
            )
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
            sendResponse(BridgeResponse.failure(id: request.id, error: bridgeError), on: connection)
        }
    }

    private func handleShellExecute(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing command parameter")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let paramsData = try JSONEncoder().encode(params)
            let decoded = try JSONDecoder().decode(ShellExecuteParams.self, from: paramsData)

            let result = try await MacSystemService.shared.executeShellCommand(
                command: decoded.command,
                timeout: decoded.timeout ?? 30000,
                workingDirectory: decoded.workingDirectory
            )
            let data = try JSONEncoder().encode(result)
            let any = try JSONDecoder().decode(AnyCodable.self, from: data)
            sendResponse(BridgeResponse.success(id: request.id, result: any), on: connection)
        } catch {
            let bridgeError = BridgeError(code: .internalError, message: error.localizedDescription)
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
