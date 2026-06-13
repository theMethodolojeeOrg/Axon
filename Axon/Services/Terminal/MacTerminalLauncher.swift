//
//  MacTerminalLauncher.swift
//  Axon
//
//  Opens the user's real macOS Terminal app at Axon's resolved terminal folder.
//

import Foundation

#if os(macOS)
import AppKit

protocol TerminalAppLaunching {
    func openTerminal(at directoryURL: URL) async throws
}

struct MacTerminalLaunchRequest: Equatable {
    let directoryURL: URL
    let source: TerminalWorkingDirectorySource
}

enum MacTerminalLauncherError: Error, LocalizedError, Equatable {
    case terminalAppNotFound
    case invalidWorkingDirectory(String)
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .terminalAppNotFound:
            return "Terminal.app could not be found on this Mac."
        case .invalidWorkingDirectory(let path):
            return "Terminal working directory does not exist or is not a folder: \(path)"
        case .openFailed(let message):
            return "Failed to open Terminal.app: \(message)"
        }
    }
}

enum MacTerminalLaunchResolver {
    nonisolated static func resolve(
        settings: BridgeSettings,
        connectedSession: BridgeSession?,
        homeDirectory: String = NSHomeDirectory(),
        isDirectory: (String) -> Bool = MacTerminalLaunchResolver.defaultIsDirectory
    ) throws -> MacTerminalLaunchRequest {
        let resolution = TerminalWorkingDirectoryResolver.resolve(
            settings: settings,
            connectedSession: connectedSession,
            homeDirectory: homeDirectory
        )
        let path = NSString(string: resolution.path).expandingTildeInPath

        guard isDirectory(path) else {
            throw MacTerminalLauncherError.invalidWorkingDirectory(path)
        }

        return MacTerminalLaunchRequest(
            directoryURL: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL,
            source: resolution.source
        )
    }

    nonisolated private static func defaultIsDirectory(_ path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

final class MacTerminalLauncher: TerminalAppLaunching {
    private let workspace: NSWorkspace
    private let terminalBundleIdentifier = "com.apple.Terminal"

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func openTerminal(at directoryURL: URL) async throws {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MacTerminalLauncherError.invalidWorkingDirectory(directoryURL.path)
        }

        guard let terminalURL = workspace.urlForApplication(withBundleIdentifier: terminalBundleIdentifier) else {
            throw MacTerminalLauncherError.terminalAppNotFound
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.open(
                [directoryURL],
                withApplicationAt: terminalURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: MacTerminalLauncherError.openFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
