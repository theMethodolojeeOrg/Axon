//
//  ToolCategory.swift
//  Axon
//
//  Tool categories for organizing tools in the UI
//

import Foundation

// MARK: - Tool Category

/// Categories for organizing tools in the UI
enum ToolCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case geminiTools = "gemini_tools"
    case openaiTools = "openai_tools"
    case memoryReflection = "memory_reflection"
    case internalThread = "internal_thread"
    case heartbeat = "heartbeat"
    case coSovereignty = "co_sovereignty"
    case systemState = "system_state"
    case multiDevice = "multi_device"
    case subAgentOrchestration = "sub_agent_orchestration"
    case systemControl = "system_control"
    case toolDiscovery = "tool_discovery"
    case debugging = "debugging"
    case temporalSymmetry = "temporal_symmetry"
    case externalApps = "external_apps"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .geminiTools: return "Gemini Tools"
        case .openaiTools: return "OpenAI Tools"
        case .memoryReflection: return "Memory & Reflection"
        case .internalThread: return "Internal Thread"
        case .heartbeat: return "Heartbeat"
        case .coSovereignty: return "Co-Sovereignty"
        case .systemState: return "System State"
        case .multiDevice: return "Multi-Device Presence"
        case .subAgentOrchestration: return "Sub-Agent Orchestration"
        case .systemControl: return "System Control"
        case .toolDiscovery: return "Tool Discovery"
        case .debugging: return "Debugging"
        case .temporalSymmetry: return "Temporal Symmetry"
        case .externalApps: return "External Apps"
        }
    }

    var description: String {
        switch self {
        case .geminiTools: return "Google-powered tools for search, code execution, and maps"
        case .openaiTools: return "OpenAI-powered tools for web search, images, and research"
        case .memoryReflection: return "Create memories and reflect on conversations"
        case .internalThread: return "AI's private workspace for notes and context"
        case .heartbeat: return "Scheduled check-ins and notifications"
        case .coSovereignty: return "Covenant-based trust and permissions"
        case .systemState: return "Query and modify system configuration"
        case .multiDevice: return "Cross-device presence and handoff"
        case .subAgentOrchestration: return "Spawn and manage sub-agents (scouts, mechanics, designers)"
        case .systemControl: return "Notifications and persistence control"
        case .toolDiscovery: return "Discover and query available tools"
        case .debugging: return "Debug VS Code bridge and connections"
        case .temporalSymmetry: return "Mutual time awareness between human and AI"
        case .externalApps: return "Invoke external iOS apps via URL schemes and Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .geminiTools: return "globe"
        case .openaiTools: return "cpu"
        case .memoryReflection: return "brain.head.profile"
        case .internalThread: return "doc.text"
        case .heartbeat: return "heart.circle"
        case .coSovereignty: return "doc.badge.gearshape"
        case .systemState: return "gearshape.2"
        case .multiDevice: return "iphone.and.arrow.forward"
        case .subAgentOrchestration: return "person.3.sequence"
        case .systemControl: return "slider.horizontal.3"
        case .toolDiscovery: return "list.bullet"
        case .debugging: return "ladybug"
        case .temporalSymmetry: return "clock.badge.checkmark"
        case .externalApps: return "app.connected.to.app.below.fill"
        }
    }
}
