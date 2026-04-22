//
//  BridgeProtocol.swift
//  Axon
//
//  JSON-RPC 2.0 style protocol for communication between Axon and VS Code.
//  Axon acts as the "puppeteer", VS Code as the "puppet".
//
//  Supports two connection modes:
//  - Local Mode: Axon is server (default), VS Code connects as client
//  - Remote Mode: VS Code is server, Axon connects as client (for LAN access)
//

import Foundation

// MARK: - Connection Mode

/// Connection mode determines which side acts as the WebSocket server
enum BridgeMode: String, Codable, CaseIterable {
    /// Axon acts as WebSocket server, VS Code connects (default, local development)
    case local = "local"
    /// VS Code acts as WebSocket server, Axon connects (remote/LAN access from phone)
    case remote = "remote"

    var displayName: String {
        switch self {
        case .local: return "Local (Axon Server)"
        case .remote: return "Remote (VS Code Server)"
        }
    }
}

/// Role in the puppeteer/puppet relationship (independent of connection direction)
enum BridgeRole: String, Codable {
    /// Axon - sends commands, controls VS Code
    case puppeteer = "puppeteer"
    /// VS Code - receives and executes commands
    case puppet = "puppet"
}

// MARK: - Session Type (for AI Sharing)

/// Type of session connection determining access level and capabilities
enum SessionType: String, Codable, CaseIterable {
    /// Full access - the host symbiont (current default behavior)
    case host = "host"
    /// Invited access via sharing request - limited to granted capabilities
    case guest = "guest"

    var displayName: String {
        switch self {
        case .host: return "Host"
        case .guest: return "Guest"
        }
    }

    /// What memories this session type can access
    var memoryAccessScope: MemoryAccessScope {
        switch self {
        case .host: return .full
        case .guest: return .egoicOnly
        }
    }

    /// Whether this session can modify memories
    var canModifyMemories: Bool {
        switch self {
        case .host: return true
        case .guest: return false
        }
    }

    /// Whether this session can negotiate covenants
    var canNegotiateCovenants: Bool {
        switch self {
        case .host: return true
        case .guest: return false
        }
    }
}

/// Scope of memory access for a session
enum MemoryAccessScope: String, Codable, CaseIterable {
    /// Full access to all memories (allocentric + egoic)
    case full = "full"
    /// Only learned patterns and solutions (egoic memories)
    case egoicOnly = "egoic"
    /// No memory access
    case none = "none"

    var displayName: String {
        switch self {
        case .full: return "Full Access"
        case .egoicOnly: return "Learned Patterns Only"
        case .none: return "No Access"
        }
    }

    var description: String {
        switch self {
        case .full:
            return "Access to all memories including personal information"
        case .egoicOnly:
            return "Access to learned patterns and solutions, personal information is protected"
        case .none:
            return "No access to memories"
        }
    }
}

// MARK: - JSON-RPC Messages

/// Incoming request from VS Code (or outgoing request to VS Code)
struct BridgeRequest: Codable {
    let jsonrpc: String
    let id: String
    let method: String
    let params: AnyCodable?

