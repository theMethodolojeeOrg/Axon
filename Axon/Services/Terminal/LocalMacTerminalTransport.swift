//
//  LocalMacTerminalTransport.swift
//  Axon
//
//  macOS local terminal transport backed by a pseudo-terminal.
//

import Foundation
import Combine

#if os(macOS)
import Darwin

@MainActor
final class LocalMacTerminalTransport: TerminalTransport {
    private let outputSubject = PassthroughSubject<String, Never>()
    private let exitSubject = PassthroughSubject<Int?, Never>()
    private var process: Process?
    private var masterHandle: FileHandle?
    private var sessionId: String?

    var outputPublisher: AnyPublisher<String, Never> {
        outputSubject.eraseToAnyPublisher()
    }

    var exitPublisher: AnyPublisher<Int?, Never> {
        exitSubject.eraseToAnyPublisher()
    }

    func start(cwd: String, cols: Int, rows: Int) async throws -> TerminalSessionStartResult {
        await close()

        var master: Int32 = -1
        var slave: Int32 = -1
        var windowSize = winsize(
            ws_row: UInt16(max(rows, 1)),
            ws_col: UInt16(max(cols, 1)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        guard openpty(&master, &slave, nil, nil, &windowSize) == 0 else {
            throw TerminalSessionError.startFailed("Failed to allocate pseudo-terminal")
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TERM": "xterm-256color",
            "COLUMNS": String(cols),
            "LINES": String(rows)
        ]) { _, new in new }

        let expandedCwd = NSString(string: cwd).expandingTildeInPath
        process.currentDirectoryURL = URL(fileURLWithPath: expandedCwd, isDirectory: true)

        let slaveInput = FileHandle(fileDescriptor: slave)
        let slaveOutput = FileHandle(fileDescriptor: dup(slave))
        let slaveError = FileHandle(fileDescriptor: dup(slave))
        process.standardInput = slaveInput
        process.standardOutput = slaveOutput
        process.standardError = slaveError

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let newSessionId = UUID().uuidString
        self.sessionId = newSessionId
        self.process = process
        self.masterHandle = masterHandle

        masterHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let output = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.outputSubject.send(output)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.exitSubject.send(Int(process.terminationStatus))
                self?.masterHandle?.readabilityHandler = nil
            }
        }

        do {
            try process.run()
            try? slaveInput.close()
            try? slaveOutput.close()
            try? slaveError.close()
            return TerminalSessionStartResult(sessionId: newSessionId, cwd: expandedCwd, shell: shell)
        } catch {
            masterHandle.readabilityHandler = nil
            try? masterHandle.close()
            throw TerminalSessionError.startFailed(error.localizedDescription)
        }
    }

    func sendInput(_ data: String) async throws {
        guard let masterHandle, let bytes = data.data(using: .utf8) else {
            throw TerminalSessionError.sessionNotStarted
        }
        try masterHandle.write(contentsOf: bytes)
    }

    func resize(cols: Int, rows: Int) async throws {
        guard let masterHandle else {
            throw TerminalSessionError.sessionNotStarted
        }
        var windowSize = winsize(
            ws_row: UInt16(max(rows, 1)),
            ws_col: UInt16(max(cols, 1)),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(masterHandle.fileDescriptor, TIOCSWINSZ, &windowSize)
    }

    func close() async {
        masterHandle?.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        try? masterHandle?.close()
        masterHandle = nil
        process = nil
        sessionId = nil
    }
}
#else
@MainActor
final class LocalMacTerminalTransport: TerminalTransport {
    private let outputSubject = PassthroughSubject<String, Never>()
    private let exitSubject = PassthroughSubject<Int?, Never>()

    var outputPublisher: AnyPublisher<String, Never> { outputSubject.eraseToAnyPublisher() }
    var exitPublisher: AnyPublisher<Int?, Never> { exitSubject.eraseToAnyPublisher() }

    func start(cwd: String, cols: Int, rows: Int) async throws -> TerminalSessionStartResult {
        throw TerminalSessionError.bridgeNotConnected
    }

    func sendInput(_ data: String) async throws {
        throw TerminalSessionError.sessionNotStarted
    }

    func resize(cols: Int, rows: Int) async throws {}

    func close() async {}
}
#endif
