//
//  TerminalSessionTypes.swift
//  Axon
//
//  Shared types for the bottom terminal drawer and bridge PTY protocol.
//

import Foundation

enum TerminalWorkingDirectorySource: String, Codable, Equatable {
    case bridgeWorkspace
    case configuredDirectory
    case home
}

struct TerminalWorkingDirectoryResolution: Equatable {
    let path: String
    let source: TerminalWorkingDirectorySource
}

enum TerminalWorkingDirectoryResolver {
    static func resolve(
        settings: BridgeSettings,
        connectedSession: BridgeSession?,
        homeDirectory: String = NSHomeDirectory()
    ) -> TerminalWorkingDirectoryResolution {
        if settings.preferBridgeWorkspaceForTerminal,
           let root = connectedSession?.workspaceRoot,
           !root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TerminalWorkingDirectoryResolution(path: root, source: .bridgeWorkspace)
        }

        let configured = settings.terminalDefaultDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return TerminalWorkingDirectoryResolution(
                path: NSString(string: configured).expandingTildeInPath,
                source: .configuredDirectory
            )
        }

        return TerminalWorkingDirectoryResolution(path: homeDirectory, source: .home)
    }
}

enum TerminalSessionError: Error, LocalizedError, Equatable {
    case bridgeNotConnected
    case startFailed(String)
    case sessionNotStarted

    var errorDescription: String? {
        switch self {
        case .bridgeNotConnected:
            return "VS Code bridge not connected"
        case .startFailed(let message):
            return message
        case .sessionNotStarted:
            return "Terminal session not started"
        }
    }
}

struct TerminalSessionStartParams: Codable, Equatable {
    let cwd: String
    let cols: Int
    let rows: Int
    let shell: String?
}

struct TerminalSessionStartResult: Codable, Equatable {
    let sessionId: String
    let cwd: String
    let shell: String
}

struct TerminalSessionInputParams: Codable, Equatable {
    let sessionId: String
    let data: String
}

struct TerminalSessionResizeParams: Codable, Equatable {
    let sessionId: String
    let cols: Int
    let rows: Int
}

struct TerminalSessionCloseParams: Codable, Equatable {
    let sessionId: String
}

struct TerminalSessionOutputNotification: Codable, Equatable {
    let sessionId: String
    let data: String
}

struct TerminalSessionExitedNotification: Codable, Equatable {
    let sessionId: String
    let exitCode: Int?
}

extension Notification.Name {
    static let terminalSessionOutput = Notification.Name("TerminalSessionOutput")
    static let terminalSessionExited = Notification.Name("TerminalSessionExited")
}

enum TerminalBridgeMethod {
    static let sessionStart = "terminal/sessionStart"
    static let sessionInput = "terminal/sessionInput"
    static let sessionResize = "terminal/sessionResize"
    static let sessionClose = "terminal/sessionClose"
    static let output = "terminal/output"
    static let exited = "terminal/exited"
}
