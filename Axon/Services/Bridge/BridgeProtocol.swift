//
//  BridgeProtocol.swift
//  Axon
//
//  JSON-RPC 2.0 style protocol for communication between Axon and VS Code.
//  Axon acts as the "puppeteer" (server), VS Code as the "puppet" (client).
//

import Foundation

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

/// Represents a connected VS Code workspace
struct BridgeSession: Codable, Identifiable, Equatable {
    let id: UUID
    let workspaceId: String          // SHA256 hash of workspace root path
    let workspaceName: String        // Human-readable name
    let workspaceRoot: String        // Full path to workspace
    let connectedAt: Date
    var lastActivity: Date
    let capabilities: [BridgeCapability]
    let extensionVersion: String

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
    }

    var displayName: String {
        workspaceName.isEmpty ? "VS Code" : workspaceName
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

/// Initial hello message from VS Code
struct BridgeHello: Codable {
    let workspaceId: String
    let workspaceName: String
    let workspaceRoot: String
    let capabilities: [String]
    let extensionVersion: String
    let vscodeVersion: String?
}

/// Welcome response from Axon
struct BridgeWelcome: Codable {
    let sessionId: String
    let axonVersion: String
    let supportedMethods: [String]
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

    // File operations
    case fileRead = "file/read"
    case fileWrite = "file/write"
    case fileList = "file/list"

    // Terminal operations
    case terminalRun = "terminal/run"

    // Workspace operations
    case workspaceInfo = "workspace/info"

    /// Whether this method requires user approval
    var requiresApproval: Bool {
        switch self {
        case .fileWrite, .terminalRun:
            return true
        case .hello, .fileRead, .fileList, .workspaceInfo:
            return false
        }
    }

    /// Human-readable description of what this method does
    var description: String {
        switch self {
        case .hello:
            return "Initialize connection"
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
        }
    }
}
