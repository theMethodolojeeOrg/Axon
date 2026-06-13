import XCTest
@testable import Axon

@MainActor
final class TerminalSessionTests: XCTestCase {
    func testWorkingDirectoryPrefersConnectedWorkspaceWhenEnabled() {
        let session = BridgeSession(
            workspaceId: "workspace-1",
            workspaceName: "Axon",
            workspaceRoot: "/Users/tom/Projects/Axon",
            capabilities: [],
            extensionVersion: "test"
        )
        var settings = BridgeSettings()
        settings.preferBridgeWorkspaceForTerminal = true
        settings.terminalDefaultDirectory = "/Users/tom/Fallback"

        let resolved = TerminalWorkingDirectoryResolver.resolve(
            settings: settings,
            connectedSession: session,
            homeDirectory: "/Users/tom"
        )

        XCTAssertEqual(resolved.path, "/Users/tom/Projects/Axon")
        XCTAssertEqual(resolved.source, .bridgeWorkspace)
    }

    func testWorkingDirectoryUsesConfiguredFolderWhenNoWorkspace() {
        var settings = BridgeSettings()
        settings.preferBridgeWorkspaceForTerminal = true
        settings.terminalDefaultDirectory = "/Users/tom/Fallback"

        let resolved = TerminalWorkingDirectoryResolver.resolve(
            settings: settings,
            connectedSession: nil,
            homeDirectory: "/Users/tom"
        )

        XCTAssertEqual(resolved.path, "/Users/tom/Fallback")
        XCTAssertEqual(resolved.source, .configuredDirectory)
    }

    func testWorkingDirectoryFallsBackToHomeDirectory() {
        let resolved = TerminalWorkingDirectoryResolver.resolve(
            settings: BridgeSettings(),
            connectedSession: nil,
            homeDirectory: "/Users/tom"
        )

        XCTAssertEqual(resolved.path, "/Users/tom")
        XCTAssertEqual(resolved.source, .home)
    }

    #if os(macOS)
    func testMacTerminalLaunchPrefersConnectedWorkspaceWhenEnabled() throws {
        let session = BridgeSession(
            workspaceId: "workspace-1",
            workspaceName: "Axon",
            workspaceRoot: "/Users/tom/Projects/Axon",
            capabilities: [],
            extensionVersion: "test"
        )
        var settings = BridgeSettings()
        settings.preferBridgeWorkspaceForTerminal = true
        settings.terminalDefaultDirectory = "/Users/tom/Fallback"

        let request = try MacTerminalLaunchResolver.resolve(
            settings: settings,
            connectedSession: session,
            homeDirectory: "/Users/tom",
            isDirectory: { $0 == "/Users/tom/Projects/Axon" }
        )

        XCTAssertEqual(request.directoryURL.path, "/Users/tom/Projects/Axon")
        XCTAssertEqual(request.source, .bridgeWorkspace)
    }

    func testMacTerminalLaunchFallsBackToConfiguredDirectory() throws {
        var settings = BridgeSettings()
        settings.preferBridgeWorkspaceForTerminal = true
        settings.terminalDefaultDirectory = "/Users/tom/Fallback"

        let request = try MacTerminalLaunchResolver.resolve(
            settings: settings,
            connectedSession: nil,
            homeDirectory: "/Users/tom",
            isDirectory: { $0 == "/Users/tom/Fallback" }
        )

        XCTAssertEqual(request.directoryURL.path, "/Users/tom/Fallback")
        XCTAssertEqual(request.source, .configuredDirectory)
    }

    func testMacTerminalLaunchFallsBackToHomeDirectory() throws {
        let request = try MacTerminalLaunchResolver.resolve(
            settings: BridgeSettings(),
            connectedSession: nil,
            homeDirectory: "/Users/tom",
            isDirectory: { $0 == "/Users/tom" }
        )

        XCTAssertEqual(request.directoryURL.path, "/Users/tom")
        XCTAssertEqual(request.source, .home)
    }

    func testMacTerminalLaunchRejectsInvalidWorkingDirectory() {
        XCTAssertThrowsError(
            try MacTerminalLaunchResolver.resolve(
                settings: BridgeSettings(),
                connectedSession: nil,
                homeDirectory: "/Users/tom/Missing",
                isDirectory: { _ in false }
            )
        ) { error in
            XCTAssertEqual(
                error as? MacTerminalLauncherError,
                .invalidWorkingDirectory("/Users/tom/Missing")
            )
        }
    }
    #endif

    func testBridgeTerminalSessionMessagesRoundTrip() throws {
        let start = TerminalSessionStartParams(
            cwd: "/Users/tom/Projects/Axon",
            cols: 100,
            rows: 30,
            shell: "/bin/zsh"
        )
        let input = TerminalSessionInputParams(sessionId: "term-1", data: "ls\n")
        let resize = TerminalSessionResizeParams(sessionId: "term-1", cols: 120, rows: 40)
        let close = TerminalSessionCloseParams(sessionId: "term-1")
        let output = TerminalSessionOutputNotification(sessionId: "term-1", data: "Axon\n")
        let exited = TerminalSessionExitedNotification(sessionId: "term-1", exitCode: 0)

        XCTAssertEqual(try roundTrip(start), start)
        XCTAssertEqual(try roundTrip(input), input)
        XCTAssertEqual(try roundTrip(resize), resize)
        XCTAssertEqual(try roundTrip(close), close)
        XCTAssertEqual(try roundTrip(output), output)
        XCTAssertEqual(try roundTrip(exited), exited)
    }

    func testRemoteTerminalRequiresConnectedBridge() async {
        let transport = BridgeTerminalTransport(connectionManager: BridgeConnectionManager.shared)
        await BridgeConnectionManager.shared.stop()

        do {
            _ = try await transport.start(cwd: "/Users/tom", cols: 80, rows: 24)
            XCTFail("Expected bridge-not-connected failure")
        } catch let error as TerminalSessionError {
            XCTAssertEqual(error, .bridgeNotConnected)
            XCTAssertEqual(error.errorDescription, "VS Code bridge not connected")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
