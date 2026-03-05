//
//  ToolId.swift
//  Axon
//
//  Available tool identifiers
//

import Foundation

// MARK: - Tool ID

/// Available tool identifiers
enum ToolId: String, Codable, CaseIterable, Identifiable, Sendable {
    // Gemini Native Tools (called directly via Gemini API)
    case googleSearch = "google_search"
    case codeExecution = "code_execution"
    case urlContext = "url_context"
    case googleMaps = "google_maps"
    case fileSearch = "file_search"  // RAG-based document search (Gemini 2.5+, 3.0+)
    case geminiVideoGeneration = "gemini_video_gen"  // Veo 3.1 video generation

    // OpenAI Native Tools (called directly via OpenAI API)
    case openaiWebSearch = "openai_web_search"      // Web search via gpt-4o-search-preview
    case openaiImageGeneration = "openai_image_gen" // Image generation via gpt-image-1
    case openaiDeepResearch = "openai_deep_research" // Deep research via o3-deep-research
    case openaiVideoGeneration = "openai_video_gen"   // Sora video generation

    // Built-in Tools
    case createMemory = "create_memory"
    case conversationSearch = "conversation_search"  // Search recent conversations for context
    case reflectOnConversation = "reflect_on_conversation"  // Meta-analysis of current conversation
    case agentStateAppend = "agent_state_append"
    case agentStateQuery = "agent_state_query"
    case agentStateClear = "agent_state_clear"
    case heartbeatConfigure = "heartbeat_configure"
    case heartbeatRunOnce = "heartbeat_run_once"
    case heartbeatSetDeliveryProfile = "heartbeat_set_delivery_profile"
    case heartbeatUpdateProfile = "heartbeat_update_profile"
    case persistenceDisable = "persistence_disable"
    case notifyUser = "notify_user"

    // Tool Introspection Tools
    // Used to keep system prompt injection light: model can fetch tool metadata on demand.
    case listTools = "list_tools"  // Compact list of available tools
    case getToolDetails = "get_tool_details"  // Detailed schema/usage for a specific tool

    // Co-Sovereignty Tools
    case queryCovenant = "query_covenant"  // Query current covenant status and permissions
    case proposeCovenantChange = "propose_covenant_change"  // AI proposes covenant modifications

    // System State Tools (AI self-configuration)
    case querySystemState = "query_system_state"  // Query available providers, models, tools, permissions
    case changeSystemState = "change_system_state"  // Request changes to model, provider, or tools

    // Bridge Debugging
    case debugBridge = "debug_bridge"  // Check bridge connection status and logs

    // Multi-Device Presence Tools
    case queryDevicePresence = "query_device_presence"  // Query all devices and their presence states
    case requestDeviceSwitch = "request_device_switch"  // Request to switch agent focus to another device
    case setPresenceIntent = "set_presence_intent"  // Declare intent about which device to focus
    case saveStateCheckpoint = "save_state_checkpoint"  // Manually save a state checkpoint

    // Sub-Agent Orchestration Tools
    case spawnScout = "spawn_scout"                    // Spawn a Scout sub-agent (read-only reconnaissance)
    case spawnMechanic = "spawn_mechanic"              // Spawn a Mechanic sub-agent (read+write execution)
    case spawnDesigner = "spawn_designer"              // Spawn a Designer sub-agent (task decomposition)
    case queryJobStatus = "query_job_status"           // Query status of active/completed sub-agent jobs
    case acceptJobResult = "accept_job_result"         // Accept and integrate sub-agent job result
    case terminateJob = "terminate_job"                // Terminate a running sub-agent job

    // Temporal Symmetry Tools (AI-side of /sync, /drift, /status)
    case temporalSync = "temporal_sync"                // Enable temporal sync mode (mutual awareness)
    case temporalDrift = "temporal_drift"              // Enable drift mode (timeless void)
    case temporalStatus = "temporal_status"            // Query temporal status report

