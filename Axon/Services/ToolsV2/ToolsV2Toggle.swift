//
//  ToolsV2Toggle.swift
//  Axon
//
//  Created by Claude Code on 2024-12-19.
//
//  Toggle for switching between ToolsV1 (current) and ToolsV2 (plugin-based) systems.
//

import Foundation
import Combine
import os.log

// MARK: - Tool System Version

/// The active tool system version
enum ToolSystemVersion: String, Codable, CaseIterable {
    case v1 = "v1"
    case v2 = "v2"

    var displayName: String {
        switch self {
        case .v1: return "Classic (V1)"
        case .v2: return "Plugin-Based (V2)"
        }
    }

    var versionDescription: String {
        switch self {
        case .v1: return "Original hardcoded tool system"
        case .v2: return "New JSON-based plugin system"
        }
    }

    var icon: String {
        switch self {
        case .v1: return "1.circle.fill"
        case .v2: return "2.circle.fill"
        }
    }
}

// MARK: - Toggle Service

/// Service for managing the V1/V2 tool system toggle
@MainActor
final class ToolsV2Toggle: ObservableObject {

    // MARK: - Singleton

    static let shared = ToolsV2Toggle()

    // MARK: - Published State

    /// The currently active tool system version
    @Published private(set) var activeVersion: ToolSystemVersion

    /// Whether V2 is currently active
    var isV2Active: Bool {
        activeVersion == .v2
    }

    /// Whether V1 is currently active
    var isV1Active: Bool {
        activeVersion == .v1
    }

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ToolsV2Toggle"
    )

    private let userDefaultsKey = "ToolSystemActiveVersion"

    /// Feature flag for V2 availability (can be controlled remotely)
    private var isV2Available: Bool {
        // In production, this could check a remote feature flag
        // For now, always available during development
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "ToolsV2FeatureFlag")
        #endif
    }

    // MARK: - Initialization

    private init() {
        // Load saved version or default to V2 (the new plugin-based system)
        if let savedValue = UserDefaults.standard.string(forKey: userDefaultsKey),
           let version = ToolSystemVersion(rawValue: savedValue) {
            self.activeVersion = version
        } else {
            self.activeVersion = .v2
        }
    }

    // MARK: - Public API

    /// Switch to a specific tool system version
    /// - Parameter version: The version to switch to
    /// - Returns: True if switch was successful
    @discardableResult
    func switchTo(_ version: ToolSystemVersion) -> Bool {
        guard version == .v1 || isV2Available else {
            logger.warning("Cannot switch to V2: feature not available")
            return false
        }

        if activeVersion != version {
            activeVersion = version
            saveActiveVersion()
            logger.info("Tool system version changed to: \(version.rawValue)")
        }
        return true
    }

    /// Toggle between V1 and V2
    /// - Returns: The new active version
    @discardableResult
    func toggle() -> ToolSystemVersion {
        let newVersion: ToolSystemVersion = activeVersion == .v1 ? .v2 : .v1

        if switchTo(newVersion) {
            return newVersion
        }
        return activeVersion
    }

    /// Check if a specific version is available
    func isVersionAvailable(_ version: ToolSystemVersion) -> Bool {
        switch version {
        case .v1: return true
        case .v2: return isV2Available
        }
    }

    /// Reset to default (V1)
    func resetToDefault() {
        activeVersion = .v1
        saveActiveVersion()
        logger.info("Reset tool system to default (V1)")
    }

    // MARK: - Private Helpers

    private func saveActiveVersion() {
        UserDefaults.standard.set(activeVersion.rawValue, forKey: userDefaultsKey)
    }
}

// MARK: - Router Helper

/// Helper for routing tool execution based on active version
enum ToolSystemRouter {

    /// Execute a closure based on the active tool system
    /// - Parameters:
    ///   - v1Handler: Handler for V1 tool system
    ///   - v2Handler: Handler for V2 tool system
    /// - Returns: Result from the appropriate handler
    @MainActor
    static func route<T>(
        v1: () async throws -> T,
        v2: () async throws -> T
    ) async throws -> T {
        switch ToolsV2Toggle.shared.activeVersion {
        case .v1:
            return try await v1()
        case .v2:
            return try await v2()
        }
    }

    /// Execute a closure based on the active tool system (non-throwing)
    @MainActor
    static func route<T>(
        v1: () async -> T,
        v2: () async -> T
    ) async -> T {
        switch ToolsV2Toggle.shared.activeVersion {
        case .v1:
            return await v1()
        case .v2:
            return await v2()
        }
    }

    /// Execute a closure based on the active tool system (synchronous)
    @MainActor
    static func routeSync<T>(
        v1: () -> T,
        v2: () -> T
    ) -> T {
        switch ToolsV2Toggle.shared.activeVersion {
        case .v1:
            return v1()
        case .v2:
            return v2()
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Posted when the tool system version changes
    static let toolSystemVersionDidChange = Notification.Name("ToolSystemVersionDidChange")
}

// MARK: - Debug Utilities

#if DEBUG
extension ToolsV2Toggle {

    /// Force V2 for testing (DEBUG only)
    func forceV2ForTesting() {
        activeVersion = .v2
        saveActiveVersion()
        logger.warning("Forced V2 for testing - not for production use")
    }

    /// Print current state for debugging
    func debugPrintState() {
        print("""
        ╔════════════════════════════════════════╗
        ║       Tool System Toggle State         ║
        ╠════════════════════════════════════════╣
        ║ Active Version: \(activeVersion.rawValue.padding(toLength: 22, withPad: " ", startingAt: 0)) ║
        ║ V2 Available:   \(String(isV2Available).padding(toLength: 22, withPad: " ", startingAt: 0)) ║
        ║ Display Name:   \(activeVersion.displayName.padding(toLength: 22, withPad: " ", startingAt: 0)) ║
        ╚════════════════════════════════════════╝
        """)
    }
}
#endif
