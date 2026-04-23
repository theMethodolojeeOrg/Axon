//
//  TerminalSessionController.swift
//  Axon
//
//  Observable state owner for the bottom terminal drawer.
//

import Foundation
import Combine

@MainActor
final class TerminalSessionController: ObservableObject {
    static let shared = TerminalSessionController()

    @Published private(set) var buffer = ""
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var workingDirectory: String = ""
    @Published private(set) var workingDirectorySource: TerminalWorkingDirectorySource = .home
    @Published var pendingInput = ""
    @Published var isDrawerOpen: Bool {
        didSet {
            BridgeSettingsStorage.shared.setTerminalDrawerOpen(isDrawerOpen)
        }
    }
    @Published var drawerHeight: Double {
        didSet {
            BridgeSettingsStorage.shared.setTerminalDrawerHeight(drawerHeight)
        }
    }

    private var transport: TerminalTransport?
    private var cancellables = Set<AnyCancellable>()
    private let bridgeManager: BridgeConnectionManager
    private let bridgeSettings: BridgeSettingsStorage

    private init() {
        self.bridgeManager = BridgeConnectionManager.shared
        self.bridgeSettings = BridgeSettingsStorage.shared
        self.isDrawerOpen = BridgeSettingsStorage.shared.settings.terminalDrawerOpen
        self.drawerHeight = BridgeSettingsStorage.shared.settings.terminalDrawerHeight
    }

    func toggleDrawer() {
        isDrawerOpen.toggle()
        if isDrawerOpen && !isRunning && buffer.isEmpty {
            Task {
                await start()
            }
        }
    }

    func start(cols: Int = 100, rows: Int = 30) async {
        await transport?.close()
        cancellables.removeAll()
        buffer = ""
        errorMessage = nil

        let resolution = TerminalWorkingDirectoryResolver.resolve(
            settings: bridgeSettings.settings,
            connectedSession: bridgeManager.connectedSession
        )
        workingDirectory = resolution.path
        workingDirectorySource = resolution.source

        let selectedTransport: TerminalTransport
        #if os(macOS)
        selectedTransport = LocalMacTerminalTransport()
        #else
        selectedTransport = BridgeTerminalTransport(connectionManager: bridgeManager)
        #endif
        transport = selectedTransport

        selectedTransport.outputPublisher
            .sink { [weak self] output in
                self?.append(output)
            }
            .store(in: &cancellables)

        selectedTransport.exitPublisher
            .sink { [weak self] exitCode in
                self?.isRunning = false
                if let exitCode {
                    self?.append("\n[process exited \(exitCode)]\n")
                } else {
                    self?.append("\n[process exited]\n")
                }
            }
            .store(in: &cancellables)

        do {
            let result = try await selectedTransport.start(cwd: resolution.path, cols: cols, rows: rows)
            workingDirectory = result.cwd
            isRunning = true
        } catch {
            isRunning = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func sendPendingInput() {
        let input = pendingInput
        guard !input.isEmpty else { return }
        pendingInput = ""
        Task {
            await sendInput(input + "\n")
        }
    }

    func sendInput(_ input: String) async {
        do {
            try await transport?.sendInput(input)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func resize(cols: Int, rows: Int) async {
        try? await transport?.resize(cols: cols, rows: rows)
    }

    func clear() {
        buffer = ""
    }

    func close() {
        isDrawerOpen = false
        Task {
            await transport?.close()
            isRunning = false
        }
    }

    func restart() {
        Task {
            await start()
        }
    }

    private func append(_ output: String) {
        buffer += output
        let maxCount = 80_000
        if buffer.count > maxCount {
            buffer = String(buffer.suffix(maxCount))
        }
    }
}
