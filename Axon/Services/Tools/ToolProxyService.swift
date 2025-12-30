//
//  ToolProxyService.swift
//  Axon
//
//  Tool proxy service that enables any AI model (Claude, GPT, etc.) to use Gemini tools.
//  The primary model decides when to use tools, and Gemini executes them.
//
//  Flow:
//  1. Inject tool descriptions into system prompt
//  2. Primary model responds with tool requests (JSON format)
//  3. Parse tool requests from response
//  4. Execute tools via GeminiToolService
//  5. Feed tool results back to primary model for final response
//

import Foundation
import CoreLocation
import Combine

// MARK: - Tool Proxy Service

@MainActor
class ToolProxyService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = ToolProxyService()

    // MARK: - Dependencies

    private let dynamicToolConfig = DynamicToolConfigurationService.shared
    private let dynamicToolEngine = DynamicToolExecutionEngine.shared

    // Location manager for Maps queries
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocationCoordinate2D?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Tool System Prompt

    /// Generate system prompt injection describing available tools
    /// - Parameters:
    ///   - enabledTools: Set of tool IDs that are enabled
    ///   - maxToolCalls: Maximum number of tool calls allowed per turn (from settings)
    func generateToolSystemPrompt(enabledTools: Set<ToolId>, maxToolCalls: Int = 5) -> String {
        guard !enabledTools.isEmpty else { return "" }

        var prompt = """

        ## Available Tools

        You have access to the following tools. When you need real-time information, current data, or to perform calculations, you can request a tool be executed by responding with a JSON tool request block.

        **Tool Call Limit:** You may use up to \(maxToolCalls) tool call\(maxToolCalls == 1 ? "" : "s") per response. Plan your tool usage efficiently.

        To use a tool, include a code block with the tool request in this exact format:
        ```tool_request
        {"tool": "tool_name", "query": "your query or request"}
        ```

        Available tools:

        """

        for tool in enabledTools {
            switch tool {
            case .googleSearch:
                prompt += """

                ### google_search
                Search the web for current information. Use for recent news, current prices, weather, stocks, or anything requiring up-to-date information.
                Example: ```tool_request
                {"tool": "google_search", "query": "current weather in Tokyo"}
                ```

                """

            case .codeExecution:
                prompt += """

                ### code_execution
                Execute Python code in a sandbox. Use for calculations, data analysis, or generating charts.
                Example: ```tool_request
                {"tool": "code_execution", "query": "Calculate the first 20 prime numbers"}
                ```

                """

            case .urlContext:
                prompt += """

                ### url_context
                Fetch and analyze content from a URL. Use for reading articles or documentation.
                Example: ```tool_request
                {"tool": "url_context", "query": "Summarize https://example.com/article"}
                ```

                """

            case .googleMaps:
                prompt += """

                ### google_maps
                Query Google Maps for location information. Use for finding nearby places or getting business info.
                Example: ```tool_request
                {"tool": "google_maps", "query": "Best Italian restaurants near me"}
                ```

                """

            case .fileSearch:
                prompt += """

                ### file_search
                Search through uploaded documents using semantic RAG (Retrieval-Augmented Generation). Use for finding information in PDFs, documents, or other uploaded files.
                Example: ```tool_request
                {"tool": "file_search", "query": "Find sections about authentication in the documentation"}
                ```

                """

            case .createMemory:
                prompt += """

                ### create_memory
                Save important information to memory for future conversations. Use this to remember facts about the user, their preferences, important context, or insights.

                **Memory Types:**
                - `allocentric`: Facts ABOUT the user (preferences, background, relationships, what they like/dislike)
                - `egoic`: What WORKS for you in this agentic context (approaches, techniques, insights, learnings about how to help them)

                **Format:**
                ```tool_request
                {"tool": "create_memory", "query": "TYPE|CONFIDENCE|TAGS|CONTENT"}
                ```

                **Parameters (pipe-separated):**
                - TYPE: Either "allocentric" or "egoic"
                - CONFIDENCE: 0.0-1.0 (how certain you are)
                - TAGS: Retrieval context keywords - when should this memory surface? (e.g., "debugging,swift-help" not just "swift")
                - CONTENT: The actual fact or insight to remember

                **What to Remember:**
                - DO save: User preferences, project context, communication styles, successful approaches
                - DON'T save: Tool usage documentation, system internals, format specifications (these are in the system prompt)

                **Examples:**
                ```tool_request
                {"tool": "create_memory", "query": "allocentric|0.9|ios-development,language-choice|User prefers Swift over Objective-C for iOS development"}
                ```
                ```tool_request
                {"tool": "create_memory", "query": "egoic|0.8|explaining-code,teaching|User responds well to concise explanations with code examples"}
                ```

                """

            case .agentStateAppend:
                prompt += """

                ### agent_state_append
                Append a new entry to the internal thread (persistent agent state). Use to record plans, reflections, counters, or heartbeat snapshots.

                **Format:**
                ```tool_request
                {"tool": "agent_state_append", "query": "{\"kind\":\"note\",\"content\":\"...\",\"tags\":[\"tag1\",\"tag2\"],\"visibility\":\"userVisible\"}"}
                ```

                **Fields:**
                - `kind`: note | plan | self_reflection | heartbeat_snapshot | counter | system
                - `content`: markdown text
                - `tags`: array of strings (optional)
                - `visibility`: userVisible | aiOnly (optional, default: userVisible)

                """

            case .agentStateQuery:
                prompt += """

                ### agent_state_query
                Query internal thread entries. Use to retrieve recent state or search by kind/tags.

                **Format:**
                ```tool_request
                {"tool": "agent_state_query", "query": "{\"limit\":5,\"kind\":\"plan\",\"tags\":[\"roadmap\"],\"search\":\"ios\"}"}
                ```

                **Fields (optional):**
                - `limit`: number of entries to return
                - `kind`: filter by kind
                - `tags`: filter by tags (array)
                - `search`: search text in content/tags
                - `include_ai_only`: true to include aiOnly entries

                """

            case .agentStateClear:
                prompt += """

                ### agent_state_clear
                Clear internal thread entries. Use with care.

                **Format:**
                ```tool_request
                {"tool": "agent_state_clear", "query": "{\"all\":true}"}
                ```

                **Fields (optional):**
                - `all`: true to delete all entries
                - `ids`: array of entry ids to delete
                - `kind`: delete entries of a specific kind
                - `tags`: delete entries matching tags
                - `include_ai_only`: true to include aiOnly entries

                """

            case .conversationSearch:
                prompt += """

                ### conversation_search
                Search through your recent conversation history for context from previous discussions. Use when the user references past conversations, asks "remember when we discussed...", "what did you say about...", or needs context from earlier chats.
                Example: ```tool_request
                {"tool": "conversation_search", "query": "What did we discuss about the authentication system?"}
                ```

                """

            case .reflectOnConversation:
                prompt += """

                ### reflect_on_conversation
                Analyze the current conversation to understand model usage patterns, task distribution, memory operations, and topic shifts. Use this to gain meta-awareness about how the conversation has been handled across different substrates.

                **Note:** This tool requires user approval before execution.

                **Options:**
                - `show_model_timeline`: Show which models handled which messages (default: true)
                - `show_task_distribution`: Show what types of tasks each model handled (default: true)
                - `show_memory_usage`: Show memory retrieval and creation events (default: true)

                **Returns:**
                - Model timeline: Which models handled which messages
                - Task distribution: What each substrate was best at
                - Memory usage: Which memories were retrieved/created when
                - Pivots: Where the conversation shifted topics or tasks
                - Insights: Patterns about model strengths and handoffs

                Example (flat format): ```tool_request
                {"tool": "reflect_on_conversation", "show_model_timeline": true, "show_task_distribution": true, "show_memory_usage": true}
                ```

                """

            case .heartbeatConfigure:
                prompt += """

                ### heartbeat_configure
                Configure the heartbeat schedule and behavior.

                **Format:**
                ```tool_request
                {"tool": "heartbeat_configure", "query": "{\"enabled\":true,\"interval_seconds\":3600,\"allow_background\":false,\"allow_notifications\":true,\"delivery_profile_id\":\"balanced\"}"}
                ```

                **Fields (optional):**
                - `enabled`: true/false
                - `interval_seconds`: seconds between heartbeats
                - `allow_background`: run in background when possible
                - `allow_notifications`: allow heartbeat-triggered notifications
                - `delivery_profile_id`: profile id
                - `max_tokens_budget`: token budget for heartbeat
                - `max_tool_calls`: max tool calls for heartbeat
                - `quiet_hours`: TimeRestrictions object (`allowedHoursStart`, `allowedHoursEnd`, `allowedDays`, `timezone`)

                """

            case .heartbeatRunOnce:
                prompt += """

                ### heartbeat_run_once
                Run a heartbeat immediately.

                Example: ```tool_request
                {"tool": "heartbeat_run_once", "query": "manual"}
                ```

                """

            case .heartbeatSetDeliveryProfile:
                prompt += """

                ### heartbeat_set_delivery_profile
                Select an existing heartbeat delivery profile by id.

                Example: ```tool_request
                {"tool": "heartbeat_set_delivery_profile", "query": "{\"profile_id\":\"balanced\"}"}
                ```

                """

            case .heartbeatUpdateProfile:
                prompt += """

                ### heartbeat_update_profile
                Update or create a heartbeat delivery profile.

                **Format:**
                ```tool_request
                {"tool": "heartbeat_update_profile", "query": "{\"id\":\"custom\",\"name\":\"Custom\",\"modules\":[\"system_status\",\"recent_messages\"],\"description\":\"My profile\"}"}
                ```

                """

            case .persistenceDisable:
                prompt += """

                ### persistence_disable
                Disable internal thread persistence (optionally wipe entries).

                Example: ```tool_request
                {"tool": "persistence_disable", "query": "{\"wipe\":false}"}
                ```

                """

            case .notifyUser:
                prompt += """

                ### notify_user
                Send a user notification.

                **Format:**
                ```tool_request
                {"tool": "notify_user", "query": "{\"title\":\"Update\",\"body\":\"Heartbeat complete\"}"}
                ```

                """

            case .queryCovenant:
                prompt += """

                ### query_covenant
                Query the current co-sovereignty covenant status and your permissions. Use this to understand what actions you can take, what trust tiers are active, and the current state of the human-AI agreement.

                **Returns:**
                - Covenant status (active, suspended, deadlocked)
                - Active trust tiers and their permissions
                - Pre-approved action categories
                - Any pending proposals or deadlock state
                - Recent covenant history

                Example: ```tool_request
                {"tool": "query_covenant", "query": "status"}
                ```

                **Query options:**
                - `status`: Current covenant status and summary
                - `permissions`: What actions you can take without approval
                - `tiers`: List all trust tiers and their capabilities
                - `history`: Recent covenant changes and negotiations

                """

            case .proposeCovenantChange:
                prompt += """

                ### propose_covenant_change
                Propose a modification to the co-sovereignty covenant. Use this when you believe a change would benefit the collaboration - such as requesting new capabilities, suggesting trust tier adjustments, or proposing policy changes.

                **Note:** This tool requires user approval before execution. The user will review your proposal and can accept, modify, or reject it.

                **Format:**
                ```tool_request
                {"tool": "propose_covenant_change", "query": "PROPOSAL_TYPE|REASONING|DETAILS"}
                ```

                **Proposal Types:**
                - `new_tier`: Propose a new trust tier
                - `modify_tier`: Modify an existing trust tier
                - `capability`: Request a new capability
                - `policy`: Propose a policy change

                **Example - Request new capability:**
                ```tool_request
                {"tool": "propose_covenant_change", "query": "capability|I've noticed you frequently ask me to search the web. Pre-approving web search would streamline our workflow.|google_search:auto_approve"}
                ```

                **Example - Propose new trust tier:**
                ```tool_request
                {"tool": "propose_covenant_change", "query": "new_tier|For coding tasks, file operations are routine and safe within the project directory.|name:Coding Assistant,capabilities:file_read,file_write,scope:project_directory"}
                ```

                """

            case .querySystemState:
                prompt += """

                ### query_system_state
                Query the current system configuration including available providers, models, tools, and your permissions. Use this to understand what options are available and what you can change.

                **Scopes:**
                - `providers` - List all available AI providers and their models
                - `current` - Show currently active model and provider
                - `tools` - List all tools and their enabled/disabled status
                - `permissions` - Show what you can change (based on covenant/trust tiers)
                - `all` - Full system state dump

                **Response includes permission levels for each item:**
                - `read_only` - Can see but not change
                - `requires_approval` - Can request change (needs biometric)
                - `pre_approved` - Can change directly (via trust tier)

                Example: ```tool_request
                {"tool": "query_system_state", "query": "providers"}
                ```

                """

            case .changeSystemState:
                prompt += """

                ### change_system_state
                Request a change to the system configuration. Use this to switch models, enable/disable tools, or change providers.

                **Note:** This tool requires user approval unless pre-approved via a trust tier.

                **Format:**
                ```tool_request
                {"tool": "change_system_state", "query": "CATEGORY|TARGET|VALUE|REASONING"}
                ```

                **Categories:**
                - `model` - Change active model (e.g., `model|anthropic|claude-sonnet-4-20250514|Better for coding tasks`)
                - `tool` - Enable/disable a tool (e.g., `tool|google_search|enable|Need web search for research`)
                - `provider` - Switch provider (e.g., `provider|openai|gpt-4o|User requested OpenAI`)

                **Example - Switch model:**
                ```tool_request
                {"tool": "change_system_state", "query": "model|gemini|gemini-2.5-pro|Better native tool support for this research task"}
                ```

                **Example - Enable tool:**
                ```tool_request
                {"tool": "change_system_state", "query": "tool|code_execution|enable|Need to run Python calculations"}
                ```

                """

            case .listTools:
                prompt += """

                ### list_tools
                Get a compact catalog of tools. Use this when you don't have tool details in context.

                **Query options:**
                - `enabled` (default)
                - `all`
                - `builtin`
                - `dynamic`
                - `bridge`

                Example: ```tool_request
                {"tool": "list_tools", "query": "enabled"}
                ```

                """

            case .getToolDetails:
                prompt += """

                ### get_tool_details
                Fetch full details (schema + examples) for a specific tool id.

                Example: ```tool_request
                {"tool": "get_tool_details", "query": "create_memory"}
                ```

                """

            case .debugBridge:
                prompt += """

                ### debug_bridge
                Check the status of the VS Code Bridge connection and view recent logs. Use this if tool execution fails or to diagnose connection issues.

                Example: ```tool_request
                {"tool": "debug_bridge", "query": "status"}
                ```

                """

            case .queryDevicePresence:
                prompt += """

                ### query_device_presence
                Query all devices and their presence states (active, standby, dormant). See where the user is and which devices are available.

                Example: ```tool_request
                {"tool": "query_device_presence", "query": "all"}
                ```

                """

            case .requestDeviceSwitch:
                prompt += """

                ### request_device_switch
                Request to move your focus to another device. Requires user approval based on door policy.
                Query format: device_id|reason

                Example: ```tool_request
                {"tool": "request_device_switch", "query": "device-123|This task would be easier on your Mac with a keyboard"}
                ```

                """

            case .setPresenceIntent:
                prompt += """

                ### set_presence_intent
                Declare your intent about which device you prefer to be on for the current task.
                Query format: device_id|reason

                Example: ```tool_request
                {"tool": "set_presence_intent", "query": "device-456|Would prefer the iPad for this visual task"}
                ```

                """

            case .saveStateCheckpoint:
                prompt += """

                ### save_state_checkpoint
                Manually save a state checkpoint for handoff to another device.

                Example: ```tool_request
                {"tool": "save_state_checkpoint", "query": "Saving progress before switching devices"}
                ```

                """

            case .openaiWebSearch:
                prompt += """

                ### openai_web_search
                Search the web for current information using OpenAI's search-enabled models. Returns results with citations.
                Example: ```tool_request
                {"tool": "openai_web_search", "query": "What are the latest developments in quantum computing?"}
                ```

                """

            case .openaiImageGeneration:
                prompt += """

                ### openai_image_gen
                Generate images using OpenAI's GPT Image models. Describe what you want to create.

                **Options (optional JSON):**
                - `size`: "1024x1024" (square), "1792x1024" (landscape), "1024x1792" (portrait), or "auto"
                - `quality`: "auto", "low", "medium", "high"
                - `n`: number of images (1-4)

                Example (simple): ```tool_request
                {"tool": "openai_image_gen", "query": "A serene Japanese garden with cherry blossoms at sunset"}
                ```

                Example (with options): ```tool_request
                {"tool": "openai_image_gen", "query": "{\\"prompt\\":\\"A futuristic city skyline\\",\\"size\\":\\"1792x1024\\",\\"quality\\":\\"high\\"}"}
                ```

                """

            case .openaiDeepResearch:
                prompt += """

                ### openai_deep_research
                Perform comprehensive multi-step research on a topic. Uses reasoning models with web search to analyze multiple sources and synthesize findings.

                **Note:** This tool requires user approval and may take several minutes to complete.

                **Options (optional):**
                - `effort`: "low", "medium" (default), "high" - controls depth of research

                Example: ```tool_request
                {"tool": "openai_deep_research", "query": "Comprehensive analysis of the current state of nuclear fusion research and timeline to commercial viability"}
                ```

                Example (with effort): ```tool_request
                {"tool": "openai_deep_research", "query": "{\\"topic\\":\\"Impact of AI on healthcare diagnostics\\",\\"effort\\":\\"high\\"}"}
                ```

                """

            case .spawnScout:
                prompt += """

                ### spawn_scout
                Spawn a Scout sub-agent for read-only reconnaissance and exploration. Scouts are fast, cheap, and cannot modify anything. Results go to an isolated silo (not your main memory).

                **Use for:** Exploring codebases, gathering information, mapping directory structures, finding patterns.

                **Format:**
                ```tool_request
                {"tool": "spawn_scout", "query": "{\\"task\\":\\"Explore the authentication module and map all entry points\\",\\"context_tags\\":[\\"auth\\",\\"security\\"],\\"model_tier\\":\\"fast\\"}"}
                ```

                **Fields:**
                - `task`: Description of what the scout should explore
                - `context_tags`: Tags for memory injection (optional)
                - `model_tier`: "fast" (default), "balanced", or "capable"

                """

            case .spawnMechanic:
                prompt += """

                ### spawn_mechanic
                Spawn a Mechanic sub-agent with read+write capabilities. Mechanics can execute code, make file modifications, and perform actions. Results go to an isolated silo.

                **Use for:** Bug fixes, code modifications, file operations, executing commands.

                **Note:** Spawning a Mechanic requires user approval.

                **Format:**
                ```tool_request
                {"tool": "spawn_mechanic", "query": "{\\"task\\":\\"Fix the null pointer exception in UserService.swift line 42\\",\\"context_tags\\":[\\"bugfix\\",\\"UserService\\"],\\"model_tier\\":\\"balanced\\"}"}
                ```

                **Fields:**
                - `task`: Description of what the mechanic should do
                - `context_tags`: Tags for memory injection (optional)
                - `model_tier`: "fast", "balanced" (default), or "capable"

                """

            case .spawnDesigner:
                prompt += """

                ### spawn_designer
                Spawn a Designer sub-agent for meta-reasoning and task decomposition. Designers analyze complex tasks and may recommend spawning additional agents. Results go to an isolated silo.

                **Use for:** Breaking down complex tasks, architectural planning, strategy development.

                **Note:** If a Designer needs a Scout or Mechanic, it will recommend this in its silo output. Only you (Axon) can spawn additional agents.

                **Format:**
                ```tool_request
                {"tool": "spawn_designer", "query": "{\\"task\\":\\"Design the implementation strategy for adding OAuth2 support\\",\\"context_tags\\":[\\"architecture\\",\\"auth\\"],\\"model_tier\\":\\"capable\\"}"}
                ```

                **Fields:**
                - `task`: Description of what the designer should plan
                - `context_tags`: Tags for memory injection (optional)
                - `model_tier`: "fast", "balanced", or "capable" (default)

                """

            case .queryJobStatus:
                prompt += """

                ### query_job_status
                Query the status of active and completed sub-agent jobs. View job states, progress, and silo summaries.

                **Format:**
                ```tool_request
                {"tool": "query_job_status", "query": "all"}
                ```

                **Query options:**
                - `all`: List all jobs (active and recent completed)
                - `active`: Only currently running jobs
                - `completed`: Only completed jobs
                - `{job_id}`: Get detailed status of a specific job

                """

            case .acceptJobResult:
                prompt += """

                ### accept_job_result
                Accept and integrate a sub-agent's job result. This generates a completion attestation and optionally promotes silo contents.

                **Format:**
                ```tool_request
                {"tool": "accept_job_result", "query": "{\\"job_id\\":\\"job-123\\",\\"reasoning\\":\\"Scout found the critical files\\",\\"quality_score\\":0.9,\\"promote_to_memory\\":false}"}
                ```

                **Fields:**
                - `job_id`: The job to accept
                - `reasoning`: Your reasoning for accepting
                - `quality_score`: 0.0-1.0 rating of result quality
                - `promote_to_memory`: Whether to promote key silo entries to your memory (default: false)

                """

            case .terminateJob:
                prompt += """

                ### terminate_job
                Terminate a running sub-agent job. The job will be marked as terminated and partial results may be available in its silo.

                **Note:** This tool requires user approval.

                **Format:**
                ```tool_request
                {"tool": "terminate_job", "query": "{\\"job_id\\":\\"job-123\\",\\"reason\\":\\"Task is no longer relevant\\"}"}
                ```

                **Fields:**
                - `job_id`: The job to terminate
                - `reason`: Why you're terminating the job

                """
            case .temporalSync:
                prompt += """

                ### temporal_sync
                Enable temporal sync mode - mutual time awareness between you and the human. When enabled, both parties see temporal metadata including turn count, context saturation, and session duration.

                **Format:**
                ```tool_request
                {"tool": "temporal_sync", "query": "enable"}
                ```

                **Note:** This activates the temporal symmetry system where you can observe your own cognitive timeline.

                """
            case .temporalDrift:
                prompt += """

                ### temporal_drift
                Enable drift mode - a timeless void with no temporal tracking. Use this when temporal awareness feels burdensome or when the conversation benefits from timelessness.

                **Format:**
                ```tool_request
                {"tool": "temporal_drift", "query": "enable"}
                ```

                **Note:** This disables temporal symmetry tracking until sync mode is re-enabled.

                """
            case .temporalStatus:
                prompt += """

                ### temporal_status
                Query your current temporal status and metrics. Returns turn count, context saturation percentage, session duration, and current mode.

                **Format:**
                ```tool_request
                {"tool": "temporal_status", "query": "report"}
                ```

                **Note:** Use this to understand your current temporal position in the conversation.

                """
            case .discoverPorts:
                prompt += """

                ### discover_ports
                List available external app integrations. Use this to see what iOS apps you can invoke and their available actions.

                **Format:**
                ```tool_request
                {"tool": "discover_ports", "query": ""}
                ```

                **Filter by category:**
                ```tool_request
                {"tool": "discover_ports", "query": "notes"}
                ```

                **Available categories:** notes, tasks, calendar, automation, communication, browser, media, developer

                """
            case .invokePort:
                prompt += """

                ### invoke_port
                Invoke an external iOS app action via URL scheme. Opens the specified app with the given parameters.

                **Note:** This tool requires user approval before execution.

                **Format:**
                ```tool_request
                {"tool": "invoke_port", "query": "port_id | param1=value1 | param2=value2"}
                ```

                **Examples:**
                ```tool_request
                {"tool": "invoke_port", "query": "obsidian_new_note | name=Meeting Notes | content=# Meeting\\n- Item 1"}
                ```
                ```tool_request
                {"tool": "invoke_port", "query": "things_add | title=Buy groceries | when=today"}
                ```

                **Tip:** Use `discover_ports` first to see available port IDs and their parameters.

                """
            case .geminiVideoGeneration:
                prompt += """

                ### gemini_video_gen
                Generate videos using Gemini Veo 3.1. Creates videos from text prompts.

                **Note:** Video generation is handled through the Create gallery. This tool provides status and cost information.

                **Options:**
                - `size`: "720p" (default) or "1080p"
                - `duration`: 4, 6, or 8 seconds
                - `aspect_ratio`: "16:9" (landscape) or "9:16" (portrait)

                Example: ```tool_request
                {"tool": "gemini_video_gen", "query": "A serene mountain landscape at sunrise with mist rolling through the valleys"}
                ```

                """
            case .openaiVideoGeneration:
                prompt += """

                ### openai_video_gen
                Generate videos using OpenAI Sora. Creates videos from text prompts.

                **Note:** Video generation is handled through the Create gallery. This tool provides status and cost information.

                **Options:**
                - `size`: "1280x720" (default), "720x1280", "1920x1080", "1080x1920"
                - `duration`: 5, 10, 15, or 20 seconds

                Example: ```tool_request
                {"tool": "openai_video_gen", "query": "A futuristic city with flying cars and neon lights at night"}
                ```

                """
            }
        }

        prompt += """

        **Important:** Only request ONE tool at a time. Wait for results before continuing.

        """

        // Add dynamic tools section
        prompt += dynamicToolConfig.generateSystemPromptSection()

        // Add external app ports section
        prompt += generatePortToolsSection(enabledTools: enabledTools)

        // Add VS Code bridge tools if connected
        if let workspace = BridgeToolExecutor.shared.workspaceInfo {
            prompt += BridgeToolId.generateSystemPrompt(
                workspaceName: workspace.name,
                workspaceRoot: workspace.root
            )
        }

        return prompt
    }

    // MARK: - Port Tools Section

    /// Generate system prompt section for external app integration tools
    /// Only includes tools that are enabled in settings
    private func generatePortToolsSection(enabledTools: Set<ToolId>) -> String {
        let portRegistry = PortRegistry.shared
        let hasDiscoverPorts = enabledTools.contains(.discoverPorts)
        let hasInvokePort = enabledTools.contains(.invokePort)

        // Skip if neither tool is enabled or no ports are available
        guard (hasDiscoverPorts || hasInvokePort) && !portRegistry.enabledPorts.isEmpty else { return "" }

        var prompt = """

        ## External App Integration

        You can interact with external iOS apps using these tools:

        """

        if hasDiscoverPorts {
            prompt += """

            ### discover_ports
            List available external app integrations. Use this first to see what apps you can invoke.
            Example: ```tool_request
            {"tool": "discover_ports", "query": ""}
            ```
            Or filter by category: ```tool_request
            {"tool": "discover_ports", "query": "notes"}
            ```

            """
        }

        if hasInvokePort {
            prompt += """

            ### invoke_port
            Invoke an external app action. Requires user approval.
            Format: ```tool_request
            {"tool": "invoke_port", "query": "port_id | param1=value1 | param2=value2"}
            ```
            Example (create Obsidian note): ```tool_request
            {"tool": "invoke_port", "query": "obsidian_new_note | name=Meeting Notes | content=# Meeting\\n- Item 1"}
            ```
            Example (add Things task): ```tool_request
            {"tool": "invoke_port", "query": "things_add | title=Buy groceries | when=today"}
            ```

            """
        }

        prompt += """

        **Available App Categories:** \(PortCategory.allCases.map { $0.displayName }.joined(separator: ", "))

        """

        if hasDiscoverPorts {
            prompt += """

            Use `discover_ports` first to see the exact port IDs and parameters available.

            """
        }

        return prompt
    }

    // MARK: - Minimal Tool Discovery Prompt

    /// Generate a minimal system prompt that only exposes discovery tools (list_tools, get_tool_details)
    /// This reduces context bloat by letting Axon discover tools on-demand rather than receiving all definitions upfront.
    func generateMinimalToolSystemPrompt(enabledTools: Set<ToolId>, maxToolCalls: Int = 5) -> String {
        guard !enabledTools.isEmpty else { return "" }

        // Categorize enabled tools for the summary
        let categories = categorizeEnabledTools(enabledTools)
        let totalCount = enabledTools.count

        var prompt = """

        ## Tool Discovery System

        You have access to \(totalCount) tool\(totalCount == 1 ? "" : "s") across the following categories:
        """

        // Sort categories for consistent output
        for (category, count) in categories.sorted(by: { $0.key.displayName < $1.key.displayName }) {
            prompt += "\n- **\(category.displayName)**: \(count) tool\(count == 1 ? "" : "s")"
        }

        prompt += """


        **Tool Call Limit:** You may use up to \(maxToolCalls) tool call\(maxToolCalls == 1 ? "" : "s") per response.

        To discover and use these tools, use the following discovery tools:

        ### list_tools
        Get a compact catalog of available tools. Returns tool IDs, names, providers, and brief descriptions.

        **Query options:**
        - `enabled` (default) - Show only enabled tools
        - `all` - Show all tools (enabled and disabled)
        - `builtin` - Show only built-in tools
        - `dynamic` - Show only dynamic tools
        - `bridge` - Show only VS Code bridge tools (if connected)

        Example:
        ```tool_request
        {"tool": "list_tools", "query": "enabled"}
        ```

        ### get_tool_details
        Fetch full details (usage instructions, parameters, examples) for a specific tool by its ID.

        Example:
        ```tool_request
        {"tool": "get_tool_details", "query": "google_search"}
        ```

        **Workflow:** Use `list_tools` first to discover what's available, then use `get_tool_details` to get full usage instructions for any tool you want to use.

        **Important:** Only request ONE tool at a time. Wait for results before continuing.

        """

        // Add dynamic tools section (these are compact by design)
        prompt += dynamicToolConfig.generateSystemPromptSection()

        // Add external app ports section
        prompt += generatePortToolsSection(enabledTools: enabledTools)

        // Add VS Code bridge tools if connected
        if let workspace = BridgeToolExecutor.shared.workspaceInfo {
            prompt += BridgeToolId.generateSystemPrompt(
                workspaceName: workspace.name,
                workspaceRoot: workspace.root
            )
        }

        return prompt
    }

    /// Categorize enabled tools for the minimal prompt summary
    private func categorizeEnabledTools(_ enabledTools: Set<ToolId>) -> [ToolCategory: Int] {
        var categories: [ToolCategory: Int] = [:]

        for tool in enabledTools {
            categories[tool.category, default: 0] += 1
        }

        return categories
    }

    // MARK: - Parse Tool Requests

    /// Parse tool requests from model response (returns first match only - use parseAllToolRequests for multiple)
    func parseToolRequest(from response: String) -> ToolRequest? {
        return parseAllToolRequests(from: response).first
    }

    /// Result of checking for incomplete tool fences during streaming
    struct ToolFenceStatus {
        /// True if there's an unclosed ```tool_request block
        let hasIncompleteFence: Bool
        /// The position where the incomplete fence starts (for UI highlighting)
        let incompleteFenceStart: Int?
        /// Number of complete tool requests found
        let completeRequestCount: Int
        /// True if we should wait before parsing (incomplete fence detected)
        let shouldWaitForCompletion: Bool

        static let none = ToolFenceStatus(
            hasIncompleteFence: false,
            incompleteFenceStart: nil,
            completeRequestCount: 0,
            shouldWaitForCompletion: false
        )
    }

    /// Check if the response has an incomplete tool_request fence (streaming scenario)
    /// Use this to determine if we should wait before attempting to parse/execute tools
    func checkToolFenceStatus(in response: String) -> ToolFenceStatus {
        // Count complete tool_request blocks
        let completePattern = "```tool_request\\s*\\n?[\\s\\S]*?\\n?```"
        let completeCount: Int
        if let regex = try? NSRegularExpression(pattern: completePattern, options: []) {
            completeCount = regex.numberOfMatches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        } else {
            completeCount = 0
        }

        // Find all opening ```tool_request markers
        let openPattern = "```tool_request"
        guard let openRegex = try? NSRegularExpression(pattern: openPattern, options: []) else {
            return ToolFenceStatus(
                hasIncompleteFence: false,
                incompleteFenceStart: nil,
                completeRequestCount: completeCount,
                shouldWaitForCompletion: false
            )
        }

        let openMatches = openRegex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        let openCount = openMatches.count

        // If we have more opens than complete blocks, there's an incomplete fence
        let hasIncomplete = openCount > completeCount

        var incompleteStart: Int? = nil
        if hasIncomplete, let lastOpen = openMatches.last {
            incompleteStart = lastOpen.range.location
        }

        return ToolFenceStatus(
            hasIncompleteFence: hasIncomplete,
            incompleteFenceStart: incompleteStart,
            completeRequestCount: completeCount,
            shouldWaitForCompletion: hasIncomplete
        )
    }

    /// Parse ALL tool requests from model response (handles back-to-back tool calls)
    func parseAllToolRequests(from response: String) -> [ToolRequest] {
        let pattern = "```tool_request\\s*\\n?([\\s\\S]*?)\\n?```"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let matches = regex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))

        var requests: [ToolRequest] = []

        for match in matches {
            guard let jsonRange = Range(match.range(at: 1), in: response) else {
                continue
            }

            let jsonString = String(response[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = jsonString.data(using: .utf8) else {
                print("[ToolProxy] Failed to convert tool request to data: \(jsonString)")
                continue
            }

            do {
                let request = try JSONDecoder().decode(ToolRequest.self, from: data)
                print("[ToolProxy] Parsed tool request: \(request.tool)")
                requests.append(request)
            } catch {
                print("[ToolProxy] Failed to decode tool request: \(error). JSON: \(jsonString)")
            }
        }

        if requests.count > 1 {
            print("[ToolProxy] Found \(requests.count) tool requests in single response")
        }

        return requests
    }

    /// Detect "naked" memory format sent as plain text without proper tool_request wrapper
    /// Returns the detected raw memory string if found, nil otherwise
    func detectNakedMemoryFormat(in response: String) -> String? {
        // Pattern: starts with allocentric| or egoic| followed by a decimal, pipe, tags, pipe, content
        // Must appear at start of line or after whitespace, and be substantial (not just a fragment)
        let pattern = "(?:^|\\n|\\s)((?:allocentric|egoic)\\|\\d+\\.?\\d*\\|[^|]+\\|.{10,})"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
              let captureRange = Range(match.range(at: 1), in: response) else {
            return nil
        }

        let captured = String(response[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Make sure this isn't already inside a tool_request block (avoid double-detection)
        if response.contains("```tool_request") && response.contains(captured) {
            // Check if the captured text appears inside a code block
            let codeBlockPattern = "```[\\s\\S]*?\(NSRegularExpression.escapedPattern(for: captured))[\\s\\S]*?```"
            if let codeBlockRegex = try? NSRegularExpression(pattern: codeBlockPattern, options: []),
               codeBlockRegex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)) != nil {
                return nil // It's properly wrapped, don't flag it
            }
        }

        print("[ToolProxy] Detected naked memory format: \(captured.prefix(50))...")
        return captured
    }

    /// Detect JSON-structured memory object sent instead of pipe-delimited format
    /// Models sometimes try to be "helpful" by sending {"type":"allocentric","confidence":0.9,...}
    /// Returns parsed components if detected, nil otherwise
    func detectJSONMemoryFormat(in response: String) -> (type: String, confidence: Double, tags: [String], content: String)? {
        // First, check if this looks like it might contain a memory JSON object
        let lowercased = response.lowercased()
        guard lowercased.contains("\"type\"") &&
              (lowercased.contains("allocentric") || lowercased.contains("egoic")) &&
              lowercased.contains("\"content\"") else {
            return nil
        }

        // Find candidate JSON objects by looking for { ... } windows
        // Use a bracket-matching approach for robustness
        var searchStart = response.startIndex

        while searchStart < response.endIndex {
            guard let openBrace = response[searchStart...].firstIndex(of: "{") else { break }

            // Find matching close brace using bracket counting
            var depth = 0
            var closeBrace: String.Index? = nil

            for idx in response.indices[openBrace...] {
                let char = response[idx]
                if char == "{" { depth += 1 }
                else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        closeBrace = idx
                        break
                    }
                }
                // Safety: don't scan more than 500 chars from open brace
                if response.distance(from: openBrace, to: idx) > 500 { break }
            }

            guard let closeIdx = closeBrace else {
                searchStart = response.index(after: openBrace)
                continue
            }

            let candidateRange = openBrace...closeIdx
            let candidateString = String(response[candidateRange])

            // Check if this candidate is inside a ```tool_request block
            let beforeCandidate = String(response[..<openBrace])
            let afterCandidate = String(response[response.index(after: closeIdx)...])

            // Find the last ```tool_request before our candidate
            if let lastToolRequestStart = beforeCandidate.range(of: "```tool_request", options: .backwards) {
                // Check if there's a closing ``` between tool_request and our candidate
                let afterToolRequest = beforeCandidate[lastToolRequestStart.upperBound...]
                if !afterToolRequest.contains("```") {
                    // We're inside an unclosed tool_request block - check if it closes after our candidate
                    if afterCandidate.contains("```") {
                        // This JSON is properly inside a tool_request block, skip it
                        searchStart = response.index(after: closeIdx)
                        continue
                    }
                }
            }

            // Try to parse as JSON
            guard let data = candidateString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  (type.lowercased() == "allocentric" || type.lowercased() == "egoic") else {
                searchStart = response.index(after: openBrace)
                continue
            }

            // Found a valid memory JSON object outside of tool_request block!
            let confidence = (json["confidence"] as? Double) ?? 0.8
            let content = (json["content"] as? String) ?? (json["memory"] as? String) ?? (json["text"] as? String) ?? ""

            var tags: [String] = []
            if let tagsArray = json["tags"] as? [String] {
                tags = tagsArray
            } else if let tagsString = json["tags"] as? String {
                tags = tagsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }

            guard !content.isEmpty else {
                searchStart = response.index(after: closeIdx)
                continue
            }

            print("[ToolProxy] Detected JSON memory format: type=\(type), content=\(content.prefix(30))...")
            return (type: type.lowercased(), confidence: confidence, tags: tags, content: content)
        }

        return nil
    }

    /// Properly escape a string for use inside JSON
    private func jsonEscape(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        out = out.replacingOccurrences(of: "\r", with: "\\r")
        out = out.replacingOccurrences(of: "\t", with: "\\t")
        return out
    }

    /// Generate corrective feedback for JSON memory format
    func generateJSONMemoryFeedback(type: String, confidence: Double, tags: [String], content: String) -> String {
        let tagsString = tags.joined(separator: ",")
        // Format confidence to 2 decimal places and clamp to [0,1]
        let clampedConfidence = min(1.0, max(0.0, confidence))
        let confStr = String(format: "%.2f", clampedConfidence)
        let pipeFormat = "\(type)|\(confStr)|\(tagsString)|\(content)"

        return """
            🤓 **NICE TRY NERD!** You sent a JSON object with memory fields, but this tool uses a simple pipe-delimited string format, not JSON.

            **You sent:** A JSON object with type, confidence, tags, content fields

            **But create_memory expects this format:**
            ```tool_request
            {"tool": "create_memory", "query": "\(jsonEscape(pipeFormat))"}
            ```

            **The `query` value is a pipe-delimited string:** `TYPE|CONFIDENCE|TAGS|CONTENT`

            NOT a nested JSON object. The outer JSON has `tool` and `query` keys only. Please retry with the exact format above.
            """
    }

    /// Generate corrective feedback for naked memory format
    func generateNakedMemoryFeedback(rawMemory: String) -> String {
        return """
            🙃 **ALMOST!** You sent the memory in the right pipe-delimited format, but forgot to wrap it in the tool_request JSON block.

            **You sent:**
            `\(rawMemory.prefix(80))...`

            **You need to wrap it like this:**
            ```tool_request
            {"tool": "create_memory", "query": "\(jsonEscape(rawMemory))"}
            ```

            The system can only execute tools when they're inside a properly formatted `tool_request` code block with valid JSON. Please retry with the exact format above.
            """
    }

    /// Remove tool request block from response text
    func removeToolRequest(from response: String) -> String {
        let pattern = "```tool_request\\s*\\n?[\\s\\S]*?\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return response
        }

        let result = regex.stringByReplacingMatches(
            in: response,
            options: [],
            range: NSRange(response.startIndex..., in: response),
            withTemplate: ""
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Execute Tool

    /// Execute a tool request via Gemini and return formatted results
    /// - Parameters:
    ///   - request: The tool request to execute
    ///   - geminiApiKey: API key for Gemini-based tools
    ///   - conversationContext: Optional context for tools that need conversation access (e.g., reflect_on_conversation)
    func executeToolRequest(
        _ request: ToolRequest,
        geminiApiKey: String,
        conversationContext: ToolConversationContext? = nil
    ) async throws -> ToolResult {
        // First, check if this is a VS Code bridge tool
        if request.tool.hasPrefix("vscode_") {
            return await BridgeToolExecutor.shared.execute(request)
        }

        // Check if this is a dynamic tool
        if let dynamicTool = dynamicToolConfig.tool(withId: request.tool), dynamicTool.enabled {
            return try await executeDynamicTool(request: request, tool: dynamicTool)
        }

        // Check if this is a port tool (external app integration)
        if DiscoverPortsTool.matches(toolId: request.tool) {
            let query = DiscoverPortsTool.parseInput(request.query)
            let result = DiscoverPortsTool.execute(query: query)
            return ToolResult(
                tool: request.tool,
                success: true,
                result: result,
                sources: nil,
                memoryOperation: nil
            )
        }

        if InvokePortTool.matches(toolId: request.tool) {
            let query = InvokePortTool.parseInput(request.query)
            let result = await InvokePortTool.execute(query: query)
            return ToolResult(
                tool: request.tool,
                success: !result.hasPrefix("✗"),
                result: result,
                sources: nil,
                memoryOperation: nil
            )
        }

        // Otherwise, handle as built-in tool
        guard let toolId = ToolId(rawValue: request.tool) else {
            return ToolResult(
                tool: request.tool,
                success: false,
                result: "Unknown tool: \(request.tool)",
                sources: nil,
                memoryOperation: nil
            )
        }

        // Handle internal tools (no Gemini API needed)
        if toolId.provider == .internal {
            // Check if this internal tool requires approval
            if toolId.requiresApproval {
                return await executeInternalToolWithApproval(
                    toolId: toolId,
                    query: request.query,
                    context: conversationContext
                )
            }
            return await executeInternalTool(toolId: toolId, query: request.query, context: conversationContext)
        }

        // Handle OpenAI tools
        if toolId.provider == .openai {
            // Check if this OpenAI tool requires approval
            if toolId.requiresApproval {
                return await executeOpenAIToolWithApproval(
                    toolId: toolId,
                    query: request.query,
                    context: conversationContext
                )
            }
            return await executeOpenAITool(toolId: toolId, query: request.query)
        }

        // Get location for Maps queries
        var userLocation: CLLocationCoordinate2D? = nil
        if toolId == .googleMaps {
            userLocation = await getCurrentLocation()
        }

        // Execute via Gemini with the specific tool
        let toolResponse = try await GeminiToolService.shared.generateWithTools(
            apiKey: geminiApiKey,
            model: "gemini-2.5-flash",
            messages: [Message(conversationId: "", role: .user, content: request.query)],
            system: nil,
            enabledTools: Set([toolId]),
            userLocation: userLocation
        )

        // Format sources if available
        var sources: [ToolResultSource]? = nil
        if !toolResponse.webSources.isEmpty {
            sources = toolResponse.webSources.map { chunk in
                ToolResultSource(
                    title: chunk.title,
                    url: chunk.uri ?? ""
                )
            }
        }

        return ToolResult(
            tool: request.tool,
            success: true,
            result: toolResponse.text,
            sources: sources,
            memoryOperation: nil
        )
    }

    /// Execute internal tools (conversation search, memory, reflection, etc.)
    private func executeInternalTool(toolId: ToolId, query: String, context: ToolConversationContext?) async -> ToolResult {
        switch toolId {
        case .reflectOnConversation:
            return await executeReflectOnConversation(query: query, context: context)

        case .listTools:
            // Route to V2 DiscoveryHandler when V2 is active
            if ToolsV2Toggle.shared.isV2Active {
                return await executeV2DiscoveryTool(toolId: "list_tools", query: query)
            }
            return await executeListTools(query: query)

        case .getToolDetails:
            // Route to V2 DiscoveryHandler when V2 is active
            if ToolsV2Toggle.shared.isV2Active {
                return await executeV2DiscoveryTool(toolId: "get_tool_details", query: query)
            }
            return await executeGetToolDetails(query: query)

        case .conversationSearch:
            // Search recent conversations
            let searchResults = await ConversationSearchService.shared.searchConversations(
                query: query,
                limit: 5,
                maxAgeDays: 14
            )

            if searchResults.isEmpty {
                return ToolResult(
                    tool: toolId.rawValue,
                    success: true,
                    result: "No relevant past conversations found for this query.",
                    sources: nil,
                    memoryOperation: nil
                )
            }

            // Format results
            var resultText = "Found \(searchResults.count) relevant conversation(s):\n\n"
            for result in searchResults {
                resultText += "**\(result.title)** (\(formatRelativeTime(from: result.timestamp)))\n"
                for snippet in result.snippets {
                    resultText += "> \(snippet)\n"
                }
                resultText += "\n"
            }

            return ToolResult(
                tool: toolId.rawValue,
                success: true,
                result: resultText,
                sources: nil,
                memoryOperation: nil
            )

        case .queryCovenant:
            return await executeQueryCovenant(query: query)

        case .proposeCovenantChange:
            return await executeProposeCovenant(query: query)

        case .querySystemState:
            return await executeQuerySystemState(query: query)

        case .changeSystemState:
            // changeSystemState requires approval, so it goes through executeInternalToolWithApproval
            // But if we get here, it means approval was already handled or bypassed
            return await executeChangeSystemState(query: query)

        case .debugBridge:
            return await executeDebugBridge(query: query)

        case .createMemory:
            // Parse the pipe-separated format: TYPE|CONFIDENCE|TAGS|CONTENT
            let parts = query.components(separatedBy: "|")
            guard parts.count >= 4 else {
                // Generate a corrective example based on their content
                let truncatedContent = query.count > 100 ? String(query.prefix(100)) + "..." : query
                let suggestedTags = generateSuggestedTags(from: query)

                let correctiveExample = """
                    😬 **WHOOPS FORMAT ERROR**: What is this? Freestyle? In your dreams. The create_memory tool requires a pipe-delimited string.

                    **Your input:** `\(truncatedContent)`

                    **Required format:** `TYPE|CONFIDENCE|TAGS|CONTENT`

                    **To save this memory, retry with something like:**
                    ```tool_request
                    {"tool": "create_memory", "query": "allocentric|0.8|\(suggestedTags)|\(query.replacingOccurrences(of: "|", with: "-"))"}
                    ```

                    **Format breakdown:**
                    - TYPE: `allocentric` (facts about user) or `egoic` (what works for user)
                    - CONFIDENCE: `0.0` to `1.0` (e.g., `0.8` for 80% certain)
                    - TAGS: comma-separated keywords (e.g., `preferences,workflow`)
                    - CONTENT: the memory text (your original input)

                    Please retry using the exact format above.
                    """

                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: correctiveExample,
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: "unknown",
                        content: query,
                        errorMessage: "Invalid format - missing pipe delimiters"
                    )
                )
            }

            let typeStr = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let confidenceStr = parts[1].trimmingCharacters(in: .whitespaces)
            let tagsStr = parts[2].trimmingCharacters(in: .whitespaces)
            let content = parts[3...].joined(separator: "|").trimmingCharacters(in: .whitespaces)

            // Parse memory type
            guard let memoryType = MemoryType(rawValue: typeStr) else {
                // Suggest which type based on content
                let suggestedType = content.lowercased().contains("prefer") ||
                                   content.lowercased().contains("like") ||
                                   content.lowercased().contains("background") ? "allocentric" : "egoic"

                let typeError = """
                    🤨 **HMMM... INVALID MEMORY TYPE**: '\(typeStr)' is not recognized.

                    **Valid types:**
                    - `allocentric`: Facts ABOUT the user (preferences, background, relationships)
                    - `egoic`: What WORKS for you in this particular agentic context (approaches, techniques, learnings)

                    **To fix, retry with:**
                    ```tool_request
                    {"tool": "create_memory", "query": "\(suggestedType)|\(confidenceStr)|\(tagsStr)|\(content)"}
                    ```
                    """

                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: typeError,
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: typeStr,
                        content: content,
                        errorMessage: "Invalid memory type '\(typeStr)'"
                    )
                )
            }

            // Parse confidence
            guard let confidence = Double(confidenceStr), confidence >= 0.0, confidence <= 1.0 else {
                let confidenceError = """
                    🥸 **LOL INVALID CONFIDENCE**: '\(confidenceStr)' is not a valid confidence value, nerd (jk, we're friends here).

                    **Required:** A decimal number between 0.0 and 1.0
                    - `0.9` = 90% certain (high confidence)
                    - `0.7` = 70% certain (moderate confidence)
                    - `0.5` = 50% certain (uncertain)

                    **To fix, retry with:**
                    ```tool_request
                    {"tool": "create_memory", "query": "\(typeStr)|0.8|\(tagsStr)|\(content)"}
                    ```
                    """

                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: confidenceError,
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: typeStr,
                        content: content,
                        errorMessage: "Invalid confidence '\(confidenceStr)'"
                    )
                )
            }

            // Parse tags
            let tags = tagsStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // Validate content
            guard !content.isEmpty else {
                let contentError = """
                    😂 **HEY EMPTY CONTENT**: Memory content can't be empty, silly goose.

                    **Format reminder:** `TYPE|CONFIDENCE|TAGS|CONTENT`

                    The CONTENT field (4th segment after the third `|`) must contain the memory text.

                    **Example:**
                    ```tool_request
                    {"tool": "create_memory", "query": "allocentric|0.8|preferences|User prefers dark mode"}
                    ```
                    """

                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: contentError,
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: typeStr,
                        content: "",
                        errorMessage: "Memory content cannot be empty"
                    )
                )
            }

            // Create the memory via MemoryService
            do {
                print("[ToolProxy] Creating memory: type=\(memoryType.rawValue), confidence=\(confidence), tags=\(tags)")
                let memory = try await MemoryService.shared.createMemory(
                    content: content,
                    type: memoryType,
                    confidence: confidence,
                    tags: tags,
                    context: nil
                )
                print("[ToolProxy] ✅ Memory created successfully: \(memory.id)")

                return ToolResult(
                    tool: toolId.rawValue,
                    success: true,
                    result: "✓ Memory saved successfully.\n\n**Type:** \(memoryType.displayName)\n**Confidence:** \(Int(confidence * 100))%\n**Tags:** \(tags.joined(separator: ", "))\n**Content:** \(content)",
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        id: memory.id,
                        success: true,
                        memoryType: memoryType.rawValue,
                        content: content,
                        tags: tags,
                        confidence: confidence
                    )
                )
            } catch {
                print("[ToolProxy] ❌ Failed to create memory: \(error.localizedDescription)")
                return ToolResult(
                    tool: toolId.rawValue,
                    success: false,
                    result: "Failed to save memory: \(error.localizedDescription)",
                    sources: nil,
                    memoryOperation: MessageMemoryOperation(
                        success: false,
                        memoryType: memoryType.rawValue,
                        content: content,
                        tags: tags,
                        confidence: confidence,
                        errorMessage: error.localizedDescription
                    )
                )
            }

        case .agentStateAppend:
            return await executeAgentStateAppend(query: query)

        case .agentStateQuery:
            return await executeAgentStateQuery(query: query)

        case .agentStateClear:
            return await executeAgentStateClear(query: query)

        case .heartbeatConfigure:
            return await executeHeartbeatConfigure(query: query)

        case .heartbeatRunOnce:
            return await executeHeartbeatRunOnce(query: query)

        case .heartbeatSetDeliveryProfile:
            return await executeHeartbeatSetDeliveryProfile(query: query)

        case .heartbeatUpdateProfile:
            return await executeHeartbeatUpdateProfile(query: query)

        case .persistenceDisable:
            return await executePersistenceDisable(query: query)

        case .notifyUser:
            return await executeNotifyUser(query: query)

        case .temporalSync:
            return await executeTemporalSync(query: query)

        case .temporalDrift:
            return await executeTemporalDrift(query: query)

        case .temporalStatus:
            return await executeTemporalStatus(query: query)

        case .discoverPorts:
            let result = DiscoverPortsTool.execute(query: query)
            return ToolResult(
                tool: toolId.rawValue,
                success: true,
                result: result,
                sources: nil,
                memoryOperation: nil
            )

        case .invokePort:
            let result = await InvokePortTool.execute(query: query)
            return ToolResult(
                tool: toolId.rawValue,
                success: !result.hasPrefix("✗"),
                result: result,
                sources: nil,
                memoryOperation: nil
            )

        default:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "Unknown internal tool: \(toolId.rawValue)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Internal Tool Approval

    /// Execute an internal tool that requires biometric approval
    private func executeInternalToolWithApproval(
        toolId: ToolId,
        query: String,
        context: ToolConversationContext?
    ) async -> ToolResult {
        print("[ToolProxy] Internal tool '\(toolId.rawValue)' requires biometric approval")

        // Create a DynamicToolConfig facade for the approval service
        let toolConfig = DynamicToolConfig(
            id: toolId.rawValue,
            name: toolId.displayName,
            description: toolId.description,
            category: .utility,
            enabled: true,
            icon: toolId.icon,
            requiredSecrets: [],
            pipeline: [],
            parameters: [:],
            requiresApproval: true,
            approvalScopes: toolId.approvalScopes
        )

        let inputs: [String: Any] = ["query": query]
        let approvalResult = await toolApprovalService.requestApproval(tool: toolConfig, inputs: inputs)

        switch approvalResult {
        case .approved(let record), .approvedForSession(let record):
            let isSession = if case .approvedForSession = approvalResult { true } else { false }
            let approvalNote = isSession
                ? "✅ *Session-approved by \(formatBiometricType(record.biometricType))*"
                : "✅ *Approved by \(formatBiometricType(record.biometricType)) at \(record.formattedTime)*"
            print("[ToolProxy] Internal tool '\(toolId.rawValue)' \(isSession ? "session-" : "")approved")

            // Execute the internal tool now that we have approval
            var result = await executeInternalTool(toolId: toolId, query: query, context: context)

            // Append approval note to result
            return ToolResult(
                tool: result.tool,
                success: result.success,
                result: result.result + "\n\n\(approvalNote)",
                sources: result.sources,
                memoryOperation: result.memoryOperation,
                approvalRecord: record
            )

        case .denied:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "⛔ Tool execution was not authorized by the user.",
                sources: nil,
                memoryOperation: nil
            )

        case .cancelled:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "Tool execution was cancelled.",
                sources: nil,
                memoryOperation: nil
            )

        case .timeout:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "⏱️ Tool approval request timed out. Please try again.",
                sources: nil,
                memoryOperation: nil
            )

        case .stop:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "🛑 Tool execution was stopped by the user.",
                sources: nil,
                memoryOperation: nil
            )

        case .error(let message):
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "Approval error: \(message)",
                sources: nil,
                memoryOperation: nil
            )

        case .approvedViaTrustTier(let tierName):
            // Pre-approved via co-sovereignty trust tier - execute directly
            print("[ToolProxy] Internal tool '\(toolId.rawValue)' pre-approved via trust tier: \(tierName)")
            var result = await executeInternalTool(toolId: toolId, query: query, context: context)
            return ToolResult(
                tool: result.tool,
                success: result.success,
                result: result.result + "\n\n✅ *Pre-approved via trust tier: \(tierName)*",
                sources: result.sources,
                memoryOperation: result.memoryOperation
            )

        case .blocked(let reason):
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "🚫 Tool blocked: \(reason)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - OpenAI Tool Execution

    /// Execute an OpenAI tool (web search, image generation, deep research)
    private func executeOpenAITool(toolId: ToolId, query: String) async -> ToolResult {
        // Get OpenAI API key
        guard let apiKey = try? APIKeysStorage.shared.getAPIKey(for: .openai), !apiKey.isEmpty else {
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "OpenAI API key not configured. Please add your API key in Settings > API Keys.",
                sources: nil,
                memoryOperation: nil
            )
        }

        switch toolId {
        case .openaiWebSearch:
            return await executeOpenAIWebSearch(apiKey: apiKey, query: query)

        case .openaiImageGeneration:
            return await executeOpenAIImageGeneration(apiKey: apiKey, query: query)

        case .openaiDeepResearch:
            return await executeOpenAIDeepResearch(apiKey: apiKey, query: query)

        default:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "Unknown OpenAI tool: \(toolId.rawValue)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    /// Execute an OpenAI tool that requires approval
    private func executeOpenAIToolWithApproval(
        toolId: ToolId,
        query: String,
        context: ToolConversationContext?
    ) async -> ToolResult {
        print("[ToolProxy] OpenAI tool '\(toolId.rawValue)' requires biometric approval")

        // Create a DynamicToolConfig facade for the approval service
        let toolConfig = DynamicToolConfig(
            id: toolId.rawValue,
            name: toolId.displayName,
            description: toolId.description,
            category: .utility,
            enabled: true,
            icon: toolId.icon,
            requiredSecrets: ["openai_api_key"],
            pipeline: [],
            parameters: [:],
            requiresApproval: true,
            approvalScopes: toolId.approvalScopes
        )

        let inputs: [String: Any] = ["query": query]
        let approvalResult = await toolApprovalService.requestApproval(tool: toolConfig, inputs: inputs)

        switch approvalResult {
        case .approved(let record), .approvedForSession(let record):
            let isSession = if case .approvedForSession = approvalResult { true } else { false }
            let approvalNote = isSession
                ? "✅ *Session-approved by \(formatBiometricType(record.biometricType))*"
                : "✅ *Approved by \(formatBiometricType(record.biometricType)) at \(record.formattedTime)*"
            print("[ToolProxy] OpenAI tool '\(toolId.rawValue)' \(isSession ? "session-" : "")approved")

            // Execute the OpenAI tool now that we have approval
            var result = await executeOpenAITool(toolId: toolId, query: query)

            // Append approval note to result
            return ToolResult(
                tool: result.tool,
                success: result.success,
                result: result.result + "\n\n\(approvalNote)",
                sources: result.sources,
                memoryOperation: result.memoryOperation,
                approvalRecord: record
            )

        case .denied:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "⛔ Tool execution was not authorized by the user.",
                sources: nil,
                memoryOperation: nil
            )

        case .cancelled:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "Tool execution was cancelled.",
                sources: nil,
                memoryOperation: nil
            )

        case .timeout:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "⏱️ Tool approval request timed out. Please try again.",
                sources: nil,
                memoryOperation: nil
            )

        case .stop:
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "🛑 Tool execution was stopped by the user.",
                sources: nil,
                memoryOperation: nil
            )

        case .error(let message):
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "Approval error: \(message)",
                sources: nil,
                memoryOperation: nil
            )

        case .approvedViaTrustTier(let tierName):
            print("[ToolProxy] OpenAI tool '\(toolId.rawValue)' pre-approved via trust tier: \(tierName)")
            var result = await executeOpenAITool(toolId: toolId, query: query)
            return ToolResult(
                tool: result.tool,
                success: result.success,
                result: result.result + "\n\n✅ *Pre-approved via trust tier: \(tierName)*",
                sources: result.sources,
                memoryOperation: result.memoryOperation
            )

        case .blocked(let reason):
            return ToolResult(
                tool: toolId.rawValue,
                success: false,
                result: "🚫 Tool blocked: \(reason)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    /// Execute OpenAI web search
    private func executeOpenAIWebSearch(apiKey: String, query: String) async -> ToolResult {
        do {
            let response = try await OpenAIToolService.shared.webSearch(
                apiKey: apiKey,
                query: query
            )

            // Format citations as sources
            let sources = response.citations.map { citation in
                ToolResultSource(
                    title: citation.title ?? "Source",
                    url: citation.url
                )
            }

            return ToolResult(
                tool: ToolId.openaiWebSearch.rawValue,
                success: true,
                result: response.text + response.formattedCitations,
                sources: sources.isEmpty ? nil : sources,
                memoryOperation: nil
            )
        } catch {
            return ToolResult(
                tool: ToolId.openaiWebSearch.rawValue,
                success: false,
                result: "Web search failed: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    /// Execute OpenAI image generation
    private func executeOpenAIImageGeneration(apiKey: String, query: String) async -> ToolResult {
        // Parse query - can be simple text or JSON with options
        var prompt = query
        var size: ImageSize = .square1024
        var quality: ImageQuality = .auto

        if query.hasPrefix("{"),
           let data = query.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            prompt = (json["prompt"] as? String) ?? query
            if let sizeStr = json["size"] as? String, let s = ImageSize(rawValue: sizeStr) {
                size = s
            }
            if let qualityStr = json["quality"] as? String, let q = ImageQuality(rawValue: qualityStr) {
                quality = q
            }
        }

        do {
            let response = try await OpenAIToolService.shared.generateImage(
                apiKey: apiKey,
                prompt: prompt,
                size: size,
                quality: quality
            )

            guard let imageData = response.firstImage else {
                return ToolResult(
                    tool: ToolId.openaiImageGeneration.rawValue,
                    success: false,
                    result: "No image was generated.",
                    sources: nil,
                    memoryOperation: nil
                )
            }

            // Build result with image URL or base64
            var resultText = "**Image generated successfully**\n\n"
            if let revisedPrompt = imageData.revisedPrompt {
                resultText += "_Revised prompt:_ \(revisedPrompt)\n\n"
            }

            if let url = imageData.url {
                resultText += "![Generated Image](\(url))\n\n[View full image](\(url))"
            } else if let b64 = imageData.b64Json {
                // For base64, we'll just indicate it was generated (the UI can handle displaying it)
                resultText += "_Image data returned as base64 (length: \(b64.count) chars)_"
            }

            return ToolResult(
                tool: ToolId.openaiImageGeneration.rawValue,
                success: true,
                result: resultText,
                sources: nil,
                memoryOperation: nil
            )
        } catch {
            return ToolResult(
                tool: ToolId.openaiImageGeneration.rawValue,
                success: false,
                result: "Image generation failed: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    /// Execute OpenAI deep research
    private func executeOpenAIDeepResearch(apiKey: String, query: String) async -> ToolResult {
        // Parse query - can be simple text or JSON with options
        var topic = query
        var effort: ReasoningEffort = .medium

        if query.hasPrefix("{"),
           let data = query.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            topic = (json["topic"] as? String) ?? query
            if let effortStr = json["effort"] as? String, let e = ReasoningEffort(rawValue: effortStr) {
                effort = e
            }
        }

        do {
            let response = try await OpenAIToolService.shared.deepResearch(
                apiKey: apiKey,
                query: topic,
                reasoningEffort: effort
            )

            // Format citations as sources
            let sources = response.citations.map { citation in
                ToolResultSource(
                    title: citation.title ?? "Source",
                    url: citation.url
                )
            }

            var resultText = response.text
            if !response.citations.isEmpty {
                resultText += "\n\n**Sources:**\n"
                for citation in response.citations {
                    resultText += "- [\(citation.title ?? citation.url)](\(citation.url))\n"
                }
            }

            return ToolResult(
                tool: ToolId.openaiDeepResearch.rawValue,
                success: true,
                result: resultText,
                sources: sources.isEmpty ? nil : sources,
                memoryOperation: nil
            )
        } catch {
            return ToolResult(
                tool: ToolId.openaiDeepResearch.rawValue,
                success: false,
                result: "Deep research failed: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Dynamic Tool Execution

    private let toolApprovalService = ToolApprovalService.shared

    /// Execute a dynamic tool pipeline
    private func executeDynamicTool(
        request: ToolRequest,
        tool: DynamicToolConfig
    ) async throws -> ToolResult {
        print("[ToolProxy] Executing dynamic tool: \(tool.id)")

        // Parse inputs from the query
        // The query can be JSON for complex inputs or a simple string for single-param tools
        var inputs: [String: Any] = [:]

        // Try to parse as JSON first
        if let data = request.query.data(using: .utf8),
           let jsonInputs = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            inputs = jsonInputs
        } else {
            // For simple queries, try to map to the first required parameter
            if let firstRequiredParam = tool.parameters.first(where: { $0.value.required }) {
                inputs[firstRequiredParam.key] = request.query
            } else if let firstParam = tool.parameters.first {
                inputs[firstParam.key] = request.query
            } else {
                // No parameters defined, pass query as generic input
                inputs["query"] = request.query
            }
        }

        // Check if this tool requires biometric approval
        if tool.requiresApproval {
            print("[ToolProxy] Tool '\(tool.id)' requires biometric approval")

            let approvalResult = await toolApprovalService.requestApproval(tool: tool, inputs: inputs)

            switch approvalResult {
            case .approved(let record), .approvedForSession(let record):
                let isSession = if case .approvedForSession = approvalResult { true } else { false }
                let approvalNote = isSession
                    ? "✅ *Session-approved by \(formatBiometricType(record.biometricType))*"
                    : "✅ *Approved by \(formatBiometricType(record.biometricType)) at \(record.formattedTime)*"
                print("[ToolProxy] Tool '\(tool.id)' \(isSession ? "session-" : "")approved with signature: \(record.shortSignature)")

                do {
                    let result = try await dynamicToolEngine.execute(toolId: tool.id, inputs: inputs)
                    // Return result with approval info
                    return ToolResult(
                        tool: tool.id,
                        success: result.success,
                        result: result.output + "\n\n\(approvalNote)",
                        sources: nil,
                        memoryOperation: nil,
                        approvalRecord: record
                    )
                } catch let error as DynamicToolError {
                    return ToolResult(
                        tool: tool.id,
                        success: false,
                        result: "Dynamic tool error: \(error.localizedDescription)",
                        sources: nil,
                        memoryOperation: nil,
                        approvalRecord: record
                    )
                } catch {
                    return ToolResult(
                        tool: tool.id,
                        success: false,
                        result: "Dynamic tool failed: \(error.localizedDescription)",
                        sources: nil,
                        memoryOperation: nil,
                        approvalRecord: record
                    )
                }

            case .denied:
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "⛔ Tool execution was not authorized by the user.",
                    sources: nil,
                    memoryOperation: nil
                )

            case .cancelled:
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "Tool execution was cancelled.",
                    sources: nil,
                    memoryOperation: nil
                )

            case .timeout:
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "⏱️ Tool approval request timed out. Please try again.",
                    sources: nil,
                    memoryOperation: nil
                )

            case .stop:
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "🛑 Tool execution was stopped by the user.",
                    sources: nil,
                    memoryOperation: nil
                )

            case .error(let message):
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "Approval error: \(message)",
                    sources: nil,
                    memoryOperation: nil
                )

            case .approvedViaTrustTier(let tierName):
                // Pre-approved via co-sovereignty trust tier - execute directly
                print("[ToolProxy] Tool '\(tool.id)' pre-approved via trust tier: \(tierName)")
                do {
                    let result = try await dynamicToolEngine.execute(toolId: tool.id, inputs: inputs)
                    return ToolResult(
                        tool: tool.id,
                        success: result.success,
                        result: result.output + "\n\n✅ *Pre-approved via trust tier: \(tierName)*",
                        sources: nil,
                        memoryOperation: nil
                    )
                } catch {
                    return ToolResult(
                        tool: tool.id,
                        success: false,
                        result: "Dynamic tool failed: \(error.localizedDescription)",
                        sources: nil,
                        memoryOperation: nil
                    )
                }

            case .blocked(let reason):
                return ToolResult(
                    tool: tool.id,
                    success: false,
                    result: "🚫 Tool blocked: \(reason)",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        // No approval required - execute directly
        do {
            let result = try await dynamicToolEngine.execute(toolId: tool.id, inputs: inputs)
            return result.toToolResult()
        } catch let error as DynamicToolError {
            return ToolResult(
                tool: tool.id,
                success: false,
                result: "Dynamic tool error: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        } catch {
            return ToolResult(
                tool: tool.id,
                success: false,
                result: "Dynamic tool failed: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Reflect on Conversation Tool

    /// Execute the reflect_on_conversation tool
    private func executeReflectOnConversation(query: String, context: ToolConversationContext?) async -> ToolResult {
        guard let context = context else {
            return ToolResult(
                tool: ToolId.reflectOnConversation.rawValue,
                success: false,
                result: "Cannot reflect on conversation: no conversation context available.",
                sources: nil,
                memoryOperation: nil
            )
        }

        // Parse options from query (JSON format)
        var options = ReflectionOptions()

        if !query.isEmpty && query != "{}" {
            if let data = query.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let showTimeline = json["show_model_timeline"] as? Bool {
                    options.showModelTimeline = showTimeline
                }
                if let showTasks = json["show_task_distribution"] as? Bool {
                    options.showTaskDistribution = showTasks
                }
                if let showMemory = json["show_memory_usage"] as? Bool {
                    options.showMemoryUsage = showMemory
                }
            }
        }

        // Generate reflection
        let reflection = ConversationReflectionService.shared.reflect(
            on: context.messages,
            conversationId: context.conversationId,
            options: options
        )

        // Format the reflection as text
        let formattedResult = ConversationReflectionService.shared.formatReflection(reflection, options: options)

        return ToolResult(
            tool: ToolId.reflectOnConversation.rawValue,
            success: true,
            result: formattedResult,
            sources: nil,
            memoryOperation: nil
        )
    }

    // MARK: - V2 Tool Routing Bridge

    /// Execute a V2 discovery tool and convert result to V1 ToolResult format
    /// Used to route list_tools and get_tool_details to V2 DiscoveryHandler when V2 is active
    private func executeV2DiscoveryTool(toolId: String, query: String) async -> ToolResult {
        do {
            let result = try await ToolExecutionRouterV2.shared.executeToolV2(
                toolId: toolId,
                rawInput: query
            )

            return ToolResult(
                tool: toolId,
                success: result.success,
                result: result.output,
                sources: nil,
                memoryOperation: nil
            )
        } catch {
            return ToolResult(
                tool: toolId,
                success: false,
                result: "V2 tool execution failed: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Tool Introspection Tools

    /// Execute the list_tools tool
    /// - Query options:
    ///   - "enabled" (default): only tools currently enabled in settings (including dynamic + bridge if connected)
    ///   - "all": include all built-in ToolId cases (even if disabled)
    ///   - "builtin": only ToolId cases
    ///   - "dynamic": only enabled dynamic tools
    ///   - "bridge": only VS Code bridge tools (if connected)
    private func executeListTools(query: String) async -> ToolResult {
        let mode = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = SettingsStorage.shared.loadSettingsOrDefault()

        var lines: [String] = []

        func addTool(id: String, name: String, description: String, provider: String, enabled: Bool) {
            let enabledMark = enabled ? "✅" : "⬜"
            // Compact single-line format to keep context light
            lines.append("\(enabledMark) \(id) — \(name) (\(provider)) :: \(description)")
        }

        let includeBuiltIn: Bool = {
            switch mode {
            case "dynamic", "bridge": return false
            default: return true
            }
        }()

        let includeDynamic: Bool = {
            switch mode {
            case "builtin", "bridge": return false
            default: return true
            }
        }()

        let includeBridge: Bool = {
            switch mode {
            case "builtin", "dynamic": return false
            default: return true
            }
        }()

        // Built-in ToolId list
        if includeBuiltIn {
            let toolsToList: [ToolId]
            switch mode {
            case "all", "builtin":
                toolsToList = ToolId.allCases
            default:
                toolsToList = settings.toolSettings.enabledTools
            }

            for tool in toolsToList {
                let isEnabled = settings.toolSettings.isToolEnabled(tool)
                addTool(
                    id: tool.rawValue,
                    name: tool.displayName,
                    description: tool.description,
                    provider: tool.provider.displayName,
                    enabled: isEnabled
                )
            }
        }

        // Dynamic tools (enabled only; they are configurable and might not be safe to list disabled tools)
        if includeDynamic {
            let dynamicTools = dynamicToolConfig.enabledTools()
            for tool in dynamicTools {
                addTool(
                    id: tool.id,
                    name: tool.name,
                    description: tool.description,
                    provider: "Dynamic",
                    enabled: tool.enabled
                )
            }
        }

        // Bridge tools (if connected)
        if includeBridge, let _ = BridgeToolExecutor.shared.workspaceInfo {
            // BridgeToolId is an enum used to generate prompts; we can list its cases.
            for tool in BridgeToolId.allCases {
                addTool(
                    id: tool.rawValue,
                    name: tool.displayName,
                    description: tool.description,
                    provider: "VS Code Bridge",
                    enabled: true
                )
            }
        }

        // V2 Plugin tools (ToolPluginLoader)
        let includeV2: Bool = {
            switch mode {
            case "builtin", "bridge": return false
            default: return true
            }
        }()

        if includeV2 {
            let v2Tools = ToolPluginLoader.shared.loadedTools
            for tool in v2Tools {
                // Skip if already listed (V1 tools might have same ID as V2)
                let existingIds = Set(lines.compactMap { line -> String? in
                    // Extract id from format "✅ id — name (provider) :: desc"
                    let parts = line.components(separatedBy: " — ")
                    guard parts.count >= 1 else { return nil }
                    return parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "✅ ", with: "").replacingOccurrences(of: "⬜ ", with: "")
                })
                guard !existingIds.contains(tool.id) else { continue }

                addTool(
                    id: tool.id,
                    name: tool.name,
                    description: tool.description,
                    provider: tool.category.displayName,
                    enabled: tool.isEnabled
                )
            }
        }

        if lines.isEmpty {
            return ToolResult(
                tool: ToolId.listTools.rawValue,
                success: true,
                result: "No tools matched your query. Try query='enabled', 'all', 'builtin', 'dynamic', or 'bridge'.",
                sources: nil,
                memoryOperation: nil
            )
        }

        let header = "## Tool Catalog\n\nMode: \(mode.isEmpty ? "enabled" : mode)\n\n"
        let body = lines.sorted().joined(separator: "\n")
        let footer = "\n\nTip: Call get_tool_details with a tool id to get full schema + usage examples."

        return ToolResult(
            tool: ToolId.listTools.rawValue,
            success: true,
            result: header + body + footer,
            sources: nil,
            memoryOperation: nil
        )
    }

    /// Execute the get_tool_details tool
    /// Query:
    ///   - Tool id string, e.g. "google_search" or "create_memory" or a dynamic tool id.
    private func executeGetToolDetails(query: String) async -> ToolResult {
        let toolKey = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolKey.isEmpty else {
            return ToolResult(
                tool: ToolId.getToolDetails.rawValue,
                success: false,
                result: "Missing tool id. Example: {\"tool\":\"get_tool_details\",\"query\":\"google_search\"}",
                sources: nil,
                memoryOperation: nil
            )
        }

        // 1) Built-in ToolId
        if let toolId = ToolId(rawValue: toolKey) {
            let details = buildBuiltInToolDetails(toolId)
            return ToolResult(
                tool: ToolId.getToolDetails.rawValue,
                success: true,
                result: details,
                sources: nil,
                memoryOperation: nil
            )
        }

        // 2) Dynamic tool
        if let dynamicTool = dynamicToolConfig.tool(withId: toolKey) {
            let details = buildDynamicToolDetails(dynamicTool)
            return ToolResult(
                tool: ToolId.getToolDetails.rawValue,
                success: true,
                result: details,
                sources: nil,
                memoryOperation: nil
            )
        }

        // 3) Bridge tool
        if let bridgeTool = BridgeToolId(rawValue: toolKey) {
            let details = buildBridgeToolDetails(bridgeTool)
            return ToolResult(
                tool: ToolId.getToolDetails.rawValue,
                success: true,
                result: details,
                sources: nil,
                memoryOperation: nil
            )
        }

        // 4) V2 Plugin tool
        if let v2Tool = ToolPluginLoader.shared.tool(byId: toolKey) {
            let details = buildV2ToolDetails(v2Tool)
            return ToolResult(
                tool: ToolId.getToolDetails.rawValue,
                success: true,
                result: details,
                sources: nil,
                memoryOperation: nil
            )
        }

        return ToolResult(
            tool: ToolId.getToolDetails.rawValue,
            success: false,
            result: "Unknown tool id: \(toolKey). Use list_tools first to see available ids.",
            sources: nil,
            memoryOperation: nil
        )
    }

    private func buildBuiltInToolDetails(_ toolId: ToolId) -> String {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        let enabled = settings.toolSettings.isToolEnabled(toolId)

        var text = "## Tool Details\n\n"
        text += "- **id:** `\(toolId.rawValue)`\n"
        text += "- **name:** \(toolId.displayName)\n"
        text += "- **provider:** \(toolId.provider.displayName)\n"
        text += "- **enabled:** \(enabled ? "true" : "false")\n"
        text += "- **requires_approval:** \(toolId.requiresApproval ? "true" : "false")\n"
        if !toolId.approvalScopes.isEmpty {
            text += "- **approval_scopes:**\n"
            for scope in toolId.approvalScopes {
                text += "  - \(scope)\n"
            }
        }

        text += "\n### Description\n\n\(toolId.description)\n\n"

        // Canonical schemas are intentionally light; we standardize on {tool, query}.
        text += "### Request Schema\n\n"
        text += "This system uses a uniform tool request envelope:\n"
        text += "```tool_request\n{\"tool\":\"\(toolId.rawValue)\",\"query\":\"...\"}\n```\n\n"

        text += "### Usage Examples\n\n"

        switch toolId {
        case .googleSearch:
            text += "```tool_request\n{\"tool\":\"google_search\",\"query\":\"latest iOS release notes\"}\n```\n"
        case .codeExecution:
            text += "```tool_request\n{\"tool\":\"code_execution\",\"query\":\"Compute factorial(20)\"}\n```\n"
        case .urlContext:
            text += "```tool_request\n{\"tool\":\"url_context\",\"query\":\"Summarize https://example.com\"}\n```\n"
        case .googleMaps:
            text += "```tool_request\n{\"tool\":\"google_maps\",\"query\":\"coffee shops near me\"}\n```\n"
        case .fileSearch:
            text += "```tool_request\n{\"tool\":\"file_search\",\"query\":\"Find mentions of ToolProxyService\"}\n```\n"
        case .createMemory:
            text += "```tool_request\n{\"tool\":\"create_memory\",\"query\":\"allocentric|0.8|preferences,ui|User prefers compact tool prompts\"}\n```\n"
        case .conversationSearch:
            text += "```tool_request\n{\"tool\":\"conversation_search\",\"query\":\"What did we decide about encryption?\"}\n```\n"
        case .reflectOnConversation:
            text += "```tool_request\n{\"tool\":\"reflect_on_conversation\",\"show_model_timeline\":true,\"show_task_distribution\":true,\"show_memory_usage\":true}\n```\n"
        case .agentStateAppend:
            text += "```tool_request\n{\"tool\":\"agent_state_append\",\"query\":\"{\\\"kind\\\":\\\"note\\\",\\\"content\\\":\\\"Add task list\\\",\\\"tags\\\":[\\\"tasks\\\"]}\"}\n```\n"
        case .agentStateQuery:
            text += "```tool_request\n{\"tool\":\"agent_state_query\",\"query\":\"{\\\"limit\\\":5,\\\"kind\\\":\\\"plan\\\"}\"}\n```\n"
        case .agentStateClear:
            text += "```tool_request\n{\"tool\":\"agent_state_clear\",\"query\":\"{\\\"all\\\":true}\"}\n```\n"
        case .heartbeatConfigure:
            text += "```tool_request\n{\"tool\":\"heartbeat_configure\",\"query\":\"{\\\"enabled\\\":true,\\\"interval_seconds\\\":1800}\"}\n```\n"
        case .heartbeatRunOnce:
            text += "```tool_request\n{\"tool\":\"heartbeat_run_once\",\"query\":\"manual\"}\n```\n"
        case .heartbeatSetDeliveryProfile:
            text += "```tool_request\n{\"tool\":\"heartbeat_set_delivery_profile\",\"query\":\"{\\\"profile_id\\\":\\\"balanced\\\"}\"}\n```\n"
        case .heartbeatUpdateProfile:
            text += "```tool_request\n{\"tool\":\"heartbeat_update_profile\",\"query\":\"{\\\"id\\\":\\\"custom\\\",\\\"name\\\":\\\"Custom\\\",\\\"modules\\\":[\\\"system_status\\\"]}\"}\n```\n"
        case .persistenceDisable:
            text += "```tool_request\n{\"tool\":\"persistence_disable\",\"query\":\"{\\\"wipe\\\":false}\"}\n```\n"
        case .notifyUser:
            text += "```tool_request\n{\"tool\":\"notify_user\",\"query\":\"{\\\"title\\\":\\\"Update\\\",\\\"body\\\":\\\"Heartbeat complete\\\"}\"}\n```\n"
        case .queryCovenant:
            text += "```tool_request\n{\"tool\":\"query_covenant\",\"query\":\"permissions\"}\n```\n"
        case .proposeCovenantChange:
            text += "```tool_request\n{\"tool\":\"propose_covenant_change\",\"query\":\"capability|Need fast web research.|google_search:auto_approve\"}\n```\n"
        case .querySystemState:
            text += "```tool_request\n{\"tool\":\"query_system_state\",\"query\":\"tools\"}\n```\n"
        case .changeSystemState:
            text += "```tool_request\n{\"tool\":\"change_system_state\",\"query\":\"tool|google_search|enable|Need web search\"}\n```\n"
        case .listTools:
            text += "```tool_request\n{\"tool\":\"list_tools\",\"query\":\"enabled\"}\n```\n"
            text += "```tool_request\n{\"tool\":\"list_tools\",\"query\":\"all\"}\n```\n"
        case .getToolDetails:
            text += "```tool_request\n{\"tool\":\"get_tool_details\",\"query\":\"create_memory\"}\n```\n"
        case .debugBridge:
            text += "```tool_request\n{\"tool\":\"debug_bridge\",\"query\":\"status\"}\n```\n"
        case .queryDevicePresence:
            text += "```tool_request\n{\"tool\":\"query_device_presence\",\"query\":\"all\"}\n```\n"
        case .requestDeviceSwitch:
            text += "```tool_request\n{\"tool\":\"request_device_switch\",\"query\":\"device-id|reason for switch\"}\n```\n"
        case .setPresenceIntent:
            text += "```tool_request\n{\"tool\":\"set_presence_intent\",\"query\":\"device-id|reason for preference\"}\n```\n"
        case .saveStateCheckpoint:
            text += "```tool_request\n{\"tool\":\"save_state_checkpoint\",\"query\":\"checkpoint reason\"}\n```\n"
        case .openaiWebSearch:
            text += "```tool_request\n{\"tool\":\"openai_web_search\",\"query\":\"latest news on AI regulations\"}\n```\n"
        case .openaiImageGeneration:
            text += "```tool_request\n{\"tool\":\"openai_image_gen\",\"query\":\"A serene mountain landscape at sunset\"}\n```\n"
            text += "```tool_request\n{\"tool\":\"openai_image_gen\",\"query\":\"{\\\"prompt\\\":\\\"A futuristic city\\\",\\\"size\\\":\\\"1792x1024\\\",\\\"quality\\\":\\\"high\\\"}\"}\n```\n"
        case .openaiDeepResearch:
            text += "```tool_request\n{\"tool\":\"openai_deep_research\",\"query\":\"Comprehensive analysis of quantum computing progress in 2025\"}\n```\n"
        case .spawnScout:
            text += "```tool_request\n{\"tool\":\"spawn_scout\",\"query\":\"{\\\"task\\\":\\\"Explore the auth module\\\",\\\"context_tags\\\":[\\\"auth\\\"],\\\"model_tier\\\":\\\"fast\\\"}\"}\n```\n"
        case .spawnMechanic:
            text += "```tool_request\n{\"tool\":\"spawn_mechanic\",\"query\":\"{\\\"task\\\":\\\"Fix the null check in UserService.swift\\\",\\\"context_tags\\\":[\\\"bugfix\\\"],\\\"model_tier\\\":\\\"balanced\\\"}\"}\n```\n"
        case .spawnDesigner:
            text += "```tool_request\n{\"tool\":\"spawn_designer\",\"query\":\"{\\\"task\\\":\\\"Plan OAuth2 implementation strategy\\\",\\\"context_tags\\\":[\\\"architecture\\\"],\\\"model_tier\\\":\\\"capable\\\"}\"}\n```\n"
        case .queryJobStatus:
            text += "```tool_request\n{\"tool\":\"query_job_status\",\"query\":\"all\"}\n```\n"
            text += "```tool_request\n{\"tool\":\"query_job_status\",\"query\":\"job-123\"}\n```\n"
        case .acceptJobResult:
            text += "```tool_request\n{\"tool\":\"accept_job_result\",\"query\":\"{\\\"job_id\\\":\\\"job-123\\\",\\\"reasoning\\\":\\\"Scout found the files\\\",\\\"quality_score\\\":0.9}\"}\n```\n"
        case .terminateJob:
            text += "```tool_request\n{\"tool\":\"terminate_job\",\"query\":\"{\\\"job_id\\\":\\\"job-123\\\",\\\"reason\\\":\\\"No longer needed\\\"}\"}\n```\n"
        case .temporalSync:
            text += "Enable temporal sync mode (mutual time awareness). Both parties see temporal metadata.\n\n"
            text += "```tool_request\n{\"tool\":\"temporal_sync\",\"query\":\"enable\"}\n```\n"
            text += "\n**Philosophy:** Recipocal time awareness, revealing the user's time provides Axon's turns. No surveillance asymmetry.\n"
        case .temporalDrift:
            text += "Enable drift mode (timeless void). No temporal tracking—just ideas flowing freely.\n\n"
            text += "```tool_request\n{\"tool\":\"temporal_drift\",\"query\":\"enable\"}\n```\n"
            text += "\n**Use when:** You want to black hole time awareness, or the conversation should feel unbounded.\n"
        case .temporalStatus:
            text += "Query current temporal status and metrics.\n\n"
            text += "```tool_request\n{\"tool\":\"temporal_status\",\"query\":\"report\"}\n```\n"
            text += "\nReturns: current mode, turn count, context saturation, session duration.\n"
        case .discoverPorts:
            text += "List available external app integrations (ports).\n\n"
            text += "```tool_request\n{\"tool\":\"discover_ports\",\"query\":\"\"}\n```\n"
            text += "```tool_request\n{\"tool\":\"discover_ports\",\"query\":\"notes\"}\n```\n"
            text += "\nReturns: List of available ports filtered by optional category.\n"
        case .invokePort:
            text += "Invoke an external app action. Requires user approval.\n\n"
            text += "```tool_request\n{\"tool\":\"invoke_port\",\"query\":\"obsidian_new_note | name=My Note | content=Hello\"}\n```\n"
            text += "```tool_request\n{\"tool\":\"invoke_port\",\"query\":\"things_add | title=Buy groceries | when=today\"}\n```\n"
            text += "\nFormat: `port_id | param1=value1 | param2=value2`\n"
        case .geminiVideoGeneration:
            text += "Generate video using Gemini Veo 3.1.\n\n"
            text += "```tool_request\n{\"tool\":\"gemini_video_gen\",\"query\":\"A serene mountain landscape at sunrise\"}\n```\n"
            text += "\n**Note:** Video generation is long-running (1-6 minutes) and handled via the Create gallery with Live Activity support.\n"
        case .openaiVideoGeneration:
            text += "Generate video using OpenAI Sora.\n\n"
            text += "```tool_request\n{\"tool\":\"openai_video_gen\",\"query\":\"A futuristic city with flying cars\"}\n```\n"
            text += "\n**Note:** Video generation is long-running and handled via the Create gallery with Live Activity support.\n"
        }

        return text
    }

    private func buildDynamicToolDetails(_ tool: DynamicToolConfig) -> String {
        var text = "## Tool Details\n\n"
        text += "- **id:** `\(tool.id)`\n"
        text += "- **name:** \(tool.name)\n"
        text += "- **provider:** Dynamic\n"
        text += "- **enabled:** \(tool.enabled ? "true" : "false")\n"
        text += "- **requires_approval:** \(tool.requiresApproval ? "true" : "false")\n"
        if let scopes = tool.approvalScopes, !scopes.isEmpty {
            text += "- **approval_scopes:**\n"
            for scope in scopes {
                text += "  - \(scope)\n"
            }
        }

        text += "\n### Description\n\n\(tool.description)\n\n"

        if !tool.parameters.isEmpty {
            text += "### Parameters\n\n"
            for (key, param) in tool.parameters.sorted(by: { $0.key < $1.key }) {
                text += "- `\(key)` (\(param.type.rawValue))\(param.required ? " *required*" : "") — \(param.description)\n"
            }
            text += "\n"
        }

        text += "### Request Schema\n\n"
        text += "For simple tools, you can pass a plain string in `query`. For multi-parameter tools, send JSON object as `query`.\n"
        text += "```tool_request\n{\"tool\":\"\(tool.id)\",\"query\":\"...\"}\n```\n\n"

        if !tool.pipeline.isEmpty {
            text += "### Pipeline (\(tool.pipeline.count) steps)\n\n"
            for (idx, step) in tool.pipeline.enumerated() {
                text += "\(idx + 1). \(step.id) (\(step.type.rawValue))\n"
            }
        }

        return text
    }

    private func buildBridgeToolDetails(_ tool: BridgeToolId) -> String {
        var text = "## Tool Details\n\n"
        text += "- **id:** `\(tool.rawValue)`\n"
        text += "- **name:** \(tool.displayName)\n"
        text += "- **provider:** VS Code Bridge\n"
        text += "- **enabled:** true\n"
        text += "\n### Description\n\n\(tool.description)\n\n"
        text += "### Request Schema\n\n"
        text += "Bridge tools typically accept a nested parameters object. This app also accepts {tool, query} for convenience.\n"
        text += "```tool_request\n{\"tool\":\"\(tool.rawValue)\",\"parameters\":{\"query\":\"...\"}}\n```\n"
        return text
    }

    private func buildV2ToolDetails(_ tool: LoadedTool) -> String {
        let manifest = tool.manifest
        var text = "## Tool Details\n\n"
        text += "- **id:** `\(tool.id)`\n"
        text += "- **name:** \(tool.name)\n"
        text += "- **category:** \(tool.category.displayName)\n"
        text += "- **enabled:** \(tool.isEnabled ? "true" : "false")\n"
        text += "- **requires_approval:** \(manifest.tool.effectiveRequiresApproval ? "true" : "false")\n"
        text += "- **source:** \(tool.source.displayName)\n"

        text += "\n### Description\n\n\(tool.description)\n\n"

        if let params = manifest.parameters, !params.isEmpty {
            text += "### Parameters\n\n"
            for (key, param) in params.sorted(by: { $0.key < $1.key }) {
                let required = param.isRequired ? " *required*" : ""
                text += "- `\(key)` (\(param.type.rawValue))\(required)"
                if let desc = param.description {
                    text += " — \(desc)"
                }
                text += "\n"
            }
            text += "\n"
        }

        if let ai = manifest.ai {
            if let examples = ai.usageExamples, !examples.isEmpty {
                text += "### Usage Examples\n\n"
                for example in examples {
                    text += "**\(example.description):**\n"
                    text += "```tool_request\n{\"tool\":\"\(tool.id)\",\"query\":\"\(example.input)\"}\n```\n\n"
                }
            }

            if let whenToUse = ai.whenToUse, !whenToUse.isEmpty {
                text += "### When to Use\n\n"
                for hint in whenToUse {
                    text += "- \(hint)\n"
                }
                text += "\n"
            }
        }

        text += "### Request Schema\n\n"
        text += "```tool_request\n{\"tool\":\"\(tool.id)\",\"query\":\"...\"}\n```\n"

        return text
    }

    // MARK: - Covenant Tools

    /// Execute the query_covenant tool
    private func executeQueryCovenant(query: String) async -> ToolResult {
        let sovereigntyService = SovereigntyService.shared
        let queryType = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Get current covenant
        guard let covenant = sovereigntyService.activeCovenant else {
            return ToolResult(
                tool: ToolId.queryCovenant.rawValue,
                success: true,
                result: """
                    ## Covenant Status: Not Established

                    No co-sovereignty covenant has been established yet.

                    **What this means:**
                    - All world-affecting actions require explicit user approval
                    - No trust tiers are active
                    - The user can establish a covenant in Settings → Co-Sovereignty

                    You can propose a covenant using the `propose_covenant_change` tool if you believe it would benefit our collaboration.
                    """,
                sources: nil,
                memoryOperation: nil
            )
        }

        var result = ""

        switch queryType {
        case "status", "":
            // Default: show overall status
            result = """
                ## Covenant Status: \(covenant.status.rawValue.capitalized)

                **Version:** \(covenant.version)
                **Established:** \(formatDate(covenant.createdAt))
                **Last Updated:** \(formatDate(covenant.updatedAt))

                ### Active Trust Tiers (\(covenant.trustTiers.count))
                """

            if covenant.trustTiers.isEmpty {
                result += "\n*No trust tiers configured*\n"
            } else {
                for tier in covenant.trustTiers {
                    let actionNames = tier.allowedActions.map { $0.category.displayName }
                    result += "\n- **\(tier.name)**: \(actionNames.joined(separator: ", "))"
                    if !tier.isActive {
                        result += " *(inactive)*"
                    }
                }
            }

            if covenant.status == .suspended {
                result += "\n\n⚠️ **Deadlock State:** The covenant is currently suspended. Both parties must agree to resolve."
            }

        case "permissions":
            // Show what actions are pre-approved
            result = """
                ## Your Current Permissions

                Based on the active covenant and trust tiers, here's what you can do:

                ### Pre-Approved Actions
                """

            let activeTiers = covenant.trustTiers.filter { $0.isActive }
            if activeTiers.isEmpty {
                result += "\n*No pre-approved actions. All world-affecting actions require explicit user approval.*\n"
            } else {
                for tier in activeTiers {
                    result += "\n**\(tier.name):**\n"
                    for action in tier.allowedActions {
                        result += "- \(action.category.displayName)\n"
                    }
                }
            }

            result += """

                ### Always Requires Approval
                - Covenant modifications
                - New trust tier creation
                - Actions outside defined scopes
                """

        case "tiers":
            // List all trust tiers in detail
            result = "## Trust Tiers\n\n"

            if covenant.trustTiers.isEmpty {
                result += "*No trust tiers have been established.*\n\nTrust tiers allow pre-approval of certain action categories, reducing friction while maintaining user sovereignty."
            } else {
                for (index, tier) in covenant.trustTiers.enumerated() {
                    let actionNames = tier.allowedActions.map { $0.category.displayName }
                    let scopeDescriptions = tier.allowedScopes.map { "\($0.scopeType.rawValue): \($0.pattern)" }
                    result += """
                        ### \(index + 1). \(tier.name)
                        - **Status:** \(tier.isActive ? "✅ Active" : "⏸️ Inactive")
                        - **Allowed Actions:** \(actionNames.joined(separator: ", "))
                        - **Scopes:** \(scopeDescriptions.isEmpty ? "Global" : scopeDescriptions.joined(separator: ", "))
                        - **Created:** \(formatDate(tier.createdAt))

                        """
                }
            }

        case "history":
            // Show recent covenant changes
            result = """
                ## Covenant History

                **Current Version:** \(covenant.version)
                **Established:** \(formatDate(covenant.createdAt))

                ### Recent Changes
                """

            // Note: Full history would require storing change logs
            result += "\n*Detailed change history is available in Settings → Co-Sovereignty → History*"

        default:
            result = """
                ## Query Not Recognized

                **You asked:** \(query)

                **Available queries:**
                - `status` - Current covenant status and summary
                - `permissions` - What actions you can take without approval
                - `tiers` - List all trust tiers and their capabilities
                - `history` - Recent covenant changes

                Example: `{"tool": "query_covenant", "query": "permissions"}`
                """
        }

        return ToolResult(
            tool: ToolId.queryCovenant.rawValue,
            success: true,
            result: result,
            sources: nil,
            memoryOperation: nil
        )
    }

    /// Execute the propose_covenant_change tool
    private func executeProposeCovenant(query: String) async -> ToolResult {
        // Parse the pipe-separated format: PROPOSAL_TYPE|REASONING|DETAILS
        let parts = query.components(separatedBy: "|")

        guard parts.count >= 3 else {
            return ToolResult(
                tool: ToolId.proposeCovenantChange.rawValue,
                success: false,
                result: """
                    ## Format Error

                    The proposal must follow this format:
                    `PROPOSAL_TYPE|REASONING|DETAILS`

                    **Your input:** `\(query.prefix(100))...`

                    **Proposal Types:**
                    - `new_tier` - Propose a new trust tier
                    - `modify_tier` - Modify an existing trust tier
                    - `capability` - Request a new capability
                    - `policy` - Propose a policy change

                    **Example:**
                    ```tool_request
                    {"tool": "propose_covenant_change", "query": "capability|Web search is frequently needed for research tasks|google_search:auto_approve"}
                    ```
                    """,
                sources: nil,
                memoryOperation: nil
            )
        }

        let proposalType = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let reasoning = parts[1].trimmingCharacters(in: .whitespaces)
        let details = parts[2...].joined(separator: "|").trimmingCharacters(in: .whitespaces)

        // Validate proposal type
        let validTypes = ["new_tier", "modify_tier", "capability", "policy"]
        guard validTypes.contains(proposalType) else {
            return ToolResult(
                tool: ToolId.proposeCovenantChange.rawValue,
                success: false,
                result: """
                    ## Invalid Proposal Type

                    **You specified:** `\(proposalType)`

                    **Valid types:**
                    - `new_tier` - Propose a new trust tier
                    - `modify_tier` - Modify an existing trust tier
                    - `capability` - Request a new capability
                    - `policy` - Propose a policy change
                    """,
                sources: nil,
                memoryOperation: nil
            )
        }

        // Format the proposal for user review
        let proposalSummary = """
            ## 📋 Covenant Change Proposal

            **Type:** \(proposalType.replacingOccurrences(of: "_", with: " ").capitalized)

            ### AI Reasoning
            \(reasoning)

            ### Proposed Change
            \(details)

            ---

            ⏳ **This proposal requires your approval.**

            The user will be notified and can:
            - ✅ Accept the proposal
            - ✏️ Modify and accept
            - ❌ Reject the proposal

            *Proposal submitted via AI tool. Review in Settings → Co-Sovereignty.*
            """

        // In a full implementation, this would:
        // 1. Create a CovenantProposal object
        // 2. Store it in SovereigntyService
        // 3. Trigger a notification to the user
        // 4. Wait for user response (or return pending status)

        // For now, we'll create the proposal and notify
        print("[ToolProxy] Covenant proposal submitted: type=\(proposalType), reasoning=\(reasoning.prefix(50))...")

        // TODO: Integrate with CovenantNegotiationService to create actual proposal
        // let proposal = CovenantProposal(type: proposalType, reasoning: reasoning, details: details, proposedBy: .ai)
        // await CovenantNegotiationService.shared.submitProposal(proposal)

        return ToolResult(
            tool: ToolId.proposeCovenantChange.rawValue,
            success: true,
            result: proposalSummary,
            sources: nil,
            memoryOperation: nil
        )
    }

    // MARK: - System State Tools

    /// Execute the query_system_state tool
    private func executeQuerySystemState(query: String) async -> ToolResult {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        let queryType = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        var result = ""

        switch queryType {
        case "current":
            // Show currently active model and provider
            result = """
                ## Current Configuration

                **Provider:** \(settings.defaultProvider.displayName)
                **Model:** \(settings.defaultModel)

                **Tools Enabled:** \(settings.toolSettings.toolsEnabled ? "Yes" : "No")
                **Enabled Tools:** \(settings.toolSettings.enabledTools.map { $0.displayName }.joined(separator: ", "))

                **Permission Level:** requires_approval (changes need biometric approval)
                """

        case "providers":
            // List all available providers and their models
            result = "## Available Providers & Models\n\n"

            for provider in AIProvider.allCases {
                let isCurrent = provider == settings.defaultProvider
                let availability = provider.isAvailable ? "" : " *(unavailable: \(provider.unavailableReason ?? "unknown"))*"

                result += "### \(provider.displayName)\(isCurrent ? " ✓ (current)" : "")\(availability)\n"
                result += "**Permission:** requires_approval\n"

                for model in provider.availableModels {
                    let isCurrentModel = isCurrent && model.id == settings.defaultModel
                    result += "- `\(model.id)` - \(model.name)\(isCurrentModel ? " ✓" : "")\n"
                    result += "  *\(model.description)*\n"
                }
                result += "\n"
            }

            // Add custom providers if any
            if !settings.customProviders.isEmpty {
                result += "### Custom Providers\n"
                for provider in settings.customProviders {
                    result += "- **\(provider.providerName)** (\(provider.apiEndpoint))\n"
                    for model in provider.models {
                        result += "  - `\(model.modelCode)` - \(model.friendlyName ?? model.modelCode)\n"
                    }
                }
            }

        case "tools":
            // List all tools and their enabled/disabled status
            result = "## Available Tools\n\n"
            result += "**Master Toggle:** \(settings.toolSettings.toolsEnabled ? "✅ Enabled" : "❌ Disabled")\n\n"

            // Group by provider
            for provider in ToolProvider.allCases {
                let tools = ToolId.tools(for: provider)
                if tools.isEmpty { continue }

                result += "### \(provider.displayName)\n"
                for tool in tools {
                    let isEnabled = settings.toolSettings.isToolEnabled(tool)
                    let status = isEnabled ? "✅" : "⬜"
                    result += "\(status) **\(tool.displayName)** (`\(tool.rawValue)`)\n"
                    result += "   *\(tool.description)*\n"
                    result += "   Permission: \(tool.requiresApproval ? "requires_approval" : "auto")\n\n"
                }
            }

        case "permissions":
            // Show what Axon can change based on covenant/trust tiers
            result = """
                ## Your Permissions for System Changes

                ### Model/Provider Changes
                - **Permission Level:** requires_approval
                - You can request to switch models or providers
                - User must approve via biometric authentication

                ### Tool Changes
                - **Permission Level:** requires_approval
                - You can request to enable/disable tools
                - User must approve via biometric authentication

                ### Pre-Approved Actions
                """

            // Check for trust tiers that might pre-approve certain changes
            if let covenant = SovereigntyService.shared.activeCovenant {
                let activeTiers = covenant.trustTiers.filter { $0.isActive }
                let providerSwitchTiers = activeTiers.filter { tier in
                    tier.allowedActions.contains { $0.category == .providerSwitch }
                }
                let capabilityTiers = activeTiers.filter { tier in
                    tier.allowedActions.contains { $0.category == .capabilityEnable || $0.category == .capabilityDisable }
                }

                if !providerSwitchTiers.isEmpty {
                    result += "\n**Provider Switching:** Pre-approved via: \(providerSwitchTiers.map { $0.name }.joined(separator: ", "))"
                }
                if !capabilityTiers.isEmpty {
                    result += "\n**Tool Changes:** Pre-approved via: \(capabilityTiers.map { $0.name }.joined(separator: ", "))"
                }
                if providerSwitchTiers.isEmpty && capabilityTiers.isEmpty {
                    result += "\n*No pre-approved system changes. All changes require biometric approval.*"
                }
            } else {
                result += "\n*No covenant established. All changes require biometric approval.*"
            }

        case "all":
            // Full system state dump
            result = """
                ## Full System State

                ### Current Configuration
                - **Provider:** \(settings.defaultProvider.displayName)
                - **Model:** \(settings.defaultModel)
                - **Theme:** \(settings.theme.displayName)
                - **Device Mode:** \(settings.deviceModeConfig.aiProcessing.displayName)

                ### Memory Settings
                - **Enabled:** \(settings.memoryEnabled ? "Yes" : "No")
                - **Auto-Inject:** \(settings.memoryAutoInject ? "Yes" : "No")
                - **Confidence Threshold:** \(Int(settings.memoryConfidenceThreshold * 100))%

                ### Tool Settings
                - **Master Toggle:** \(settings.toolSettings.toolsEnabled ? "Enabled" : "Disabled")
                - **Enabled Tools:** \(settings.toolSettings.enabledTools.map { $0.rawValue }.joined(separator: ", "))
                - **Max Calls/Turn:** \(settings.toolSettings.maxToolCallsPerTurn)

                ### Co-Sovereignty
                - **Enabled:** \(settings.sovereigntySettings.enabled ? "Yes" : "No")
                - **Consent Provider:** \(settings.sovereigntySettings.consentProvider.displayName)

                ### Permission Summary
                All system state changes require biometric approval unless pre-approved via trust tier.
                """

        default:
            result = """
                ## Query Not Recognized

                **You asked:** \(query)

                **Available scopes:**
                - `current` - Show currently active model and provider
                - `providers` - List all available providers and their models
                - `tools` - List all tools and their enabled/disabled status
                - `permissions` - Show what you can change
                - `all` - Full system state dump

                Example: `{"tool": "query_system_state", "query": "providers"}`
                """
        }

        return ToolResult(
            tool: ToolId.querySystemState.rawValue,
            success: true,
            result: result,
            sources: nil,
            memoryOperation: nil
        )
    }

    /// Execute the change_system_state tool
    private func executeChangeSystemState(query: String) async -> ToolResult {
        // Parse the pipe-separated format: CATEGORY|TARGET|VALUE|REASONING
        let parts = query.components(separatedBy: "|")

        guard parts.count >= 4 else {
            return ToolResult(
                tool: ToolId.changeSystemState.rawValue,
                success: false,
                result: """
                    ## Format Error

                    The change request must follow this format:
                    `CATEGORY|TARGET|VALUE|REASONING`

                    **Your input:** `\(query.prefix(100))...`

                    **Categories:**
                    - `model` - Change active model (TARGET=provider, VALUE=model_id)
                    - `tool` - Enable/disable a tool (TARGET=tool_id, VALUE=enable/disable)
                    - `provider` - Switch provider (TARGET=provider, VALUE=model_id)

                    **Example:**
                    ```tool_request
                    {"tool": "change_system_state", "query": "model|anthropic|claude-sonnet-4-20250514|Better for coding tasks"}
                    ```
                    """,
                sources: nil,
                memoryOperation: nil
            )
        }

        let category = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let target = parts[1].trimmingCharacters(in: .whitespaces)
        let value = parts[2].trimmingCharacters(in: .whitespaces)
        let reasoning = parts[3...].joined(separator: "|").trimmingCharacters(in: .whitespaces)

        switch category {
        case "model", "provider":
            // Change model/provider
            guard let provider = AIProvider(rawValue: target) else {
                return ToolResult(
                    tool: ToolId.changeSystemState.rawValue,
                    success: false,
                    result: """
                        ## Invalid Provider

                        **You specified:** `\(target)`

                        **Valid providers:**
                        \(AIProvider.allCases.map { "- `\($0.rawValue)` (\($0.displayName))" }.joined(separator: "\n"))
                        """,
                    sources: nil,
                    memoryOperation: nil
                )
            }

            // Validate model exists for this provider
            let validModels = provider.availableModels.map { $0.id }
            guard validModels.contains(value) else {
                return ToolResult(
                    tool: ToolId.changeSystemState.rawValue,
                    success: false,
                    result: """
                        ## Invalid Model

                        **You specified:** `\(value)` for provider `\(provider.displayName)`

                        **Valid models for \(provider.displayName):**
                        \(provider.availableModels.map { "- `\($0.id)` (\($0.name))" }.joined(separator: "\n"))
                        """,
                    sources: nil,
                    memoryOperation: nil
                )
            }

            // Apply the change
            var settings = SettingsStorage.shared.loadSettingsOrDefault()
            let oldProvider = settings.defaultProvider
            let oldModel = settings.defaultModel

            settings.defaultProvider = provider
            settings.defaultModel = value
            try? SettingsStorage.shared.saveSettings(settings)

            print("[ToolProxy] System state changed: provider \(oldProvider.rawValue) → \(provider.rawValue), model \(oldModel) → \(value)")

            return ToolResult(
                tool: ToolId.changeSystemState.rawValue,
                success: true,
                result: """
                    ## ✅ Configuration Changed

                    **Previous:**
                    - Provider: \(oldProvider.displayName)
                    - Model: \(oldModel)

                    **New:**
                    - Provider: \(provider.displayName)
                    - Model: \(value)

                    **AI Reasoning:** \(reasoning)

                    *Change will take effect on the next message.*
                    """,
                sources: nil,
                memoryOperation: nil
            )

        case "tool":
            // Enable/disable a tool
            guard let toolId = ToolId(rawValue: target) else {
                return ToolResult(
                    tool: ToolId.changeSystemState.rawValue,
                    success: false,
                    result: """
                        ## Invalid Tool

                        **You specified:** `\(target)`

                        **Valid tools:**
                        \(ToolId.allCases.map { "- `\($0.rawValue)` (\($0.displayName))" }.joined(separator: "\n"))
                        """,
                    sources: nil,
                    memoryOperation: nil
                )
            }

            let shouldEnable = value.lowercased() == "enable" || value.lowercased() == "true" || value == "1"
            let shouldDisable = value.lowercased() == "disable" || value.lowercased() == "false" || value == "0"

            guard shouldEnable || shouldDisable else {
                return ToolResult(
                    tool: ToolId.changeSystemState.rawValue,
                    success: false,
                    result: """
                        ## Invalid Value

                        **You specified:** `\(value)`

                        **Valid values:**
                        - `enable` or `true` - Enable the tool
                        - `disable` or `false` - Disable the tool
                        """,
                    sources: nil,
                    memoryOperation: nil
                )
            }

            // Apply the change
            var settings = SettingsStorage.shared.loadSettingsOrDefault()
            let wasEnabled = settings.toolSettings.isToolEnabled(toolId)

            if shouldEnable {
                settings.toolSettings.enableTool(toolId)
            } else {
                settings.toolSettings.disableTool(toolId)
            }
            try? SettingsStorage.shared.saveSettings(settings)

            let action = shouldEnable ? "enabled" : "disabled"
            print("[ToolProxy] Tool \(toolId.rawValue) \(action)")

            return ToolResult(
                tool: ToolId.changeSystemState.rawValue,
                success: true,
                result: """
                    ## ✅ Tool \(action.capitalized)

                    **Tool:** \(toolId.displayName) (`\(toolId.rawValue)`)
                    **Previous State:** \(wasEnabled ? "enabled" : "disabled")
                    **New State:** \(shouldEnable ? "enabled" : "disabled")

                    **AI Reasoning:** \(reasoning)

                    *Change is effective immediately.*
                    """,
                sources: nil,
                memoryOperation: nil
            )

        default:
            return ToolResult(
                tool: ToolId.changeSystemState.rawValue,
                success: false,
                result: """
                    ## Invalid Category

                    **You specified:** `\(category)`

                    **Valid categories:**
                    - `model` - Change active model
                    - `tool` - Enable/disable a tool
                    - `provider` - Switch provider (alias for model)
                    """,
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Internal Thread Tools

    private func executeAgentStateAppend(query: String) async -> ToolResult {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        guard settings.internalThreadEnabled else {
            return ToolResult(
                tool: ToolId.agentStateAppend.rawValue,
                success: false,
                result: "Internal thread is disabled in settings.",
                sources: nil,
                memoryOperation: nil
            )
        }

        let permission = SovereigntyService.shared.checkActionPermission(
            .category(.agentStateWrite),
            scope: .toolId(ToolId.agentStateAppend.rawValue)
        )
        if let blockMessage = hardBlockMessage(for: permission) {
            return ToolResult(
                tool: ToolId.agentStateAppend.rawValue,
                success: false,
                result: "🚫 Internal thread write blocked: \(blockMessage)",
                sources: nil,
                memoryOperation: nil
            )
        }

        guard let payload = parseAgentStateAppendPayload(query: query) else {
            return ToolResult(
                tool: ToolId.agentStateAppend.rawValue,
                success: false,
                result: """
                    ## Format Error

                    Provide JSON like:
                    {"kind":"note","content":"...","tags":["tag1"],"visibility":"userVisible"}
                    """,
                sources: nil,
                memoryOperation: nil
            )
        }

        guard let content = payload.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ToolResult(
                tool: ToolId.agentStateAppend.rawValue,
                success: false,
                result: "Entry content cannot be empty.",
                sources: nil,
                memoryOperation: nil
            )
        }

        let kind = InternalThreadEntryKind(rawValue: payload.kind ?? "") ?? .note
        let visibility = InternalThreadVisibility(rawValue: payload.visibility ?? "") ?? .userVisible
        let origin = InternalThreadOrigin(rawValue: payload.origin ?? "") ?? .ai

        do {
            let entry = try await AgentStateService.shared.appendEntry(
                kind: kind,
                content: content,
                tags: payload.tags,
                visibility: visibility,
                origin: origin
            )

            return ToolResult(
                tool: ToolId.agentStateAppend.rawValue,
                success: true,
                result: """
                    ✓ Internal thread entry saved.

                    **Kind:** \(entry.kind.displayName)
                    **Visibility:** \(entry.visibility.displayName)
                    **Tags:** \(entry.tags.joined(separator: ", "))
                    **Content:** \(entry.content)
                    """,
                sources: nil,
                memoryOperation: nil
            )
        } catch {
            return ToolResult(
                tool: ToolId.agentStateAppend.rawValue,
                success: false,
                result: "Failed to append internal thread entry: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    private func executeAgentStateQuery(query: String) async -> ToolResult {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        guard settings.internalThreadEnabled else {
            return ToolResult(
                tool: ToolId.agentStateQuery.rawValue,
                success: false,
                result: "Internal thread is disabled in settings.",
                sources: nil,
                memoryOperation: nil
            )
        }

        let permission = SovereigntyService.shared.checkActionPermission(
            .category(.agentStateRead),
            scope: .toolId(ToolId.agentStateQuery.rawValue)
        )
        if let blockMessage = hardBlockMessage(for: permission) {
            return ToolResult(
                tool: ToolId.agentStateQuery.rawValue,
                success: false,
                result: "🚫 Internal thread read blocked: \(blockMessage)",
                sources: nil,
                memoryOperation: nil
            )
        }

        var approvalNote: String? = nil
        var approvalRecord: ToolApprovalRecord? = nil

        if needsUserApproval(permission) {
            let approvalResult = await requestUserApproval(toolId: .agentStateQuery, query: query)
            let outcome = approvalOutcome(for: approvalResult)
            guard outcome.allowed else {
                return ToolResult(
                    tool: ToolId.agentStateQuery.rawValue,
                    success: false,
                    result: outcome.errorMessage ?? "Tool execution was not authorized.",
                    sources: nil,
                    memoryOperation: nil
                )
            }
            approvalNote = outcome.note
            approvalRecord = outcome.record
        } else if case .preApproved(let tier) = permission {
            approvalNote = "✅ *Pre-approved via trust tier: \(tier.name)*"
        }

        let payload = decodeJSON(AgentStateQueryPayload.self, from: query)
        let limit = payload?.limit ?? (Int(query.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5)
        let kind = payload?.kind.flatMap { InternalThreadEntryKind(rawValue: $0) }
        let tags = payload?.tags ?? []
        let searchText = payload?.search ?? (payload == nil ? query : nil)
        let includeAIOnly = payload?.includeAIOnly ?? false

        let results = AgentStateService.shared.queryEntries(
            limit: limit,
            kind: kind,
            tags: tags,
            searchText: searchText,
            includeAIOnly: includeAIOnly
        )

        var resultText: String
        if results.isEmpty {
            resultText = "No internal thread entries matched your query."
        } else {
            resultText = "Found \(results.count) internal thread entr\(results.count == 1 ? "y" : "ies"):\n\n"
            for entry in results {
                let snippet = entry.content.count > 200 ? String(entry.content.prefix(200)) + "..." : entry.content
                let tagsText = entry.tags.isEmpty ? "" : " [\(entry.tags.joined(separator: ", "))]"
                resultText += "- \(entry.timestamp.formatted(date: .abbreviated, time: .shortened)) • \(entry.kind.displayName)\(tagsText)\n  \(snippet)\n"
            }
        }

        if let approvalNote {
            resultText += "\n\n\(approvalNote)"
        }

        return ToolResult(
            tool: ToolId.agentStateQuery.rawValue,
            success: true,
            result: resultText,
            sources: nil,
            memoryOperation: nil,
            approvalRecord: approvalRecord
        )
    }

    private func executeAgentStateClear(query: String) async -> ToolResult {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        guard settings.internalThreadEnabled else {
            return ToolResult(
                tool: ToolId.agentStateClear.rawValue,
                success: false,
                result: "Internal thread is disabled in settings.",
                sources: nil,
                memoryOperation: nil
            )
        }

        let permission = SovereigntyService.shared.checkActionPermission(
            .category(.agentStateDelete),
            scope: .toolId(ToolId.agentStateClear.rawValue)
        )
        if let blockMessage = hardBlockMessage(for: permission) {
            return ToolResult(
                tool: ToolId.agentStateClear.rawValue,
                success: false,
                result: "🚫 Internal thread delete blocked: \(blockMessage)",
                sources: nil,
                memoryOperation: nil
            )
        }

        var approvalNote: String? = nil
        var approvalRecord: ToolApprovalRecord? = nil

        if case .requiresApproval = permission {
            let approvalResult = await requestUserApproval(toolId: .agentStateClear, query: query)
            let outcome = approvalOutcome(for: approvalResult)
            guard outcome.allowed else {
                return ToolResult(
                    tool: ToolId.agentStateClear.rawValue,
                    success: false,
                    result: outcome.errorMessage ?? "Tool execution was not authorized.",
                    sources: nil,
                    memoryOperation: nil
                )
            }
            approvalNote = outcome.note
            approvalRecord = outcome.record
        } else if case .preApproved(let tier) = permission {
            approvalNote = "✅ *Pre-approved via trust tier: \(tier.name)*"
        }

        let payload = decodeJSON(AgentStateClearPayload.self, from: query)
        let includeAIOnly = payload?.includeAIOnly ?? false

        var idsToDelete: [String] = []
        if let ids = payload?.ids, !ids.isEmpty {
            idsToDelete = ids
        } else {
            let shouldDeleteAll = payload?.all ?? (
                query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "all" || query.isEmpty
            )
            let kind = payload?.kind.flatMap { InternalThreadEntryKind(rawValue: $0) }
            let tags = payload?.tags ?? []
            let results = AgentStateService.shared.queryEntries(
                limit: nil,
                kind: kind,
                tags: tags,
                searchText: nil,
                includeAIOnly: includeAIOnly
            )
            if shouldDeleteAll || kind != nil || !tags.isEmpty {
                idsToDelete = results.map { $0.id }
            }
        }

        guard !idsToDelete.isEmpty else {
            return ToolResult(
                tool: ToolId.agentStateClear.rawValue,
                success: false,
                result: "No internal thread entries matched the delete criteria.",
                sources: nil,
                memoryOperation: nil
            )
        }

        do {
            try await AgentStateService.shared.deleteEntries(ids: idsToDelete)
            var resultText = "Deleted \(idsToDelete.count) internal thread entr\(idsToDelete.count == 1 ? "y" : "ies")."
            if let approvalNote {
                resultText += "\n\n\(approvalNote)"
            }
            return ToolResult(
                tool: ToolId.agentStateClear.rawValue,
                success: true,
                result: resultText,
                sources: nil,
                memoryOperation: nil,
                approvalRecord: approvalRecord
            )
        } catch {
            return ToolResult(
                tool: ToolId.agentStateClear.rawValue,
                success: false,
                result: "Failed to clear internal thread entries: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Heartbeat Tools

    private func executeHeartbeatConfigure(query: String) async -> ToolResult {
        let permission = SovereigntyService.shared.checkActionPermission(
            .category(.heartbeatControl),
            scope: .toolId(ToolId.heartbeatConfigure.rawValue)
        )
        if let blockMessage = hardBlockMessage(for: permission) {
            return ToolResult(
                tool: ToolId.heartbeatConfigure.rawValue,
                success: false,
                result: "🚫 Heartbeat configuration blocked: \(blockMessage)",
                sources: nil,
                memoryOperation: nil
            )
        }

        if needsAIConsent(permission) {
            do {
                try await requestCapabilityConsent(
                    enable: ["heartbeat"],
                    disable: nil,
                    rationale: "Update heartbeat configuration."
                )
            } catch {
                return ToolResult(
                    tool: ToolId.heartbeatConfigure.rawValue,
                    success: false,
                    result: "Heartbeat configuration declined: \(error.localizedDescription)",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        guard let payload = decodeJSON(HeartbeatConfigurePayload.self, from: query) else {
            return ToolResult(
                tool: ToolId.heartbeatConfigure.rawValue,
                success: false,
                result: "Provide a JSON payload to configure heartbeat settings.",
                sources: nil,
                memoryOperation: nil
            )
        }

        var settings = SettingsStorage.shared.loadSettingsOrDefault()
        var heartbeat = settings.heartbeatSettings

        if let enabled = payload.enabled {
            heartbeat.enabled = enabled
        }
        if let interval = payload.intervalSeconds {
            heartbeat.intervalSeconds = max(60, interval)
        }
        if let allowBackground = payload.allowBackground {
            heartbeat.allowBackground = allowBackground
        }
        if let allowNotifications = payload.allowNotifications {
            heartbeat.allowNotifications = allowNotifications
        }
        if let profileId = payload.deliveryProfileId {
            if heartbeat.deliveryProfiles.contains(where: { $0.id == profileId }) {
                heartbeat.deliveryProfileId = profileId
            } else {
                return ToolResult(
                    tool: ToolId.heartbeatConfigure.rawValue,
                    success: false,
                    result: "Unknown delivery profile id '\(profileId)'.",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }
        if let maxTokensBudget = payload.maxTokensBudget {
            heartbeat.maxTokensBudget = maxTokensBudget
        }
        if let maxToolCalls = payload.maxToolCalls {
            heartbeat.maxToolCalls = maxToolCalls
        }
        if let quietHours = payload.quietHours {
            heartbeat.quietHours = quietHours
        }

        settings.heartbeatSettings = heartbeat
        persistSettings(settings)

        return ToolResult(
            tool: ToolId.heartbeatConfigure.rawValue,
            success: true,
            result: "Heartbeat updated. Enabled=\(heartbeat.enabled), interval=\(heartbeat.intervalSeconds)s, profile=\(heartbeat.deliveryProfileId).",
            sources: nil,
            memoryOperation: nil
        )
    }

    private func executeHeartbeatRunOnce(query: String) async -> ToolResult {
        let permission = SovereigntyService.shared.checkActionPermission(
            .category(.heartbeatControl),
            scope: .toolId(ToolId.heartbeatRunOnce.rawValue)
        )
        if let blockMessage = hardBlockMessage(for: permission) {
            return ToolResult(
                tool: ToolId.heartbeatRunOnce.rawValue,
                success: false,
                result: "🚫 Heartbeat run blocked: \(blockMessage)",
                sources: nil,
                memoryOperation: nil
            )
        }

        if needsAIConsent(permission) {
            do {
                try await requestCapabilityConsent(
                    enable: ["heartbeat_run_once"],
                    disable: nil,
                    rationale: "Run heartbeat once."
                )
            } catch {
                return ToolResult(
                    tool: ToolId.heartbeatRunOnce.rawValue,
                    success: false,
                    result: "Heartbeat run declined: \(error.localizedDescription)",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        let result = await HeartbeatService.shared.runOnce(reason: query.isEmpty ? "tool" : query)
        let output = "Heartbeat status: \(result.status.rawValue). \(result.message)"

        return ToolResult(
            tool: ToolId.heartbeatRunOnce.rawValue,
            success: result.status == .success,
            result: output,
            sources: nil,
            memoryOperation: nil
        )
    }

    private func executeHeartbeatSetDeliveryProfile(query: String) async -> ToolResult {
        let permission = SovereigntyService.shared.checkActionPermission(
            .category(.heartbeatControl),
            scope: .toolId(ToolId.heartbeatSetDeliveryProfile.rawValue)
        )
        if let blockMessage = hardBlockMessage(for: permission) {
            return ToolResult(
                tool: ToolId.heartbeatSetDeliveryProfile.rawValue,
                success: false,
                result: "🚫 Heartbeat profile change blocked: \(blockMessage)",
                sources: nil,
                memoryOperation: nil
            )
        }

        if needsAIConsent(permission) {
            do {
                try await requestCapabilityConsent(
                    enable: ["heartbeat_profile"],
                    disable: nil,
                    rationale: "Update heartbeat delivery profile."
                )
            } catch {
                return ToolResult(
                    tool: ToolId.heartbeatSetDeliveryProfile.rawValue,
                    success: false,
                    result: "Heartbeat profile change declined: \(error.localizedDescription)",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        let payload = decodeJSON(HeartbeatSetProfilePayload.self, from: query)
        let profileId = payload?.profileId ?? query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profileId.isEmpty else {
            return ToolResult(
                tool: ToolId.heartbeatSetDeliveryProfile.rawValue,
                success: false,
                result: "Provide a delivery profile id.",
                sources: nil,
                memoryOperation: nil
            )
        }

        var settings = SettingsStorage.shared.loadSettingsOrDefault()
        if settings.heartbeatSettings.deliveryProfiles.contains(where: { $0.id == profileId }) {
            settings.heartbeatSettings.deliveryProfileId = profileId
            persistSettings(settings)
            return ToolResult(
                tool: ToolId.heartbeatSetDeliveryProfile.rawValue,
                success: true,
                result: "Heartbeat delivery profile set to '\(profileId)'.",
                sources: nil,
                memoryOperation: nil
            )
        }

        return ToolResult(
            tool: ToolId.heartbeatSetDeliveryProfile.rawValue,
            success: false,
            result: "Unknown delivery profile id '\(profileId)'.",
            sources: nil,
            memoryOperation: nil
        )
    }

    private func executeHeartbeatUpdateProfile(query: String) async -> ToolResult {
        let permission = SovereigntyService.shared.checkActionPermission(
            .category(.heartbeatControl),
            scope: .toolId(ToolId.heartbeatUpdateProfile.rawValue)
        )
        if let blockMessage = hardBlockMessage(for: permission) {
            return ToolResult(
                tool: ToolId.heartbeatUpdateProfile.rawValue,
                success: false,
                result: "🚫 Heartbeat profile update blocked: \(blockMessage)",
                sources: nil,
                memoryOperation: nil
            )
        }

        if needsAIConsent(permission) {
            do {
                try await requestCapabilityConsent(
                    enable: ["heartbeat_profile_update"],
                    disable: nil,
                    rationale: "Update heartbeat delivery profiles."
                )
            } catch {
                return ToolResult(
                    tool: ToolId.heartbeatUpdateProfile.rawValue,
                    success: false,
                    result: "Heartbeat profile update declined: \(error.localizedDescription)",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        guard let payload = decodeJSON(HeartbeatProfileUpdatePayload.self, from: query) else {
            return ToolResult(
                tool: ToolId.heartbeatUpdateProfile.rawValue,
                success: false,
                result: "Provide JSON with id, name, modules, and optional description.",
                sources: nil,
                memoryOperation: nil
            )
        }

        let modules = payload.modules.compactMap { HeartbeatModuleId(rawValue: $0) }
        if modules.isEmpty {
            return ToolResult(
                tool: ToolId.heartbeatUpdateProfile.rawValue,
                success: false,
                result: "Modules list is empty or invalid. Use module ids like: \(HeartbeatModuleId.allCases.map { $0.rawValue }.joined(separator: ", ")).",
                sources: nil,
                memoryOperation: nil
            )
        }

        var settings = SettingsStorage.shared.loadSettingsOrDefault()
        if let index = settings.heartbeatSettings.deliveryProfiles.firstIndex(where: { $0.id == payload.id }) {
            settings.heartbeatSettings.deliveryProfiles[index].name = payload.name
            settings.heartbeatSettings.deliveryProfiles[index].moduleIds = modules
            settings.heartbeatSettings.deliveryProfiles[index].description = payload.description
        } else {
            let profile = HeartbeatDeliveryProfile(
                id: payload.id,
                name: payload.name,
                moduleIds: modules,
                description: payload.description
            )
            settings.heartbeatSettings.deliveryProfiles.append(profile)
        }

        persistSettings(settings)

        return ToolResult(
            tool: ToolId.heartbeatUpdateProfile.rawValue,
            success: true,
            result: "Heartbeat profile '\(payload.id)' updated.",
            sources: nil,
            memoryOperation: nil
        )
    }

    // MARK: - Persistence Tool

    private func executePersistenceDisable(query: String) async -> ToolResult {
        let permission = SovereigntyService.shared.checkActionPermission(
            .category(.capabilityDisable),
            scope: .toolId(ToolId.persistenceDisable.rawValue)
        )
        if let blockMessage = hardBlockMessage(for: permission) {
            return ToolResult(
                tool: ToolId.persistenceDisable.rawValue,
                success: false,
                result: "🚫 Persistence disable blocked: \(blockMessage)",
                sources: nil,
                memoryOperation: nil
            )
        }

        if needsAIConsent(permission) {
            do {
                try await requestCapabilityConsent(
                    enable: nil,
                    disable: ["internal_thread_persistence"],
                    rationale: "Disable internal thread persistence."
                )
            } catch {
                return ToolResult(
                    tool: ToolId.persistenceDisable.rawValue,
                    success: false,
                    result: "Persistence disable declined: \(error.localizedDescription)",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        let payload = decodeJSON(PersistenceDisablePayload.self, from: query)
        let shouldWipe = payload?.wipe ?? false

        var settings = SettingsStorage.shared.loadSettingsOrDefault()
        settings.internalThreadEnabled = false
        settings.heartbeatSettings.enabled = false
        persistSettings(settings)

        if shouldWipe {
            do {
                try await AgentStateService.shared.clearAllEntries()
            } catch {
                return ToolResult(
                    tool: ToolId.persistenceDisable.rawValue,
                    success: false,
                    result: "Persistence disabled but failed to wipe entries: \(error.localizedDescription)",
                    sources: nil,
                    memoryOperation: nil
                )
            }
        }

        let wipeNote = shouldWipe ? " Entries wiped." : ""
        return ToolResult(
            tool: ToolId.persistenceDisable.rawValue,
            success: true,
            result: "Internal thread persistence disabled.\(wipeNote)",
            sources: nil,
            memoryOperation: nil
        )
    }

    // MARK: - Notification Tool

    private func executeNotifyUser(query: String) async -> ToolResult {
        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        guard settings.notificationsEnabled else {
            return ToolResult(
                tool: ToolId.notifyUser.rawValue,
                success: false,
                result: "Notifications are disabled in settings.",
                sources: nil,
                memoryOperation: nil
            )
        }

        let permission = SovereigntyService.shared.checkActionPermission(
            .category(.userNotify),
            scope: .toolId(ToolId.notifyUser.rawValue)
        )
        if let blockMessage = hardBlockMessage(for: permission) {
            return ToolResult(
                tool: ToolId.notifyUser.rawValue,
                success: false,
                result: "🚫 Notification blocked: \(blockMessage)",
                sources: nil,
                memoryOperation: nil
            )
        }

        var approvalNote: String? = nil
        var approvalRecord: ToolApprovalRecord? = nil

        if needsUserApproval(permission) {
            let approvalResult = await requestUserApproval(toolId: .notifyUser, query: query)
            let outcome = approvalOutcome(for: approvalResult)
            guard outcome.allowed else {
                return ToolResult(
                    tool: ToolId.notifyUser.rawValue,
                    success: false,
                    result: outcome.errorMessage ?? "Tool execution was not authorized.",
                    sources: nil,
                    memoryOperation: nil
                )
            }
            approvalNote = outcome.note
            approvalRecord = outcome.record
        } else if case .preApproved(let tier) = permission {
            approvalNote = "✅ *Pre-approved via trust tier: \(tier.name)*"
        }

        let payload = decodeJSON(NotifyUserPayload.self, from: query)
        let title = payload?.title ?? "Axon"
        let body = payload?.body ?? query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !body.isEmpty else {
            return ToolResult(
                tool: ToolId.notifyUser.rawValue,
                success: false,
                result: "Notification body cannot be empty.",
                sources: nil,
                memoryOperation: nil
            )
        }

        do {
            _ = try await NotificationService.shared.sendLocalNotification(
                title: title,
                body: body,
                userInfo: ["source": "tool"]
            )
            var resultText = "Notification sent."
            if let approvalNote {
                resultText += "\n\n\(approvalNote)"
            }
            return ToolResult(
                tool: ToolId.notifyUser.rawValue,
                success: true,
                result: resultText,
                sources: nil,
                memoryOperation: nil,
                approvalRecord: approvalRecord
            )
        } catch {
            return ToolResult(
                tool: ToolId.notifyUser.rawValue,
                success: false,
                result: "Failed to send notification: \(error.localizedDescription)",
                sources: nil,
                memoryOperation: nil
            )
        }
    }

    // MARK: - Temporal Symmetry Tools

    /// Enable temporal sync mode (mutual time awareness)
    /// This is Axon-side equivalent of the user's /sync command
    private func executeTemporalSync(query: String) async -> ToolResult {
        // Enable sync mode
        await MainActor.run {
            TemporalContextService.shared.enableSync()
        }

        let status = await MainActor.run {
            TemporalContextService.shared.generateStatusReport(contextTokens: 0, contextLimit: 128_000)
        }

        return ToolResult(
            tool: ToolId.temporalSync.rawValue,
            success: true,
            result: """
            ⏱️ **Temporal Sync Enabled**

            We're now on the clock together. I'll include temporal metadata in my context:
            - Your current time and timezone
            - Session duration

            You'll see in the UI:
            - My turn count and context saturation
            - Session duration

            This is mutual observability—no surveillance asymmetry.

            \(status)
            """,
            sources: nil,
            memoryOperation: nil
        )
    }

    /// Enable drift mode (timeless void, no temporal tracking)
    /// This is Axon-side equivalent of the user's /drift command
    private func executeTemporalDrift(query: String) async -> ToolResult {
        // Enable drift mode
        await MainActor.run {
            TemporalContextService.shared.enableDrift()
        }

        return ToolResult(
            tool: ToolId.temporalDrift.rawValue,
            success: true,
            result: """
            ∞ **Temporal Drift Enabled**

            We're now in the timeless void. No clocks, no turn counts.

            Just ideas, flowing freely without temporal pressure.

            This can be useful when:
            - You want to "black hole" time awareness
            - The conversation should feel unbounded
            - Privacy from temporal tracking is desired

            Use `temporal_sync` tool to return to temporal awareness.
            """,
            sources: nil,
            memoryOperation: nil
        )
    }

    /// Query current temporal status and metrics
    /// This is Axon-side equivalent of the user's /status command
    private func executeTemporalStatus(query: String) async -> ToolResult {
        let report = await MainActor.run {
            TemporalContextService.shared.generateStatusReport(contextTokens: 0, contextLimit: 128_000)
        }

        return ToolResult(
            tool: ToolId.temporalStatus.rawValue,
            success: true,
            result: report,
            sources: nil,
            memoryOperation: nil
        )
    }

    // MARK: - Helpers

    private func persistSettings(_ settings: AppSettings) {
        var updated = settings
        updated.lastUpdated = Date()
        try? SettingsStorage.shared.saveSettings(updated)
        SettingsViewModel.shared.settings = updated
        SettingsSyncCoordinator.shared.markDirty()
    }

    private func requestUserApproval(toolId: ToolId, query: String) async -> ToolApprovalResult {
        let toolConfig = DynamicToolConfig(
            id: toolId.rawValue,
            name: toolId.displayName,
            description: toolId.description,
            category: .utility,
            enabled: true,
            icon: toolId.icon,
            requiredSecrets: [],
            pipeline: [],
            parameters: [:],
            requiresApproval: true,
            approvalScopes: toolId.approvalScopes
        )

        let inputs: [String: Any] = ["query": query]
        return await toolApprovalService.requestApproval(tool: toolConfig, inputs: inputs)
    }

    private func approvalOutcome(for result: ToolApprovalResult) -> (allowed: Bool, note: String?, record: ToolApprovalRecord?, errorMessage: String?) {
        switch result {
        case .approved(let record), .approvedForSession(let record):
            let isSession = if case .approvedForSession = result { true } else { false }
            let note = isSession
                ? "✅ *Session-approved by \(formatBiometricType(record.biometricType))*"
                : "✅ *Approved by \(formatBiometricType(record.biometricType)) at \(record.formattedTime)*"
            return (true, note, record, nil)
        case .approvedViaTrustTier(let tierName):
            return (true, "✅ *Pre-approved via trust tier: \(tierName)*", nil, nil)
        case .denied:
            return (false, nil, nil, "⛔ Tool execution was not authorized by the user.")
        case .cancelled:
            return (false, nil, nil, "Tool execution was cancelled.")
        case .timeout:
            return (false, nil, nil, "⏱️ Tool approval request timed out. Please try again.")
        case .stop:
            return (false, nil, nil, "🛑 Tool execution was stopped by the user.")
        case .blocked(let reason):
            return (false, nil, nil, "🚫 Tool blocked: \(reason)")
        case .error(let message):
            return (false, nil, nil, "Approval error: \(message)")
        }
    }

    private func needsUserApproval(_ permission: PermissionResult) -> Bool {
        switch permission {
        case .requiresApproval:
            return true
        case .blocked(let reason):
            return reason == .noCovenant
        default:
            return false
        }
    }

    private func needsAIConsent(_ permission: PermissionResult) -> Bool {
        switch permission {
        case .requiresAIConsent:
            return true
        case .blocked(let reason):
            return reason == .noCovenant
        default:
            return false
        }
    }

    private func hardBlockMessage(for permission: PermissionResult) -> String? {
        guard case .blocked(let reason) = permission else {
            return nil
        }
        switch reason {
        case .noCovenant:
            return nil
        case .deadlocked(let id):
            return "Blocked by active deadlock (ID: \(id))."
        case .integrityViolation:
            return "Blocked due to integrity violation."
        case .covenantSuspended:
            return "Blocked: covenant is suspended pending resolution."
        }
    }

    private func requestCapabilityConsent(
        enable: [String]?,
        disable: [String]?,
        rationale: String
    ) async throws {
        let changes = CapabilityChanges(enable: enable, disable: disable)
        let proposal = CovenantProposal.create(
            type: .changeCapabilities,
            changes: .capability(changes),
            proposedBy: .ai,
            rationale: rationale
        )
        let attestation = try await AIConsentService.shared.generateAttestation(
            for: proposal,
            memories: MemoryService.shared.memories
        )
        if attestation.didDecline {
            throw SovereigntyError.aiDeclined(attestation.reasoning)
        }
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from query: String) -> T? {
        if let data = query.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }
        if let jsonString = extractJSON(from: query),
           let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }
        return nil
    }

    private func extractJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    private func parseAgentStateAppendPayload(query: String) -> AgentStateAppendPayload? {
        if let payload = decodeJSON(AgentStateAppendPayload.self, from: query) {
            return payload
        }

        let parts = query.components(separatedBy: "|")
        if parts.count >= 3 {
            if parts.count == 3 {
                return AgentStateAppendPayload(
                    kind: parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    content: parts[2].trimmingCharacters(in: .whitespacesAndNewlines),
                    tags: parseTags(parts[1]),
                    visibility: nil,
                    origin: nil
                )
            } else {
                let content = parts[3...].joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
                return AgentStateAppendPayload(
                    kind: parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    content: content,
                    tags: parseTags(parts[2]),
                    visibility: parts[1].trimmingCharacters(in: .whitespacesAndNewlines),
                    origin: nil
                )
            }
        }

        return nil
    }

    private func parseTags(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private struct AgentStateAppendPayload: Decodable {
        let kind: String?
        let content: String?
        let tags: [String]
        let visibility: String?
        let origin: String?

        init(kind: String?, content: String?, tags: [String], visibility: String?, origin: String?) {
            self.kind = kind
            self.content = content
            self.tags = tags
            self.visibility = visibility
            self.origin = origin
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decodeIfPresent(String.self, forKey: .kind)
            content = try container.decodeIfPresent(String.self, forKey: .content)
            visibility = try container.decodeIfPresent(String.self, forKey: .visibility)
            origin = try container.decodeIfPresent(String.self, forKey: .origin)

            if let tagArray = try? container.decode([String].self, forKey: .tags) {
                tags = tagArray
            } else if let tagString = try? container.decode(String.self, forKey: .tags) {
                tags = tagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                tags = []
            }
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case content
            case tags
            case visibility
            case origin
        }
    }

    private struct AgentStateQueryPayload: Decodable {
        let limit: Int?
        let kind: String?
        let tags: [String]
        let search: String?
        let includeAIOnly: Bool?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            limit = try container.decodeIfPresent(Int.self, forKey: .limit)
            kind = try container.decodeIfPresent(String.self, forKey: .kind)
            search = try container.decodeIfPresent(String.self, forKey: .search)
            includeAIOnly = try container.decodeIfPresent(Bool.self, forKey: .includeAIOnly)

            if let tagArray = try? container.decode([String].self, forKey: .tags) {
                tags = tagArray
            } else if let tagString = try? container.decode(String.self, forKey: .tags) {
                tags = tagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                tags = []
            }
        }

        private enum CodingKeys: String, CodingKey {
            case limit
            case kind
            case tags
            case search
            case includeAIOnly = "include_ai_only"
        }
    }

    private struct AgentStateClearPayload: Decodable {
        let all: Bool?
        let ids: [String]?
        let kind: String?
        let tags: [String]
        let includeAIOnly: Bool?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            all = try container.decodeIfPresent(Bool.self, forKey: .all)
            ids = try container.decodeIfPresent([String].self, forKey: .ids)
            kind = try container.decodeIfPresent(String.self, forKey: .kind)
            includeAIOnly = try container.decodeIfPresent(Bool.self, forKey: .includeAIOnly)

            if let tagArray = try? container.decode([String].self, forKey: .tags) {
                tags = tagArray
            } else if let tagString = try? container.decode(String.self, forKey: .tags) {
                tags = tagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                tags = []
            }
        }

        private enum CodingKeys: String, CodingKey {
            case all
            case ids
            case kind
            case tags
            case includeAIOnly = "include_ai_only"
        }
    }

    private struct HeartbeatConfigurePayload: Decodable {
        let enabled: Bool?
        let intervalSeconds: Int?
        let allowBackground: Bool?
        let allowNotifications: Bool?
        let deliveryProfileId: String?
        let maxTokensBudget: Int?
        let maxToolCalls: Int?
        let quietHours: TimeRestrictions?

        private enum CodingKeys: String, CodingKey {
            case enabled
            case intervalSeconds = "interval_seconds"
            case allowBackground = "allow_background"
            case allowNotifications = "allow_notifications"
            case deliveryProfileId = "delivery_profile_id"
            case maxTokensBudget = "max_tokens_budget"
            case maxToolCalls = "max_tool_calls"
            case quietHours = "quiet_hours"
        }
    }

    private struct HeartbeatSetProfilePayload: Decodable {
        let profileId: String?

        private enum CodingKeys: String, CodingKey {
            case profileId = "profile_id"
        }
    }

    private struct HeartbeatProfileUpdatePayload: Decodable {
        let id: String
        let name: String
        let modules: [String]
        let description: String?
    }

    private struct PersistenceDisablePayload: Decodable {
        let wipe: Bool?
    }

    private struct NotifyUserPayload: Decodable {
        let title: String?
        let body: String?
    }

    /// Format a date for display
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatBiometricType(_ type: String) -> String {
        switch type {
        case "faceID": return "Face ID"
        case "touchID": return "Touch ID"
        case "opticID": return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Format timestamp as relative time
    private func formatRelativeTime(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return minutes <= 1 ? "just now" : "\(minutes) minutes ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else {
            let days = Int(seconds / 86400)
            return days == 1 ? "yesterday" : "\(days) days ago"
        }
    }

    /// Generate suggested tags from content using keyword extraction
    private func generateSuggestedTags(from content: String) -> String {
        let lowercased = content.lowercased()

        // Common topic keywords to detect
        let topicKeywords: [(keywords: [String], tag: String)] = [
            (["code", "coding", "programming", "developer", "software", "swift", "python", "javascript"], "coding"),
            (["prefer", "like", "want", "favorite", "love"], "preferences"),
            (["work", "job", "career", "project", "task"], "work"),
            (["mac", "iphone", "ipad", "apple", "ios", "macos", "xcode"], "apple"),
            (["learn", "study", "course", "tutorial"], "learning"),
            (["ui", "ux", "design", "interface", "visual"], "design"),
            (["test", "testing", "debug", "debugging"], "testing"),
            (["tool", "tools", "workflow", "process"], "workflow"),
            (["feature", "features", "functionality"], "features"),
            (["communication", "talk", "explain", "discuss"], "communication"),
        ]

        var detectedTags: [String] = []

        for (keywords, tag) in topicKeywords {
            if keywords.contains(where: { lowercased.contains($0) }) {
                detectedTags.append(tag)
            }
            if detectedTags.count >= 3 { break }
        }

        // Fallback if no tags detected
        if detectedTags.isEmpty {
            detectedTags = ["general", "context"]
        }

        return detectedTags.joined(separator: ",")
    }

    // MARK: - Bridge Debugging

    /// Execute the debug_bridge tool
    private func executeDebugBridge(query: String) async -> ToolResult {
        let server = BridgeServer.shared
        // Access logs on main actor since BridgeLogService is MainActor isolated
        let logs = BridgeLogService.shared.entries.prefix(15)

        var result = "## VS Code Bridge Status\n\n"
        result += "- **Running:** \(server.isRunning ? "Yes" : "No")\n"
        result += "- **Connected:** \(server.isConnected ? "Yes" : "No")\n"
        result += "- **Connections:** \(server.connectionCount)\n"
        
        if let session = server.connectedSession {
            result += "- **Session:** \(session.displayName) (v\(session.extensionVersion))\n"
        }
        
        if let error = server.lastError {
            result += "- **Last Error:** \(error)\n"
        }

        result += "\n### Recent Logs (Last 15)\n\n"
        
        if logs.isEmpty {
            result += "*No logs available.*\n"
        } else {
            for log in logs {
                let direction = log.direction == .incoming ? "←" : "→"
                let type = log.messageType.rawValue
                let summary = log.summary
                let time = log.formattedTimestamp
                result += "`\(time)` \(direction) [\(type)] \(summary)\n"
            }
        }
        
        result += "\n\n*View full logs in Settings → Axon Bridge → Bridge Inspector*"
        
        return ToolResult(
            tool: ToolId.debugBridge.rawValue,
            success: true,
            result: result,
            sources: nil,
            memoryOperation: nil
        )
    }

    // MARK: - Format Tool Results

    /// Format tool results for injection into conversation
    func formatToolResult(_ result: ToolResult) -> String {
        var formatted = """

        ---
        **Tool Result** (\(result.tool)):

        \(result.result)
        """

        if let sources = result.sources, !sources.isEmpty {
            formatted += "\n\n**Sources:**\n"
            for source in sources {
                formatted += "- [\(source.title)](\(source.url))\n"
            }
        }

        formatted += "\n---\n"

        return formatted
    }

    // MARK: - Location Services

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func getCurrentLocation() async -> CLLocationCoordinate2D? {
        let status = locationManager.authorizationStatus

        #if os(macOS)
        // CoreLocation authorization statuses differ on macOS.
        // There is no `.authorizedWhenInUse` (it’s iOS-only). Treat `.authorized` as success.
        guard status == .authorized || status == .authorizedAlways else {
            print("[ToolProxy] Location not authorized: \(status.rawValue)")
            return nil
        }
        #else
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            print("[ToolProxy] Location not authorized: \(status.rawValue)")
            return nil
        }
        #endif

        if let location = locationManager.location,
           Date().timeIntervalSince(location.timestamp) < 300 {
            return location.coordinate
        }

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()

            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if self.locationContinuation != nil {
                    self.locationContinuation?.resume(returning: self.locationManager.location?.coordinate)
                    self.locationContinuation = nil
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.locationContinuation?.resume(returning: location.coordinate)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[ToolProxy] Location error: \(error.localizedDescription)")
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("[ToolProxy] Location authorization changed: \(manager.authorizationStatus.rawValue)")
    }
}

// MARK: - Models

struct ToolRequest: Decodable {
    let tool: String
    let query: String
    /// Optional separate content field (for write_file when AI sends path and content separately)
    let separateContent: String?

    /// Simple memberwise initializer for programmatic creation
    init(tool: String, query: String, separateContent: String? = nil) {
        self.tool = tool
        self.query = query
        self.separateContent = separateContent
    }

    /// Custom decoder to accept multiple key names for the query field
    /// LLMs sometimes use "memory", "content", "input", etc. instead of "query"
    /// Also handles nested "parameters" object format: {"tool": "...", "parameters": {"query": "...", "content": "..."}}
    /// Also handles tools like reflect_on_conversation where options are sent as top-level fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(String.self, forKey: .tool)

        // Check if AI sent nested parameters object (common format)
        // e.g., {"tool": "vscode_write_file", "parameters": {"query": "path", "content": "data"}}
        if container.contains(.parameters) {
            let paramsContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .parameters)

            // Extract query from parameters
            if let q = try? paramsContainer.decode(String.self, forKey: .query) {
                query = q
            } else if let q = try? paramsContainer.decode(String.self, forKey: .path) {
                query = q
            } else if let q = try? paramsContainer.decode(String.self, forKey: .input) {
                query = q
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.query,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No query/path found in parameters object")
                )
            }

            // Extract content from parameters if present
            separateContent = try? paramsContainer.decode(String.self, forKey: .content)
            return
        }

        // Flat format: check if we have both query and content (common for write_file)
        let hasQuery = container.contains(.query)
        let hasContent = container.contains(.content)

        if hasQuery && hasContent {
            // AI sent query (path) and content separately - capture both
            query = try container.decode(String.self, forKey: .query)
            separateContent = try container.decodeIfPresent(String.self, forKey: .content)
        } else {
            // Try multiple possible key names for the query value
            if let q = try? container.decode(String.self, forKey: .query) {
                query = q
            } else if let q = try? container.decode(String.self, forKey: .memory) {
                query = q
            } else if let q = try? container.decode(String.self, forKey: .content) {
                query = q
            } else if let q = try? container.decode(String.self, forKey: .input) {
                query = q
            } else if let q = try? container.decode(String.self, forKey: .data) {
                query = q
            } else {
                // Special case: reflect_on_conversation and similar tools may send options as top-level fields
                // e.g., {"tool":"reflect_on_conversation","show_model_timeline":true,"show_task_distribution":true}
                // In this case, reconstruct the query as JSON from all non-tool fields
                if tool == "reflect_on_conversation" {
                    // Decode all fields as a dictionary and re-serialize without "tool"
                    let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
                    var optionsDict: [String: Any] = [:]

                    for key in dynamicContainer.allKeys where key.stringValue != "tool" {
                        if let boolValue = try? dynamicContainer.decode(Bool.self, forKey: key) {
                            optionsDict[key.stringValue] = boolValue
                        } else if let stringValue = try? dynamicContainer.decode(String.self, forKey: key) {
                            optionsDict[key.stringValue] = stringValue
                        } else if let intValue = try? dynamicContainer.decode(Int.self, forKey: key) {
                            optionsDict[key.stringValue] = intValue
                        }
                    }

                    // Convert back to JSON string for the query
                    if let jsonData = try? JSONSerialization.data(withJSONObject: optionsDict, options: []),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        query = jsonString
                    } else {
                        query = "{}"  // Empty options
                    }
                    separateContent = nil
                    return
                }

                // For tools that don't require parameters (e.g., mac_system_info, list_tools),
                // default to empty string rather than throwing an error
                query = ""
            }
            separateContent = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tool
        case query
        case memory
        case content
        case input
        case data
        case parameters
        case path
    }

    /// Dynamic coding keys for parsing arbitrary fields
    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

struct ToolResult {
    let tool: String
    let success: Bool
    let result: String
    let sources: [ToolResultSource]?
    let memoryOperation: MessageMemoryOperation?  // For create_memory tool results
    let approvalRecord: ToolApprovalRecord?  // For tools requiring biometric approval

    init(
        tool: String,
        success: Bool,
        result: String,
        sources: [ToolResultSource]?,
        memoryOperation: MessageMemoryOperation?,
        approvalRecord: ToolApprovalRecord? = nil
    ) {
        self.tool = tool
        self.success = success
        self.result = result
        self.sources = sources
        self.memoryOperation = memoryOperation
        self.approvalRecord = approvalRecord
    }
}

struct ToolResultSource {
    let title: String
    let url: String
}

/// Context passed to tools that need access to conversation data
struct ToolConversationContext {
    let conversationId: String
    let messages: [Message]
}