    // External App Integration Tools (Port Registry)
    case discoverPorts = "discover_ports"              // List/search available external app integrations
    case invokePort = "invoke_port"                    // Invoke an external app via URL scheme

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleSearch: return "Google Search"
        case .codeExecution: return "Code Execution"
        case .urlContext: return "URL Context"
        case .googleMaps: return "Google Maps"
        case .fileSearch: return "File Search"
        case .geminiVideoGeneration: return "Video Generation"
        case .openaiWebSearch: return "Web Search"
        case .openaiImageGeneration: return "Image Generation"
        case .openaiDeepResearch: return "Deep Research"
        case .openaiVideoGeneration: return "Video Generation"
        case .createMemory: return "Memory Creation"
        case .conversationSearch: return "Conversation History"
        case .reflectOnConversation: return "Conversation Reflection"
        case .agentStateAppend: return "Internal Thread Append"
        case .agentStateQuery: return "Internal Thread Query"
        case .agentStateClear: return "Internal Thread Clear"
        case .heartbeatConfigure: return "Heartbeat Configure"
        case .heartbeatRunOnce: return "Heartbeat Run Once"
        case .heartbeatSetDeliveryProfile: return "Heartbeat Set Delivery Profile"
        case .heartbeatUpdateProfile: return "Heartbeat Update Profile"
        case .persistenceDisable: return "Disable Persistence"
        case .notifyUser: return "Notify User"
        case .listTools: return "List Tools"
        case .getToolDetails: return "Tool Details"
        case .queryCovenant: return "Query Covenant"
        case .proposeCovenantChange: return "Propose Covenant Change"
        case .querySystemState: return "Query System State"
        case .changeSystemState: return "Change System State"
        case .debugBridge: return "Debug Bridge"
        case .queryDevicePresence: return "Query Device Presence"
        case .requestDeviceSwitch: return "Request Device Switch"
        case .setPresenceIntent: return "Set Presence Intent"
        case .saveStateCheckpoint: return "Save State Checkpoint"
        case .spawnScout: return "Spawn Scout"
        case .spawnMechanic: return "Spawn Mechanic"
        case .spawnDesigner: return "Spawn Designer"
        case .queryJobStatus: return "Query Job Status"
        case .acceptJobResult: return "Accept Job Result"
        case .terminateJob: return "Terminate Job"
        case .temporalSync: return "Temporal Sync"
        case .temporalDrift: return "Temporal Drift"
        case .temporalStatus: return "Temporal Status"
        case .discoverPorts: return "Discover External Apps"
        case .invokePort: return "Invoke External App"
        }
    }

    var description: String {
        switch self {
        case .googleSearch: return "Real-time web search grounded by Google"
        case .codeExecution: return "Execute Python code in a sandbox"
        case .urlContext: return "Fetch and analyze content from URLs"
        case .googleMaps: return "Location queries and place information"
        case .fileSearch: return "Search uploaded documents using semantic RAG"
        case .geminiVideoGeneration: return "Generate videos with Veo 3.1 (text/image to video)"
        case .openaiWebSearch: return "Real-time web search powered by OpenAI"
        case .openaiImageGeneration: return "Generate and edit images with GPT Image"
        case .openaiDeepResearch: return "Multi-step research with web search and analysis"
        case .openaiVideoGeneration: return "Generate videos with Sora (text/image to video)"
        case .createMemory: return "AI creates memories about you during chat"
        case .conversationSearch: return "Search recent conversations for context"
        case .reflectOnConversation: return "Analyze model usage, memories, and topic shifts"
        case .agentStateAppend: return "Append a new entry to the internal thread"
        case .agentStateQuery: return "Query internal thread entries"
        case .agentStateClear: return "Clear internal thread entries"
        case .heartbeatConfigure: return "Configure heartbeat scheduling and behavior"
        case .heartbeatRunOnce: return "Run heartbeat immediately"
        case .heartbeatSetDeliveryProfile: return "Select a heartbeat delivery profile"
        case .heartbeatUpdateProfile: return "Update or create a heartbeat delivery profile"
        case .persistenceDisable: return "Disable internal thread persistence (optionally wipe)"
        case .notifyUser: return "Send a user notification"
        case .listTools: return "List all available tools in a compact format"
        case .getToolDetails: return "Get detailed usage and input schema for a specific tool"
        case .queryCovenant: return "Query current covenant status and permissions"
        case .proposeCovenantChange: return "AI proposes modifications to the covenant"
        case .querySystemState: return "Query available providers, models, tools, and permissions"
        case .changeSystemState: return "Request changes to model, provider, or tool configuration"
        case .debugBridge: return "Check VS Code bridge connection status and recent logs"
        case .queryDevicePresence: return "Query all devices and their presence states"
        case .requestDeviceSwitch: return "Request to switch agent focus to another device"
        case .setPresenceIntent: return "Declare intent about which device to focus"
        case .saveStateCheckpoint: return "Manually save a state checkpoint for handoff"
        case .spawnScout: return "Spawn a Scout for read-only reconnaissance and exploration"
        case .spawnMechanic: return "Spawn a Mechanic for read+write code execution and fixes"
        case .spawnDesigner: return "Spawn a Designer for task decomposition and planning"
        case .queryJobStatus: return "Query status of active and completed sub-agent jobs"
        case .acceptJobResult: return "Accept and integrate a sub-agent's job result"
        case .terminateJob: return "Terminate a running sub-agent job"
        case .temporalSync: return "Enable temporal sync mode (mutual time awareness)"
        case .temporalDrift: return "Enable drift mode (timeless void, no tracking)"
        case .temporalStatus: return "Query current temporal status and metrics"
        case .discoverPorts: return "List and search available external app integrations"
        case .invokePort: return "Open an external app with specified action and parameters"
        }
    }

    var icon: String {
        switch self {
        case .googleSearch: return "magnifyingglass"
        case .codeExecution: return "terminal"
        case .urlContext: return "link"
        case .googleMaps: return "map"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .geminiVideoGeneration: return "video.badge.plus"
        case .openaiWebSearch: return "globe.americas"
        case .openaiImageGeneration: return "photo.badge.plus"
        case .openaiDeepResearch: return "text.book.closed"
        case .openaiVideoGeneration: return "video.badge.plus"
        case .createMemory: return "brain.head.profile"
        case .conversationSearch: return "clock.arrow.circlepath"
        case .reflectOnConversation: return "waveform.path.ecg"
        case .agentStateAppend: return "square.and.pencil"
        case .agentStateQuery: return "doc.text.magnifyingglass"
        case .agentStateClear: return "trash"
        case .heartbeatConfigure: return "heart.circle"
        case .heartbeatRunOnce: return "bolt.circle"
        case .heartbeatSetDeliveryProfile: return "list.bullet.rectangle"
        case .heartbeatUpdateProfile: return "slider.horizontal.3"
        case .persistenceDisable: return "xmark.circle"
        case .notifyUser: return "bell.badge"
        case .listTools: return "list.bullet"
        case .getToolDetails: return "info.circle"
        case .queryCovenant: return "doc.badge.gearshape"
        case .proposeCovenantChange: return "doc.badge.plus"
        case .querySystemState: return "gearshape.2"
        case .changeSystemState: return "gearshape.arrow.triangle.2.circlepath"
        case .debugBridge: return "ladybug"
        case .queryDevicePresence: return "iphone.and.arrow.forward"
        case .requestDeviceSwitch: return "arrow.left.arrow.right.circle"
        case .setPresenceIntent: return "location.circle"
        case .saveStateCheckpoint: return "arrow.down.doc"
        case .spawnScout: return "binoculars"
        case .spawnMechanic: return "wrench.and.screwdriver"
        case .spawnDesigner: return "square.and.pencil"
        case .queryJobStatus: return "list.bullet.clipboard"
        case .acceptJobResult: return "checkmark.seal"
        case .terminateJob: return "stop.circle"
        case .temporalSync: return "clock.badge.checkmark"
        case .temporalDrift: return "infinity"
        case .temporalStatus: return "chart.bar.fill"
        case .discoverPorts: return "app.connected.to.app.below.fill"
        case .invokePort: return "arrow.up.forward.app"
        }
    }

    var provider: ToolProvider {
        switch self {
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch, .geminiVideoGeneration:
            return .gemini
        case .openaiWebSearch, .openaiImageGeneration, .openaiDeepResearch, .openaiVideoGeneration:
            return .openai
        case .createMemory, .conversationSearch, .reflectOnConversation,
             .agentStateAppend, .agentStateQuery, .agentStateClear,
             .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile,
             .persistenceDisable, .notifyUser,
             .listTools, .getToolDetails,
             .queryCovenant, .proposeCovenantChange,
             .querySystemState, .changeSystemState,
             .debugBridge,
             .queryDevicePresence, .requestDeviceSwitch, .setPresenceIntent, .saveStateCheckpoint,
             .spawnScout, .spawnMechanic, .spawnDesigner, .queryJobStatus, .acceptJobResult, .terminateJob,
             .temporalSync, .temporalDrift, .temporalStatus,
             .discoverPorts, .invokePort:
            return .internal
        }
    }

    /// Whether this tool requires a Gemini API key
    var requiresGeminiKey: Bool {
        switch self {
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch, .geminiVideoGeneration:
            return true
        case .openaiWebSearch, .openaiImageGeneration, .openaiDeepResearch, .openaiVideoGeneration,
             .createMemory, .conversationSearch, .reflectOnConversation,
             .agentStateAppend, .agentStateQuery, .agentStateClear,
             .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile,
             .persistenceDisable, .notifyUser,
             .listTools, .getToolDetails,
             .queryCovenant, .proposeCovenantChange,
             .querySystemState, .changeSystemState,
             .debugBridge,
             .queryDevicePresence, .requestDeviceSwitch, .setPresenceIntent, .saveStateCheckpoint,
             .spawnScout, .spawnMechanic, .spawnDesigner, .queryJobStatus, .acceptJobResult, .terminateJob,
             .temporalSync, .temporalDrift, .temporalStatus,
             .discoverPorts, .invokePort:
            return false
        }
    }

    /// Whether this tool requires an OpenAI API key
    var requiresOpenAIKey: Bool {
        switch self {
        case .openaiWebSearch, .openaiImageGeneration, .openaiDeepResearch, .openaiVideoGeneration:
            return true
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch, .geminiVideoGeneration,
             .createMemory, .conversationSearch, .reflectOnConversation,
             .agentStateAppend, .agentStateQuery, .agentStateClear,
             .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile,
             .persistenceDisable, .notifyUser,
             .listTools, .getToolDetails,
             .queryCovenant, .proposeCovenantChange,
             .querySystemState, .changeSystemState,
             .debugBridge,
             .queryDevicePresence, .requestDeviceSwitch, .setPresenceIntent, .saveStateCheckpoint,
             .spawnScout, .spawnMechanic, .spawnDesigner, .queryJobStatus, .acceptJobResult, .terminateJob,
             .temporalSync, .temporalDrift, .temporalStatus,
             .discoverPorts, .invokePort:
            return false
        }
    }

    /// Whether this tool requires user approval before execution
    var requiresApproval: Bool {
        switch self {
        case .reflectOnConversation:
            return true  // Meta-analysis should require user awareness
        case .proposeCovenantChange:
            return true  // Covenant changes always require user consent
        case .changeSystemState:
            return true  // System state changes require user approval (unless pre-approved via trust tier)
        case .requestDeviceSwitch:
            return true  // Device switches should require user approval (based on door policy)
        case .openaiDeepResearch:
            return true  // Deep research can run for extended periods; user should be aware
        case .spawnScout, .spawnMechanic, .spawnDesigner:
            return true  // Sub-agent spawning requires user consent (job attestation gate)
        case .terminateJob:
            return true  // Terminating a running job should require user awareness
        case .invokePort:
            return true  // Opening external apps requires user awareness
        case .geminiVideoGeneration, .openaiVideoGeneration:
            return true  // Video generation is long-running and expensive
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch,
             .openaiWebSearch, .openaiImageGeneration,
             .createMemory, .conversationSearch, .queryCovenant, .querySystemState,
             .listTools, .getToolDetails,
             .agentStateAppend, .agentStateQuery, .agentStateClear,
             .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile,
             .persistenceDisable, .notifyUser,
             .debugBridge,
             .queryDevicePresence, .setPresenceIntent, .saveStateCheckpoint,
             .queryJobStatus, .acceptJobResult,
             .temporalSync, .temporalDrift, .temporalStatus,  // Temporal tools visible via status bar
             .discoverPorts:  // Read-only list of available apps
            return false
        }
    }

    /// Approval scopes describing what this tool will do
    var approvalScopes: [String] {
        switch self {
        case .reflectOnConversation:
            return [
                "Analyze conversation metadata (models, timestamps, tokens)",
                "Review memory operations performed",
                "Identify task types and topic shifts"
            ]
        case .proposeCovenantChange:
            return [
                "Propose modifications to the co-sovereignty covenant",
                "Request new trust tiers or capability changes",
                "Initiate negotiation process requiring your consent"
            ]
        case .changeSystemState:
            return [
                "Change active AI model or provider",
                "Enable or disable tools",
                "Modify system configuration"
            ]
        case .agentStateQuery:
            return [
                "Read internal thread entries",
                "Access user-visible agent state"
            ]
        case .agentStateClear:
            return [
                "Delete internal thread entries",
                "Clear stored agent state"
            ]
        case .notifyUser:
            return [
                "Send a local notification to the user"
            ]
        case .heartbeatConfigure:
            return [
                "Enable or disable heartbeat scheduling",
                "Adjust interval and notification behavior"
            ]
        case .heartbeatRunOnce:
            return [
                "Run the heartbeat immediately"
            ]
        case .heartbeatSetDeliveryProfile:
            return [
                "Select a heartbeat delivery profile"
            ]
        case .heartbeatUpdateProfile:
            return [
                "Update or create heartbeat delivery profiles"
            ]
        case .persistenceDisable:
            return [
                "Disable internal thread persistence",
                "Optionally wipe existing entries"
            ]
        case .requestDeviceSwitch:
            return [
                "Move agent focus to another device",
                "Transfer current context and state",
                "Subject to door policy on target device"
            ]
        case .openaiDeepResearch:
            return [
                "Perform multi-step web research (may take several minutes)",
                "Browse and analyze multiple web sources",
                "Synthesize findings into a comprehensive report"
            ]
        case .spawnScout:
            return [
                "Spawn a read-only Scout sub-agent",
                "Scout will explore and gather information",
                "Results go to an isolated silo (not main memory)"
            ]
        case .spawnMechanic:
            return [
                "Spawn a Mechanic sub-agent with read+write access",
                "Mechanic can execute code and make changes",
                "Results go to an isolated silo (not main memory)"
            ]
        case .spawnDesigner:
            return [
                "Spawn a Designer sub-agent for meta-reasoning",
                "Designer will plan and decompose tasks",
                "May recommend spawning additional agents"
            ]
        case .terminateJob:
            return [
                "Terminate a running sub-agent job",
                "Job will be marked as terminated",
                "Partial results may be available in silo"
            ]
        case .invokePort:
            return [
                "Open an external app via URL scheme",
                "Pass parameters to the external app action",
                "External app may perform actions on your behalf"
            ]
        case .geminiVideoGeneration:
            return [
                "Generate video using Gemini Veo 3.1 (long-running, 30s-6min)",
                "Video generation costs approximately $0.35/second",
                "Video will appear in Create gallery when complete"
            ]
        case .openaiVideoGeneration:
            return [
                "Generate video using OpenAI Sora (long-running, may take several minutes)",
                "Video generation costs approximately $0.20/second",
                "Video will appear in Create gallery when complete"
            ]
        default:
            return []
        }
    }

    /// Group tools by provider
    static func tools(for provider: ToolProvider) -> [ToolId] {
        allCases.filter { $0.provider == provider }
    }

    /// Tool category for organizational purposes
    var category: ToolCategory {
        switch self {
        case .googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch, .geminiVideoGeneration:
            return .geminiTools
        case .openaiWebSearch, .openaiImageGeneration, .openaiDeepResearch, .openaiVideoGeneration:
            return .openaiTools
        case .createMemory, .conversationSearch, .reflectOnConversation:
            return .memoryReflection
        case .agentStateAppend, .agentStateQuery, .agentStateClear:
            return .internalThread
        case .heartbeatConfigure, .heartbeatRunOnce, .heartbeatSetDeliveryProfile, .heartbeatUpdateProfile:
            return .heartbeat
        case .queryCovenant, .proposeCovenantChange:
            return .coSovereignty
        case .querySystemState, .changeSystemState:
            return .systemState
        case .queryDevicePresence, .requestDeviceSwitch, .setPresenceIntent, .saveStateCheckpoint:
            return .multiDevice
        case .spawnScout, .spawnMechanic, .spawnDesigner, .queryJobStatus, .acceptJobResult, .terminateJob:
            return .subAgentOrchestration
        case .notifyUser, .persistenceDisable:
            return .systemControl
        case .listTools, .getToolDetails:
            return .toolDiscovery
        case .debugBridge:
            return .debugging
        case .temporalSync, .temporalDrift, .temporalStatus:
            return .temporalSymmetry
        case .discoverPorts, .invokePort:
            return .externalApps
        }
    }

    /// Group tools by category
    static func toolsByCategory() -> [ToolCategory: [ToolId]] {
        var grouped: [ToolCategory: [ToolId]] = [:]
        for tool in allCases {
            grouped[tool.category, default: []].append(tool)
        }
        return grouped
    }

    /// Get tools for a specific category
    static func tools(for category: ToolCategory) -> [ToolId] {
        allCases.filter { $0.category == category }
    }
}
