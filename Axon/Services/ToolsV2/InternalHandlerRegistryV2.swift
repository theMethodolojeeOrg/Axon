//
//  InternalHandlerRegistryV2.swift
//  Axon
//
//  Central registry mapping handler names to implementations.
//  Uses V2 suffix to enable parallel operation with V1 tool system.
//

import Foundation
import Combine
import os.log

// MARK: - Handler Registry

/// Central registry for V2 tool handlers
///
/// Maps handler IDs (from tool.json "handler" field) to handler implementations.
/// Handlers are registered at app startup and looked up during tool execution.
@MainActor
final class InternalHandlerRegistryV2: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = InternalHandlerRegistryV2()
    
    // MARK: - Properties
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "InternalHandlerRegistryV2"
    )
    
    /// Registered handlers keyed by handler ID
    private var handlers: [String: any ToolHandlerV2] = [:]
    
    /// Count of registered handlers
    @Published private(set) var handlerCount: Int = 0
    
    // MARK: - Initialization
    
    private init() {
        logger.debug("InternalHandlerRegistryV2 initialized")
        registerBuiltInHandlers()
    }
    
    // MARK: - Registration
    
    /// Register a handler with the registry
    /// - Parameter handler: The handler to register
    func registerHandler(_ handler: any ToolHandlerV2) {
        let id = handler.handlerId
        
        if handlers[id] != nil {
            logger.warning("Overwriting existing handler: \(id)")
        }
        
        handlers[id] = handler
        handlerCount = handlers.count
        logger.debug("Registered handler: \(id)")
    }
    
    /// Register multiple handlers at once
    /// - Parameter handlers: Array of handlers to register
    func registerHandlers(_ handlers: [any ToolHandlerV2]) {
        for handler in handlers {
            registerHandler(handler)
        }
    }
    
    /// Unregister a handler by ID
    /// - Parameter handlerId: The handler ID to remove
    func unregisterHandler(_ handlerId: String) {
        if handlers.removeValue(forKey: handlerId) != nil {
            handlerCount = handlers.count
            logger.debug("Unregistered handler: \(handlerId)")
        }
    }
    
    // MARK: - Lookup
    
    /// Get a handler by its ID
    /// - Parameter handlerId: The handler ID to look up
    /// - Returns: The handler if found, nil otherwise
    func handlerV2(for handlerId: String) -> (any ToolHandlerV2)? {
        handlers[handlerId]
    }
    
    /// Check if a handler is registered
    /// - Parameter handlerId: The handler ID to check
    /// - Returns: True if the handler is registered
    func hasHandler(_ handlerId: String) -> Bool {
        handlers[handlerId] != nil
    }
    
    /// Get all registered handler IDs
    var registeredHandlerIds: [String] {
        Array(handlers.keys).sorted()
    }
    
    // MARK: - Built-in Handlers
    
    /// Register all built-in handlers
    private func registerBuiltInHandlers() {
        // Core handlers (Phase 3)
        registerHandler(MemoryHandler())
        registerHandler(AgentStateHandler())
        registerHandler(HeartbeatHandler())
        registerHandler(SovereigntyHandler())
        registerHandler(SystemStateHandler())
        registerHandler(NotificationHandler())
        registerHandler(TemporalHandler())
        registerHandler(SubAgentHandler())
        registerHandler(DiscoveryHandler())
        registerHandler(DevicePresenceHandler())
        registerHandler(BridgeHandler())

        // Provider-specific handlers
        registerHandler(GeminiHandler())
        registerHandler(OpenAIHandler())
        registerHandler(XAIHandler())
        registerHandler(ZAIHandler())
        
        logger.info("Built-in handlers registered: \(self.handlers.count)")
    }
    
    // MARK: - Debug
    
    #if DEBUG
    /// Print registry status for debugging
    func debugPrintStatus() {
        print("""
        ╔════════════════════════════════════════════╗
        ║      Internal Handler Registry V2          ║
        ╠════════════════════════════════════════════╣
        ║ Registered Handlers: \(String(handlers.count).padding(toLength: 20, withPad: " ", startingAt: 0)) ║
        ╠════════════════════════════════════════════╣
        """)
        
        for id in registeredHandlerIds {
            print("║ - \(id.padding(toLength: 38, withPad: " ", startingAt: 0)) ║")
        }
        
        print("╚════════════════════════════════════════════╝")
    }
    
    /// Reset registry for testing
    func resetForTesting() {
        handlers.removeAll()
        handlerCount = 0
        logger.warning("Registry reset for testing")
    }
    #endif
}

// MARK: - Handler Discovery Helper

extension InternalHandlerRegistryV2 {
    
    /// Find which loaded tools don't have registered handlers
    /// - Parameter loadedTools: Tools loaded by ToolPluginLoader
    /// - Returns: Tool IDs that reference missing handlers
    func findMissingHandlers(for loadedTools: [LoadedTool]) -> [String] {
        var missing: [String] = []
        
        for tool in loadedTools {
            if tool.manifest.execution.type == .internalHandler {
                if let handlerId = tool.manifest.execution.handler {
                    if !hasHandler(handlerId) {
                        missing.append("\(tool.id): \(handlerId)")
                    }
                }
            }
        }
        
        return missing
    }
    
    /// Generate a report of handler coverage
    func generateCoverageReport(for loadedTools: [LoadedTool]) -> String {
        var report = "# Handler Coverage Report\n\n"
        
        let internalTools = loadedTools.filter {
            $0.manifest.execution.type == .internalHandler
        }
        
        let covered = internalTools.filter { tool in
            if let handlerId = tool.manifest.execution.handler {
                return hasHandler(handlerId)
            }
            return false
        }
        
        let coverage = internalTools.isEmpty ? 100.0 : 
            (Double(covered.count) / Double(internalTools.count)) * 100.0
        
        report += "**Coverage:** \(String(format: "%.1f", coverage))%\n"
        report += "**Covered:** \(covered.count)/\(internalTools.count)\n\n"
        
        let missing = findMissingHandlers(for: loadedTools)
        if !missing.isEmpty {
            report += "## Missing Handlers\n\n"
            for item in missing {
                report += "- \(item)\n"
            }
        }
        
        return report
    }
}
