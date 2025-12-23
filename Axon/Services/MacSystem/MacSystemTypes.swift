//
//  MacSystemTypes.swift
//  Axon
//
//  Request and response types for Mac system operations.
//  These types are used for both local execution and bridge communication.
//

import Foundation

// MARK: - System Info

struct SystemInfoParams: Codable {
    // No parameters needed
}

struct SystemInfoResult: Codable {
    let hostname: String
    let osVersion: String
    let osBuild: String
    let cpuModel: String
    let cpuCores: Int
    let cpuCoresLogical: Int
    let memoryTotalGB: Double
    let memoryUsedGB: Double
    let memoryFreeGB: Double
    let memoryUsagePercent: Double
    let uptimeSeconds: Int
    let uptimeFormatted: String
    let bootTime: Date
}

// MARK: - Running Processes

struct ProcessListParams: Codable {
    let limit: Int?

    init(limit: Int? = 20) {
        self.limit = limit
    }
}

struct ProcessListResult: Codable {
    let processes: [MacProcessInfo]
    let totalCount: Int
}

struct MacProcessInfo: Codable {
    let pid: Int
    let name: String
    let cpuPercent: Double
    let memoryPercent: Double
    let memoryMB: Double
    let status: String
    let user: String?
}

// MARK: - Disk Usage

struct DiskUsageParams: Codable {
    let path: String

    init(path: String = "/") {
        self.path = path
    }
}

struct DiskUsageResult: Codable {
    let path: String
    let totalGB: Double
    let usedGB: Double
    let freeGB: Double
    let usagePercent: Double
    let fileSystem: String?
}

// MARK: - Clipboard

struct ClipboardReadParams: Codable {
    // No parameters needed
}

struct ClipboardReadResult: Codable {
    let content: String?
    let hasContent: Bool
    let contentType: String  // "text", "image", "file", "unknown"
}

struct ClipboardWriteParams: Codable {
    let content: String
}

struct ClipboardWriteResult: Codable {
    let success: Bool
}

// MARK: - Notifications

struct NotificationSendParams: Codable {
    let title: String
    let message: String
    let subtitle: String?
    let soundName: String?

    init(title: String, message: String, subtitle: String? = nil, soundName: String? = nil) {
        self.title = title
        self.message = message
        self.subtitle = subtitle
        self.soundName = soundName
    }
}

struct NotificationSendResult: Codable {
    let success: Bool
    let notificationId: String?
}

// MARK: - Spotlight Search

struct SpotlightSearchParams: Codable {
    let query: String
    let limit: Int?
    let contentType: String?  // e.g., "public.text", "public.image"

    init(query: String, limit: Int? = 20, contentType: String? = nil) {
        self.query = query
        self.limit = limit
        self.contentType = contentType
    }
}

struct SpotlightSearchResult: Codable {
    let results: [SpotlightItem]
    let totalFound: Int
    let searchTime: Double  // seconds
}

struct SpotlightItem: Codable {
    let path: String
    let name: String
    let displayName: String?
    let contentType: String?
    let sizeBytes: Int?
    let modifiedDate: Date?
    let createdDate: Date?
}

// MARK: - File Find

struct FileFindParams: Codable {
    let pattern: String
    let directory: String?
    let maxDepth: Int?

    init(pattern: String, directory: String? = "~", maxDepth: Int? = 3) {
        self.pattern = pattern
        self.directory = directory
        self.maxDepth = maxDepth
    }
}

struct FileFindResult: Codable {
    let files: [FoundFile]
    let searchDirectory: String
    let totalFound: Int
}

struct FoundFile: Codable {
    let path: String
    let name: String
    let sizeBytes: Int?
    let isDirectory: Bool
}

// MARK: - File Metadata

struct FileMetadataParams: Codable {
    let path: String
}

struct FileMetadataResult: Codable {
    let path: String
    let name: String
    let exists: Bool
    let isDirectory: Bool
    let isSymlink: Bool
    let sizeBytes: Int?
    let permissions: String?
    let owner: String?
    let group: String?
    let createdDate: Date?
    let modifiedDate: Date?
    let accessedDate: Date?
    let contentType: String?
}

