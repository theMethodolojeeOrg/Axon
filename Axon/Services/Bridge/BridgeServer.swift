//
//  BridgeServer.swift
//  Axon
//
//  WebSocket server using Network.framework that allows VS Code to connect
//  and receive commands from the AI. Axon is the "puppeteer", VS Code is the "puppet".
//

import Foundation
import Network
import Combine

@MainActor
class BridgeServer: ObservableObject {
    static let shared = BridgeServer()

    // MARK: - Published State

    @Published private(set) var isRunning = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedSession: BridgeSession?
    @Published private(set) var lastError: String?

    // MARK: - Private Properties

    private var listener: NWListener?
    private var connection: NWConnection?
    private var pendingRequests: [String: PendingBridgeRequest] = [:]
    private var messageBuffer = Data()
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

    /// Stop the server and disconnect any clients
    func stop() async {
        guard isRunning else { return }

        // Cancel pending requests
        for (_, pending) in pendingRequests {
            pending.continuation.resume(throwing: BridgeError(code: .notConnected, message: "Server stopped"))
        }
        pendingRequests.removeAll()

        // Close connection
        connection?.cancel()
        connection = nil
        connectedSession = nil
        isConnected = false

        // Stop listener
        listener?.cancel()
        listener = nil
        isRunning = false

        print("[BridgeServer] Stopped")
    }

    // MARK: - Message Sending

    /// Send a request to VS Code and wait for response
    func sendRequest(method: String, params: AnyCodable? = nil, timeout: TimeInterval? = nil) async throws -> BridgeResponse {
        guard isConnected, let connection = connection else {
            throw BridgeError(code: .notConnected, message: "No VS Code connection")
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
            print("[BridgeServer] Cannot send notification: not connected")
            return
        }

        let notification = BridgeNotification(method: method, params: params)

        do {
            let data = try BridgeMessage.encode(notification)
            sendWebSocketMessage(data, on: connection)
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
        // Only allow one connection at a time (MVP)
        if connection != nil {
            print("[BridgeServer] Rejecting connection: already connected")
            newConnection.cancel()
            return
        }

        print("[BridgeServer] New connection from VS Code")
        connection = newConnection

        newConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state)
            }
        }

        newConnection.start(queue: queue)
        startReceiving(on: newConnection)
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            print("[BridgeServer] Connection ready")
            // Don't set isConnected yet - wait for handshake

        case .failed(let error):
            print("[BridgeServer] Connection failed: \(error)")
            lastError = "Connection failed: \(error.localizedDescription)"
            disconnectClient()

        case .cancelled:
            print("[BridgeServer] Connection cancelled")
            disconnectClient()

        default:
            break
        }
    }

    private func disconnectClient() {
        let wasConnected = isConnected

        connection = nil
        connectedSession = nil
        isConnected = false
        messageBuffer = Data()

        // Cancel pending requests
        for (_, pending) in pendingRequests {
            pending.continuation.resume(throwing: BridgeError(code: .notConnected, message: "Connection lost"))
        }
        pendingRequests.removeAll()

        // Notify observers that VS Code disconnected
        if wasConnected {
            NotificationCenter.default.post(
                name: .bridgeConnectionDidChange,
                object: self,
                userInfo: ["connected": false]
            )
        }
    }

    // MARK: - WebSocket Message Handling

    private func sendWebSocketMessage(_ data: Data, on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "websocket", metadata: [metadata])

        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if let error = error {
                print("[BridgeServer] Send error: \(error)")
            }
        })
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[BridgeServer] Receive error: \(error)")
                Task { @MainActor in
                    self.disconnectClient()
                }
                return
            }

            if let content = content, !content.isEmpty {
                Task { @MainActor in
                    await self.handleReceivedData(content)
                }
            }

            // Continue receiving
            if self.connection != nil {
                self.startReceiving(on: connection)
            }
        }
    }

    private func handleReceivedData(_ data: Data) async {
        do {
            let message = try BridgeMessage.decode(from: data)

            switch message {
            case .request(let request):
                await handleIncomingRequest(request)

            case .response(let response):
                handleIncomingResponse(response)

            case .notification(let notification):
                handleIncomingNotification(notification)
            }
        } catch {
            print("[BridgeServer] Failed to decode message: \(error)")
            if let str = String(data: data, encoding: .utf8) {
                print("[BridgeServer] Raw message: \(str.prefix(200))")
            }
        }
    }

    private func handleIncomingRequest(_ request: BridgeRequest) async {
        print("[BridgeServer] Received request: \(request.method)")

        guard let connection = connection else { return }

        // Handle handshake specially
        if request.method == BridgeMethod.hello.rawValue {
            await handleHello(request, on: connection)
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

    private func handleIncomingNotification(_ notification: BridgeNotification) {
        print("[BridgeServer] Received notification: \(notification.method)")
        // Handle notifications from VS Code if needed (e.g., file changed events)
    }

    private func handleHello(_ request: BridgeRequest, on connection: NWConnection) async {
        guard let params = request.params else {
            let error = BridgeError(code: .invalidParams, message: "Missing hello parameters")
            sendResponse(BridgeResponse.failure(id: request.id, error: error), on: connection)
            return
        }

        do {
            let helloData = try JSONEncoder().encode(params)
            let hello = try JSONDecoder().decode(BridgeHello.self, from: helloData)

            // Create session
            let capabilities = hello.capabilities.compactMap { BridgeCapability(rawValue: $0) }

            let session = BridgeSession(
                workspaceId: hello.workspaceId,
                workspaceName: hello.workspaceName,
                workspaceRoot: hello.workspaceRoot,
                capabilities: capabilities.isEmpty ? BridgeCapability.allCases : capabilities,
                extensionVersion: hello.extensionVersion
            )

            connectedSession = session
            isConnected = true

            print("[BridgeServer] VS Code connected: \(session.displayName) (\(session.workspaceRoot))")

            // Notify observers that VS Code connected
            NotificationCenter.default.post(
                name: .bridgeConnectionDidChange,
                object: self,
                userInfo: ["connected": true, "session": session]
            )

            // Send welcome response
            let welcome = BridgeWelcome(
                sessionId: session.id.uuidString,
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
