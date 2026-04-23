//
//  BridgeTerminalTransport.swift
//  Axon
//
//  Remote terminal transport that streams through the VS Code bridge.
//

import Foundation
import Combine

@MainActor
final class BridgeTerminalTransport: TerminalTransport {
    private let connectionManager: BridgeConnectionManager
    private let outputSubject = PassthroughSubject<String, Never>()
    private let exitSubject = PassthroughSubject<Int?, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var sessionId: String?

    var outputPublisher: AnyPublisher<String, Never> {
        outputSubject.eraseToAnyPublisher()
    }

    var exitPublisher: AnyPublisher<Int?, Never> {
        exitSubject.eraseToAnyPublisher()
    }

    init(connectionManager: BridgeConnectionManager) {
        self.connectionManager = connectionManager

        NotificationCenter.default.publisher(for: .terminalSessionOutput)
            .compactMap { $0.object as? TerminalSessionOutputNotification }
            .sink { [weak self] notification in
                guard let self, notification.sessionId == self.sessionId else { return }
                self.outputSubject.send(notification.data)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .terminalSessionExited)
            .compactMap { $0.object as? TerminalSessionExitedNotification }
            .sink { [weak self] notification in
                guard let self, notification.sessionId == self.sessionId else { return }
                self.exitSubject.send(notification.exitCode)
            }
            .store(in: &cancellables)
    }

    func start(cwd: String, cols: Int, rows: Int) async throws -> TerminalSessionStartResult {
        guard connectionManager.isConnected else {
            throw TerminalSessionError.bridgeNotConnected
        }

        let params = TerminalSessionStartParams(cwd: cwd, cols: cols, rows: rows, shell: nil)
        let result = try await connectionManager.startTerminalSession(params)
        sessionId = result.sessionId
        return result
    }

    func sendInput(_ data: String) async throws {
        guard let sessionId else {
            throw TerminalSessionError.sessionNotStarted
        }
        try await connectionManager.sendTerminalInput(
            TerminalSessionInputParams(sessionId: sessionId, data: data)
        )
    }

    func resize(cols: Int, rows: Int) async throws {
        guard let sessionId else {
            throw TerminalSessionError.sessionNotStarted
        }
        try await connectionManager.resizeTerminalSession(
            TerminalSessionResizeParams(sessionId: sessionId, cols: cols, rows: rows)
        )
    }

    func close() async {
        guard let sessionId else { return }
        try? await connectionManager.closeTerminalSession(TerminalSessionCloseParams(sessionId: sessionId))
        self.sessionId = nil
    }
}