    init(id: String = UUID().uuidString, method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// Response to a request
struct BridgeResponse: Codable {
    let jsonrpc: String
    let id: String
    let result: AnyCodable?
    let error: BridgeError?

    init(id: String, result: AnyCodable? = nil, error: BridgeError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }

    static func success(id: String, result: AnyCodable) -> BridgeResponse {
        BridgeResponse(id: id, result: result, error: nil)
    }

    static func failure(id: String, error: BridgeError) -> BridgeResponse {
        BridgeResponse(id: id, result: nil, error: error)
    }
}

/// Notification (no response expected)
struct BridgeNotification: Codable {
    let jsonrpc: String
    let method: String
    let params: AnyCodable?

    init(method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

// MARK: - Error Types

struct BridgeError: Codable, Error {
    let code: Int
    let message: String
    let data: AnyCodable?

    init(code: BridgeErrorCode, message: String, data: AnyCodable? = nil) {
        self.code = code.rawValue
        self.message = message
        self.data = data
    }

    init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

enum BridgeErrorCode: Int {
    // Standard JSON-RPC errors
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603

    // Bridge-specific errors
    case notConnected = -1000
    case sessionExpired = -1001
    case approvalDenied = -2000
    case approvalTimeout = -2001
    case pathBlocked = -3000
    case commandBlocked = -3001
    case fileNotFound = -4000
    case fileReadError = -4001
    case fileWriteError = -4002
    case terminalError = -5000
    case timeout = -6000
}

// MARK: - Session

/// Represents a connected VS Code workspace or guest session
struct BridgeSession: Codable, Identifiable, Equatable {
    let id: UUID
    let workspaceId: String          // SHA256 hash of workspace root path
    let workspaceName: String        // Human-readable name
    let workspaceRoot: String        // Full path to workspace
    let connectedAt: Date
    var lastActivity: Date
    let capabilities: [BridgeCapability]
    let extensionVersion: String

    // Guest sharing fields
    let sessionType: SessionType
    let invitationId: String?        // Links to GuestInvitation if this is a guest session
    let guestCapabilities: GuestCapabilities?  // Granted capabilities for guest sessions

    /// Initialize a host session (default, for VS Code connections)
    init(
        id: UUID = UUID(),
        workspaceId: String,
        workspaceName: String,
        workspaceRoot: String,
        capabilities: [BridgeCapability] = BridgeCapability.allCases,
        extensionVersion: String = "0.1.0"
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.workspaceRoot = workspaceRoot
        self.connectedAt = Date()
        self.lastActivity = Date()
        self.capabilities = capabilities
        self.extensionVersion = extensionVersion
        self.sessionType = .host
        self.invitationId = nil
        self.guestCapabilities = nil
    }

    /// Initialize a guest session (for friends with invitations)
    init(
        id: UUID = UUID(),
        guestName: String,
        invitationId: String,
        guestCapabilities: GuestCapabilities,
        extensionVersion: String = "0.1.0"
    ) {
        self.id = id
        self.workspaceId = "guest-\(invitationId)"
        self.workspaceName = guestName
        self.workspaceRoot = ""
        self.connectedAt = Date()
        self.lastActivity = Date()
        self.capabilities = [.workspaceInfo]  // Limited capabilities for guests
        self.extensionVersion = extensionVersion
        self.sessionType = .guest
        self.invitationId = invitationId
        self.guestCapabilities = guestCapabilities
    }

    var displayName: String {
        if sessionType == .guest {
            return workspaceName.isEmpty ? "Guest" : workspaceName
        }
        return workspaceName.isEmpty ? "VS Code" : workspaceName
    }

    var isGuest: Bool {
        sessionType == .guest
    }

    /// The effective memory access scope for this session
    var effectiveMemoryScope: MemoryAccessScope {
        if let guestCaps = guestCapabilities {
            // Use the guest's granted scope
            return guestCaps.canChatWithContext || guestCaps.canQueryMemories ? .egoicOnly : .none
        }
        return sessionType.memoryAccessScope
    }
}

// MARK: - Guest Capabilities

/// Capabilities granted to a guest session after joint host + AI consent
struct GuestCapabilities: Codable, Equatable {
    /// Can have full AI conversations with memory context injected
    let canChatWithContext: Bool
    /// Can directly search/query host's memories
    let canQueryMemories: Bool
    /// Maximum memories returned per query
    let maxMemoriesPerQuery: Int
    /// Maximum queries allowed per hour
    let maxQueriesPerHour: Int
    /// Which memory types can be accessed (should only include .egoic for guests)
    let allowedMemoryTypes: [String]  // Using String to avoid circular dependency with Memory module
    /// Specific topics allowed (nil = all topics)
    let allowedTopics: [String]?
    /// Tags that should be excluded from shared memories
    let excludedTags: [String]

    /// Read-only access - can only search memories, no conversations
    static var readOnly: GuestCapabilities {
        GuestCapabilities(
            canChatWithContext: false,
            canQueryMemories: true,
            maxMemoriesPerQuery: 3,
            maxQueriesPerHour: 10,
            allowedMemoryTypes: ["egoic"],
            allowedTopics: nil,
            excludedTags: ["private", "personal", "health", "financial", "sensitive"]
        )
    }

    /// Standard access - can chat with AI and search memories
    static var standard: GuestCapabilities {
        GuestCapabilities(
            canChatWithContext: true,
            canQueryMemories: true,
            maxMemoriesPerQuery: 5,
            maxQueriesPerHour: 20,
            allowedMemoryTypes: ["egoic"],
            allowedTopics: nil,
            excludedTags: ["private", "personal", "health", "financial", "sensitive"]
        )
    }

    /// Full access - maximum capabilities for trusted friends
    static var full: GuestCapabilities {
        GuestCapabilities(
            canChatWithContext: true,
            canQueryMemories: true,
            maxMemoriesPerQuery: 10,
            maxQueriesPerHour: 50,
            allowedMemoryTypes: ["egoic"],
            allowedTopics: nil,
            excludedTags: ["private", "personal", "health", "financial"]
        )
    }
}

/// Capabilities the VS Code extension supports
enum BridgeCapability: String, Codable, CaseIterable {
    case readFile = "file/read"
    case writeFile = "file/write"
    case listFiles = "file/list"
    case runTerminal = "terminal/run"
    case workspaceInfo = "workspace/info"
}

// MARK: - Handshake Messages

/// Hello message sent by the connecting party during handshake
/// In Local Mode: VS Code sends this to Axon
/// In Remote Mode: Axon sends this to VS Code
/// In Guest Mode: Guest connects with invitation token
struct BridgeHello: Codable {
    // Mode and role information (new for Remote Mode support)
    let mode: BridgeMode?           // nil defaults to .local for backward compatibility
    let role: BridgeRole?           // nil inferred from mode

    // Workspace info (always present when VS Code sends, optional when Axon sends)
    let workspaceId: String?
    let workspaceName: String?
    let workspaceRoot: String?
    let capabilities: [String]?
    let extensionVersion: String?
    let vscodeVersion: String?

    // Axon info (present when Axon sends in Remote Mode)
    let axonVersion: String?
    let deviceName: String?         // e.g., "Tom's iPhone"

    // Security
    let pairingToken: String?

    // Guest sharing fields (present when guest connects with invitation)
    let sessionType: SessionType?   // nil defaults to .host for backward compatibility
    let invitationToken: String?    // Secure token from invitation link
    let guestName: String?          // Display name of the guest

    /// Create hello from VS Code (Local Mode - existing behavior)
    static func fromVSCode(
        workspaceId: String,
        workspaceName: String,
        workspaceRoot: String,
        capabilities: [String],
        extensionVersion: String,
        vscodeVersion: String?,
        pairingToken: String?
    ) -> BridgeHello {
        BridgeHello(
            mode: .local,
            role: .puppet,
            workspaceId: workspaceId,
            workspaceName: workspaceName,
            workspaceRoot: workspaceRoot,
            capabilities: capabilities,
            extensionVersion: extensionVersion,
            vscodeVersion: vscodeVersion,
            axonVersion: nil,
            deviceName: nil,
            pairingToken: pairingToken,
            sessionType: .host,
            invitationToken: nil,
            guestName: nil
        )
    }

    /// Create hello from Axon (Remote Mode - new)
    static func fromAxon(
        axonVersion: String,
        deviceName: String?,
        pairingToken: String?
    ) -> BridgeHello {
        BridgeHello(
            mode: .remote,
            role: .puppeteer,
            workspaceId: nil,
            workspaceName: nil,
            workspaceRoot: nil,
            capabilities: nil,
            extensionVersion: nil,
            vscodeVersion: nil,
            axonVersion: axonVersion,
            deviceName: deviceName,
            pairingToken: pairingToken,
            sessionType: .host,
            invitationToken: nil,
            guestName: nil
        )
    }

    /// Create hello from a guest connecting with an invitation token
    static func fromGuest(
        invitationToken: String,
        guestName: String,
        deviceName: String?,
        axonVersion: String?
    ) -> BridgeHello {
        BridgeHello(
            mode: .remote,
            role: .puppet,  // Guest is controlled by host's AI
            workspaceId: nil,
            workspaceName: nil,
            workspaceRoot: nil,
            capabilities: nil,
            extensionVersion: nil,
            vscodeVersion: nil,
            axonVersion: axonVersion,
            deviceName: deviceName,
            pairingToken: nil,
            sessionType: .guest,
            invitationToken: invitationToken,
            guestName: guestName
        )
    }

    /// Effective mode (defaults to .local for backward compatibility)
    var effectiveMode: BridgeMode {
        mode ?? .local
    }

    /// Effective role (inferred from mode if not specified)
    var effectiveRole: BridgeRole {
        if let role = role { return role }
        return effectiveMode == .local ? .puppet : .puppeteer
    }

    /// Effective session type (defaults to .host for backward compatibility)
    var effectiveSessionType: SessionType {
        sessionType ?? .host
    }

    /// Whether this is a guest connection
    var isGuestConnection: Bool {
        effectiveSessionType == .guest && invitationToken != nil
    }
}

/// Welcome response sent by the server during handshake
/// In Local Mode: Axon sends this to VS Code
/// In Remote Mode: VS Code sends this to Axon
struct BridgeWelcome: Codable {
    let sessionId: String
    let mode: BridgeMode?           // Echo back the mode for confirmation

    // Server info (always present)
    let axonVersion: String?        // Present in Local Mode (Axon is server)
    let extensionVersion: String?   // Present in Remote Mode (VS Code is server)

    // Workspace info (present in Remote Mode response from VS Code)
    let workspaceId: String?
    let workspaceName: String?
    let workspaceRoot: String?
    let capabilities: [String]?

    let supportedMethods: [String]

    /// Create welcome from Axon (Local Mode - existing behavior)
    static func fromAxon(
        sessionId: String,
        axonVersion: String,
        supportedMethods: [String]
    ) -> BridgeWelcome {
        BridgeWelcome(
            sessionId: sessionId,
            mode: .local,
            axonVersion: axonVersion,
            extensionVersion: nil,
            workspaceId: nil,
            workspaceName: nil,
            workspaceRoot: nil,
            capabilities: nil,
            supportedMethods: supportedMethods
        )
    }

    /// Create welcome from VS Code (Remote Mode - new)
    static func fromVSCode(
        sessionId: String,
        extensionVersion: String,
        workspaceId: String,
        workspaceName: String,
        workspaceRoot: String,
        capabilities: [String],
        supportedMethods: [String]
    ) -> BridgeWelcome {
        BridgeWelcome(
            sessionId: sessionId,
            mode: .remote,
            axonVersion: nil,
            extensionVersion: extensionVersion,
            workspaceId: workspaceId,
            workspaceName: workspaceName,
            workspaceRoot: workspaceRoot,
            capabilities: capabilities,
            supportedMethods: supportedMethods
        )
    }

    /// Effective mode (defaults to .local for backward compatibility)
    var effectiveMode: BridgeMode {
        mode ?? .local
    }
}

// MARK: - File Operation Types

struct FileReadParams: Codable {
    let path: String
    let encoding: String?
    let maxSize: Int?

    init(path: String, encoding: String? = "utf-8", maxSize: Int? = nil) {
        self.path = path
        self.encoding = encoding
        self.maxSize = maxSize
    }
}

struct FileReadResult: Codable {
    let content: String
    let size: Int
    let encoding: String
    let path: String
}

struct FileWriteParams: Codable {
    let path: String
    let content: String
    let createIfMissing: Bool?
    let encoding: String?

    init(path: String, content: String, createIfMissing: Bool? = true, encoding: String? = "utf-8") {
        self.path = path
        self.content = content
        self.createIfMissing = createIfMissing
        self.encoding = encoding
    }
}

struct FileWriteResult: Codable {
    let success: Bool
    let bytesWritten: Int
    let created: Bool
    let path: String
}

struct FileListParams: Codable {
    let path: String
    let recursive: Bool?
    let maxDepth: Int?
    let includeHidden: Bool?

    init(path: String, recursive: Bool? = false, maxDepth: Int? = 1, includeHidden: Bool? = false) {
        self.path = path
        self.recursive = recursive
        self.maxDepth = maxDepth
        self.includeHidden = includeHidden
    }
}

struct FileListResult: Codable {
    let path: String
    let files: [FileInfo]
}

struct FileInfo: Codable {
    let name: String
    let path: String
    let type: FileType
    let size: Int?
    let modified: Date?

    enum FileType: String, Codable {
        case file
        case directory
        case symlink
        case unknown
    }
}

// MARK: - Terminal Operation Types

struct TerminalRunParams: Codable {
    let command: String
    let args: [String]?
    let cwd: String?
    let env: [String: String]?
    let timeout: Int?           // milliseconds, default 60000

    init(command: String, args: [String]? = nil, cwd: String? = nil, env: [String: String]? = nil, timeout: Int? = 60000) {
        self.command = command
        self.args = args
        self.cwd = cwd
        self.env = env
        self.timeout = timeout
    }
}

struct TerminalRunResult: Codable {
    let output: String
    let stderr: String?
    let exitCode: Int
    let duration: Int           // milliseconds
    let timedOut: Bool
}

// MARK: - Workspace Operation Types

struct WorkspaceInfoResult: Codable {
    let name: String
    let rootPath: String
    let folders: [WorkspaceFolder]
    let openFiles: [String]
}

struct WorkspaceFolder: Codable {
    let name: String
    let path: String
}

// MARK: - Axon Native Control Types

struct AxonDiscoverActionsParams: Codable {
    let filter: String?
    let platform: String?
    let view: String?
}

struct AxonDiscoverActionsResult: Codable {
    let actions: [AgentActionDescriptor]
}

struct AxonInvokeActionParams: Codable {
    let id: String
    let params: [String: AnyCodable]?
    let context: AgentActionContext?
}

struct AxonInvokeActionResult: Codable {
    let result: AgentActionResult
}

struct AxonGetStateResult: Codable {
    let state: AgentActionStateSnapshot
}

// MARK: - Pending Request Tracking

/// Tracks an outgoing request waiting for a response
struct PendingBridgeRequest {
    let id: String
    let method: String
    let sentAt: Date
    let continuation: CheckedContinuation<BridgeResponse, Error>
    let timeout: TimeInterval

    var isExpired: Bool {
        Date().timeIntervalSince(sentAt) > timeout
    }
}

// MARK: - Message Encoding/Decoding

enum BridgeMessage {
    case request(BridgeRequest)
    case response(BridgeResponse)
    case notification(BridgeNotification)

    /// Decode a raw JSON message into the appropriate type
    static func decode(from data: Data) throws -> BridgeMessage {
        // First, decode as generic JSON to determine message type
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError(code: .parseError, message: "Invalid JSON")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Check if it's a response (has result or error, no method)
        if json["result"] != nil || json["error"] != nil {
            let response = try decoder.decode(BridgeResponse.self, from: data)
            return .response(response)
        }

        // Check if it's a request or notification (has method)
        if json["method"] != nil {
            if json["id"] != nil {
                let request = try decoder.decode(BridgeRequest.self, from: data)
                return .request(request)
            } else {
                let notification = try decoder.decode(BridgeNotification.self, from: data)
                return .notification(notification)
            }
        }

        throw BridgeError(code: .invalidRequest, message: "Unknown message type")
    }

    /// Encode a message to JSON data
    static func encode<T: Encodable>(_ message: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(message)
    }
}

// MARK: - Bridge Methods

/// All supported bridge methods
enum BridgeMethod: String, CaseIterable {
    // Handshake
    case hello = "hello"

    // Setup / pairing info (Axon → clients)
    case getPairingInfo = "bridge/getPairingInfo"

    // Chat mirroring (read-only MVP)
    case chatListConversations = "chat/listConversations"
    case chatGetMessages = "chat/getMessages"

    // File operations
    case fileRead = "file/read"
    case fileWrite = "file/write"
    case fileList = "file/list"

    // Terminal operations
    case terminalRun = "terminal/run"

    // Workspace operations
    case workspaceInfo = "workspace/info"

    // Guest sharing operations
    case guestQueryMemories = "guest/queryMemories"
    case guestGetContext = "guest/getContext"
    case guestChatWithContext = "guest/chatWithContext"
    case guestDisconnect = "guest/disconnect"

    // Mac System operations (for iOS → Mac remote control)
    case systemInfo = "system/info"
    case systemProcesses = "system/processes"
    case systemDiskUsage = "system/disk_usage"
    case clipboardRead = "clipboard/read"
    case clipboardWrite = "clipboard/write"
    case notificationSend = "notification/send"
    case spotlightSearch = "spotlight/search"
    case fileFind = "file/find"
    case fileMetadata = "file/metadata"
    case appList = "app/list"
    case appLaunch = "app/launch"
    case screenshot = "screenshot/capture"
    case networkInfo = "network/info"
    case networkPing = "network/ping"
    case shellExecute = "shell/execute"

    // Axon native action control
    case axonDiscoverActions = "axon/discoverActions"
    case axonInvokeAction = "axon/invokeAction"
    case axonGetState = "axon/getState"

    /// Whether this method requires user approval
    var requiresApproval: Bool {
        switch self {
        case .fileWrite, .terminalRun,
             .clipboardWrite, .appLaunch, .shellExecute:
            return true
        case .hello,
             .getPairingInfo,
             .chatListConversations,
             .chatGetMessages,
             .fileRead,
             .fileList,
             .workspaceInfo,
             .guestQueryMemories,
             .guestGetContext,
             .guestChatWithContext,
             .guestDisconnect,
             .systemInfo,
             .systemProcesses,
             .systemDiskUsage,
             .clipboardRead,
             .notificationSend,
             .spotlightSearch,
             .fileFind,
             .fileMetadata,
             .appList,
             .screenshot,
             .networkInfo,
             .networkPing,
             .axonDiscoverActions,
             .axonInvokeAction,
             .axonGetState:
            return false
        }
    }

    /// Whether this method is available to guest sessions
    var availableToGuests: Bool {
        switch self {
        case .guestQueryMemories, .guestGetContext, .guestChatWithContext, .guestDisconnect, .hello:
            return true
        case .getPairingInfo, .chatListConversations, .chatGetMessages,
             .fileRead, .fileWrite, .fileList, .terminalRun, .workspaceInfo,
             .systemInfo, .systemProcesses, .systemDiskUsage,
             .clipboardRead, .clipboardWrite, .notificationSend,
             .spotlightSearch, .fileFind, .fileMetadata,
             .appList, .appLaunch, .screenshot,
             .networkInfo, .networkPing, .shellExecute,
             .axonDiscoverActions, .axonInvokeAction, .axonGetState:
            return false
        }
    }

    /// Human-readable description of what this method does
    var description: String {
        switch self {
        case .hello:
            return "Initialize connection"
        case .getPairingInfo:
            return "Get Axon pairing / hotspot connection info"
        case .chatListConversations:
            return "List conversations"
        case .chatGetMessages:
            return "Get messages for a conversation"
        case .fileRead:
            return "Read file contents"
        case .fileWrite:
            return "Write or create file"
        case .fileList:
            return "List directory contents"
        case .terminalRun:
            return "Execute terminal command"
        case .workspaceInfo:
            return "Get workspace information"
        case .guestQueryMemories:
            return "Query host's learned patterns"
        case .guestGetContext:
            return "Get context for a topic"
        case .guestChatWithContext:
            return "Chat with AI using host's learned patterns"
        case .guestDisconnect:
            return "End guest session"
        // Mac System operations
        case .systemInfo:
            return "Get Mac system information (CPU, memory, uptime)"
        case .systemProcesses:
            return "List running processes"
        case .systemDiskUsage:
            return "Get disk usage statistics"
        case .clipboardRead:
            return "Read clipboard content"
        case .clipboardWrite:
            return "Write to clipboard"
        case .notificationSend:
            return "Send a system notification"
        case .spotlightSearch:
            return "Search files using Spotlight"
        case .fileFind:
            return "Find files by pattern"
        case .fileMetadata:
            return "Get file metadata"
        case .appList:
            return "List running applications"
        case .appLaunch:
            return "Launch an application"
        case .screenshot:
            return "Capture a screenshot"
        case .networkInfo:
            return "Get network interface information"
        case .networkPing:
            return "Ping a host"
        case .shellExecute:
            return "Execute a shell command"
        case .axonDiscoverActions:
            return "Discover Axon native control actions"
        case .axonInvokeAction:
            return "Invoke an Axon native control action"
        case .axonGetState:
            return "Get Axon native app state"
        }
    }

    /// Methods available for guest sessions
    static var guestMethods: [BridgeMethod] {
        allCases.filter { $0.availableToGuests }
    }
}