// MARK: - Running Applications

struct AppListParams: Codable {
    // No parameters needed
}

struct AppListResult: Codable {
    let applications: [RunningApp]
}

struct RunningApp: Codable {
    let name: String
    let bundleIdentifier: String?
    let pid: Int
    let isActive: Bool
    let isHidden: Bool
    let icon: String?  // Base64 encoded PNG for small icon
}

// MARK: - App Launch

struct AppLaunchParams: Codable {
    let appName: String
    let arguments: [String]?

    init(appName: String, arguments: [String]? = nil) {
        self.appName = appName
        self.arguments = arguments
    }
}

struct AppLaunchResult: Codable {
    let success: Bool
    let pid: Int?
    let bundleIdentifier: String?
    let errorMessage: String?
}

// MARK: - Screenshot

struct ScreenshotParams: Codable {
    let path: String?  // If nil, returns base64 data
    let display: Int?  // Display index, nil for main display
    let includeWindows: Bool?

    init(path: String? = nil, display: Int? = nil, includeWindows: Bool? = true) {
        self.path = path
        self.display = display
        self.includeWindows = includeWindows
    }
}

struct ScreenshotResult: Codable {
    let success: Bool
    let path: String?
    let imageData: String?  // Base64 encoded PNG if no path specified
    let width: Int?
    let height: Int?
    let errorMessage: String?
}

// MARK: - Network Info

struct NetworkInfoParams: Codable {
    // No parameters needed
}

struct NetworkInfoResult: Codable {
    let interfaces: [NetworkInterface]
    let wifiSSID: String?
    let wifiBSSID: String?
    let externalIP: String?
}

struct NetworkInterface: Codable {
    let name: String
    let displayName: String?
    let ipv4Address: String?
    let ipv6Address: String?
    let macAddress: String?
    let isUp: Bool
    let isLoopback: Bool
    let mtu: Int?
    let speed: String?  // e.g., "1 Gbps"
}

// MARK: - Network Ping

struct PingParams: Codable {
    let host: String
    let count: Int?
    let timeout: Int?  // milliseconds

    init(host: String, count: Int? = 4, timeout: Int? = 5000) {
        self.host = host
        self.count = count
        self.timeout = timeout
    }
}

struct PingResult: Codable {
    let success: Bool
    let host: String
    let packetsTransmitted: Int
    let packetsReceived: Int
    let packetLoss: Double  // percentage
    let minTime: Double?    // ms
    let avgTime: Double?    // ms
    let maxTime: Double?    // ms
    let errorMessage: String?
}

// MARK: - Shell Execute

struct ShellExecuteParams: Codable {
    let command: String
    let timeout: Int?  // milliseconds, default 30000
    let workingDirectory: String?

    init(command: String, timeout: Int? = 30000, workingDirectory: String? = nil) {
        self.command = command
        self.timeout = timeout
        self.workingDirectory = workingDirectory
    }
}

struct ShellExecuteResult: Codable {
    let success: Bool
    let stdout: String
    let stderr: String
    let exitCode: Int
    let timedOut: Bool
    let executionTime: Double  // seconds
    let blocked: Bool  // true if command was blocked for security
    let blockedReason: String?
}

// MARK: - Errors

enum MacSystemError: Error, LocalizedError {
    case notAvailable(String)
    case requiresBridge(String)
    case operationFailed(String)
    case commandBlocked(String)
    case timeout
    case permissionDenied(String)
    case missingBridgeMethod
    case bridgeNotConnected

    var errorDescription: String? {
        switch self {
        case .notAvailable(let reason):
            return "Operation not available: \(reason)"
        case .requiresBridge(let operation):
            return "\(operation) requires connection to a Mac via bridge"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        case .commandBlocked(let command):
            return "Command blocked for security: \(command)"
        case .timeout:
            return "Operation timed out"
        case .permissionDenied(let resource):
            return "Permission denied: \(resource)"
        case .missingBridgeMethod:
            return "Tool manifest missing bridgeMethod configuration"
        case .bridgeNotConnected:
            return "Not connected to Mac via bridge"
        }
    }
}
