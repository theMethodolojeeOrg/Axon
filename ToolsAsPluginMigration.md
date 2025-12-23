# Axon Plugin-Based Tool Architecture (ToolsV2)

## Summary

Build a **parallel** plugin-based tool system alongside the existing architecture. No existing code is modified - all new files. A toggle switches between ToolsV1 (current) and ToolsV2 (plugin system).

**Key Principles**:
- Decode engine "just knows what to do" - tool authors only write JSON
- Zero risk to existing system - parallel architecture
- Toggle-based testing - flip between V1 and V2
- Old code as reference - never delete during development

---

## Directory Structure

```
AxonTools/
  _index.json                    # Master discovery index
  _schema/tool-manifest-v1.json  # Validation schema

  core/                          # Shipped with app (read-only)
    memory/
      create_memory/tool.json
      conversation_search/tool.json
      reflect_on_conversation/tool.json
    agent_state/
      agent_state_append/tool.json
      agent_state_query/tool.json
      agent_state_clear/tool.json
    heartbeat/
      heartbeat_configure/tool.json
      heartbeat_run_once/tool.json
    sovereignty/
      query_covenant/tool.json
      propose_covenant_change/tool.json
    sub_agents/
      spawn_scout/tool.json
      spawn_mechanic/tool.json
      spawn_designer/tool.json
      query_job_status/tool.json
      accept_job_result/tool.json
      terminate_job/tool.json
    temporal/
      temporal_sync/tool.json
      temporal_drift/tool.json
      temporal_status/tool.json
    discovery/
      list_tools/tool.json
      get_tool_details/tool.json

  providers/                     # Provider-native wrappers
    gemini/
      google_search/tool.json
      code_execution/tool.json
      url_context/tool.json
    openai/
      web_search/tool.json
      image_generation/tool.json
      deep_research/tool.json

  ports/                         # External app integrations (from PortRegistry)
    notes/
      obsidian_new_note/tool.json
      bear_create/tool.json
    tasks/
      things_add/tool.json
      todoist_add/tool.json
    automation/
      shortcuts_run/tool.json

  community/                     # Imported tools
  custom/                        # User-created tools
```

---

## Tool Manifest Schema (tool.json)

```json
{
  "version": "1.0.0",
  "tool": {
    "id": "create_memory",
    "name": "Create Memory",
    "description": "Save important information to memory",
    "category": "memory",
    "icon": { "sfSymbol": "brain.head.profile" },
    "requiresApproval": false,
    "trustTierCategory": "memory_add"
  },

  "parameters": {
    "type": {
      "type": "enum",
      "required": true,
      "enum": ["allocentric", "egoic"],
      "enumDescriptions": {
        "allocentric": "Facts ABOUT the user",
        "egoic": "What WORKS for the AI"
      }
    },
    "content": {
      "type": "string",
      "required": true,
      "minLength": 10
    }
  },

  "inputFormat": {
    "style": "pipe_delimited",
    "pattern": "{{type}}|{{confidence}}|{{tags}}|{{content}}"
  },

  "execution": {
    "type": "internal_handler",
    "handler": "MemoryToolHandler"
  },

  "ai": {
    "systemPromptSection": "### create_memory\nSave info to memory...",
    "usageExamples": [
      { "description": "Remember preference", "input": "allocentric|0.9|ios|User prefers Swift" }
    ],
    "whenToUse": ["User states a preference"],
    "whenNotToUse": ["Temporary information"]
  },

  "ui": {
    "inputForm": {
      "fields": [
        { "param": "type", "widget": "segmented" },
        { "param": "content", "widget": "textarea", "rows": 3 }
      ]
    },
    "resultDisplay": {
      "sections": [
        { "type": "header", "title": "Memory Saved" },
        { "type": "text", "source": "{{content}}" }
      ]
    }
  },

  "sovereignty": {
    "actionCategory": "memory_add",
    "approvalDescription": "Create new {{type}} memory"
  }
}
```

---

## Core Services to Create

### New Files in `/Axon/Services/Tools/Plugin/`

| File | Purpose |
|------|---------|
| `ToolManifest.swift` | Swift types matching tool.json schema |
| `ToolPluginLoader.swift` | Discovers & loads tool folders from bundled/iCloud/imports |
| `ToolManifestDecoder.swift` | Parses tool.json with validation |
| `ToolUIRenderer.swift` | Generates SwiftUI from JSON ui config |
| `ToolExecutionRouter.swift` | Routes to internal_handler/pipeline/provider/url_scheme |
| `ToolIndexService.swift` | Search index, system prompt generation, sovereignty integration |
| `ToolImportService.swift` | Import from GitHub/iCloud/Axon Store |

### Handler Protocol

```swift
protocol ToolHandler {
    func execute(inputs: [String: Any], context: ToolContext?) async -> ToolResult
}

// Register handlers in ToolExecutionRouter
handlers["MemoryToolHandler"] = MemoryToolHandler()
handlers["HeartbeatToolHandler"] = HeartbeatToolHandler()
handlers["GeminiNativeHandler"] = GeminiNativeHandler()
// ... one per internal tool
```

---

## UI DSL Widgets

| Widget | Maps To |
|--------|---------|
| `text_field` | TextField |
| `textarea` | TextEditor |
| `slider` | Slider (with optional value display) |
| `segmented` | Picker(.segmented) |
| `tag_input` | Custom TagInputView |
| `toggle` | Toggle |
| `picker` | Picker |
| `date_picker` | DatePicker |

Template syntax: `{{param}}`, `{{param|percent}}`, `{{result.field}}`

---

## Execution Types

1. **internal_handler** - Routes to registered Swift ToolHandler
2. **pipeline** - Uses existing DynamicToolExecutionEngine (model_call, api_call, transform, etc.)
3. **provider_native** - Passes to Gemini/OpenAI SDK
4. **url_scheme** - Opens URL with parameter substitution (for ports)

---

## Import Sources

1. **Bundled** - Read-only in app bundle
2. **iCloud** - Synced via CloudKit
3. **GitHub** - Import from repo URL, validate manifest, download to community/
4. **Axon Store** - Future central catalog (redirects to GitHub internally)

Security: Validate execution type, check API endpoints against allowlist, require approval for imported tools.

---

## Build Order (Parallel Architecture)

**Strategy**: Build ToolsV2 in a completely separate directory. Add a toggle in Settings to switch. Old code stays untouched as reference.

### Phase 1: Foundation (~5 files)
1. Create `/Axon/Services/ToolsV2/` directory (NOT in existing Tools/)
2. `ToolManifestTypes.swift` - All Swift types matching tool.json schema
3. `ToolPluginLoader.swift` - Discovers & loads tool folders
4. `ToolManifestDecoder.swift` - Parses + validates tool.json
5. `ToolsV2Toggle.swift` - Toggle between V1/V2 (stored in Settings)

### Phase 2: Execution Engine (~4 files)
1. `ToolExecutionRouterV2.swift` - Routes based on execution type
2. `ToolHandlerProtocol.swift` - Protocol + base class for handlers
3. `InternalHandlerRegistry.swift` - Maps handler names → implementations
4. `ToolResultTypes.swift` - Unified result types

### Phase 3: Create Tool Handlers (1 file per handler type)
```
/Axon/Services/ToolsV2/Handlers/
  MemoryToolHandler.swift
  AgentStateToolHandler.swift
  HeartbeatToolHandler.swift
  SovereigntyToolHandler.swift
  SubAgentToolHandler.swift
  TemporalToolHandler.swift
  DiscoveryToolHandler.swift
  NotificationToolHandler.swift
  GeminiNativeHandler.swift
  OpenAINativeHandler.swift
  URLSchemeHandler.swift        # For ports
  PipelineHandler.swift         # Wraps DynamicToolExecutionEngine
```

### Phase 4: Create tool.json Files
```
/Axon/Resources/AxonTools/      # Bundled with app
  core/memory/create_memory/tool.json
  core/memory/conversation_search/tool.json
  ... (all 40+ tools)
  providers/gemini/google_search/tool.json
  ... (all provider tools)
  ports/notes/obsidian_new_note/tool.json
  ... (all 60+ ports)
```

### Phase 5: Integration (~3 files)
1. `ToolIndexServiceV2.swift` - Search, system prompt generation
2. `ToolApprovalBridgeV2.swift` - Integrate with existing ToolApprovalService
3. `ToolSovereigntyBridgeV2.swift` - Integrate with existing SovereigntyService

### Phase 6: UI Layer (~3 files)
1. `ToolUIRenderer.swift` - Generates SwiftUI from JSON UI config
2. `ToolSettingsViewV2.swift` - Browse/enable/disable tools
3. `ToolImportServiceV2.swift` - Import from GitHub/iCloud/Store

### Phase 7: Wire Up Toggle
1. Add V1/V2 toggle in General Settings
2. In conversation orchestrators, check toggle and route to appropriate service
3. Test by flipping toggle back and forth

---

## Files to Create (Zero Modifications to Existing)

### Swift Files (~15 new files)

```
Axon/Services/ToolsV2/
  ToolManifestTypes.swift         # Schema types
  ToolPluginLoader.swift          # Discovery & loading
  ToolManifestDecoder.swift       # Parsing & validation
  ToolsV2Toggle.swift             # V1/V2 switch
  ToolExecutionRouterV2.swift     # Routing
  ToolHandlerProtocol.swift       # Handler interface
  InternalHandlerRegistry.swift   # Handler lookup
  ToolResultTypes.swift           # Result models
  ToolIndexServiceV2.swift        # Index & prompts
  ToolApprovalBridgeV2.swift      # Approval integration
  ToolSovereigntyBridgeV2.swift   # Sovereignty integration
  ToolUIRenderer.swift            # JSON → SwiftUI
  ToolImportServiceV2.swift       # Import flow

Axon/Services/ToolsV2/Handlers/
  MemoryToolHandler.swift
  AgentStateToolHandler.swift
  HeartbeatToolHandler.swift
  SovereigntyToolHandler.swift
  SubAgentToolHandler.swift
  TemporalToolHandler.swift
  DiscoveryToolHandler.swift
  NotificationToolHandler.swift
  GeminiNativeHandler.swift
  OpenAINativeHandler.swift
  URLSchemeHandler.swift
  PipelineHandler.swift
```

### Resource Files (~100+ tool.json files)

```
Axon/Resources/AxonTools/
  _index.json
  _schema/tool-manifest-v1.json
  core/memory/create_memory/tool.json
  core/memory/conversation_search/tool.json
  core/memory/reflect_on_conversation/tool.json
  core/agent_state/agent_state_append/tool.json
  core/agent_state/agent_state_query/tool.json
  core/agent_state/agent_state_clear/tool.json
  core/heartbeat/heartbeat_configure/tool.json
  core/heartbeat/heartbeat_run_once/tool.json
  ... (continue for all core tools)
  providers/gemini/google_search/tool.json
  providers/gemini/code_execution/tool.json
  providers/gemini/url_context/tool.json
  providers/openai/web_search/tool.json
  providers/openai/image_generation/tool.json
  ... (continue for all provider tools)
  ports/notes/obsidian_new_note/tool.json
  ports/notes/bear_create/tool.json
  ports/tasks/things_add/tool.json
  ... (continue for all 60+ ports)
```

### Files to REFERENCE (not modify)

| File | Reference Purpose |
|------|-------------------|
| `Axon/Models/Settings.swift` (lines 1997-2189) | ToolId enum definitions |
| `Axon/Services/Tools/ToolProxyService.swift` | Handler implementations |
| `Axon/Services/AppIntents/Consumer/PortRegistry.swift` | Port definitions |
| `Axon/Services/Tools/DynamicToolConfiguration.swift` | Pipeline DSL |
| `Axon/Services/Sovereignty/SovereigntyService.swift` | Integration patterns |
| `Axon/Services/Tools/ToolApprovalService.swift` | Approval flow |

---

## Benefits

1. **Infinite scalability** - Just add folders
2. **No Swift knowledge needed** - JSON only
3. **Hot reload** - Change tool.json, see results
4. **Unified sovereignty** - All tools use same trust tier system
5. **Tool ecosystem** - Import/share/store
6. **Zero-risk development** - V1 always available via toggle
7. **Reference preserved** - Old code as documentation

---

## Recommended Start

Begin with Phase 1 (Foundation) creating these files in order:

1. **ToolManifestTypes.swift** - Define all the Swift types that mirror tool.json structure
2. **ToolManifestDecoder.swift** - Parse and validate tool.json files
3. **ToolPluginLoader.swift** - Load tools from bundled/Documents/iCloud locations
4. **One example tool.json** (create_memory) - Validate the schema works end-to-end
5. **ToolsV2Toggle.swift** - Simple UserDefaults toggle for switching

This gives us a working foundation to validate before building handlers.

---

## Implementation Progress

### ✅ Phase 1: Foundation — COMPLETE
*Completed December 2024*

- `ToolManifestTypes.swift` — All Swift types matching tool.json schema
- `ToolPluginLoader.swift` — Discovers & loads tool folders  
- `ToolManifestDecoder.swift` — Parses + validates tool.json
- Settings integration for V1/V2 toggle

### ✅ Phase 2: Execution Engine — COMPLETE
*Completed December 2024*

- `ToolExecutionRouterV2.swift` — Routes based on execution type
- `ToolHandlerV2.swift` — Protocol + context types
- `InternalHandlerRegistryV2.swift` — Maps handler IDs → implementations
- `ToolResultV2.swift` — Unified result types with success/failure helpers

### ✅ Phase 3: Tool Handlers — COMPLETE
*Completed December 23, 2024*

Created **11 V2 handlers** in `/Axon/Services/ToolsV2/Handlers/`:

| Handler | Handler ID | Tools Covered |
|---------|-----------|---------------|
| `MemoryHandler.swift` | `memory` | create_memory, conversation_search |
| `AgentStateHandler.swift` | `agent_state` | agent_state_*, persistence_disable |
| `HeartbeatHandler.swift` | `heartbeat` | heartbeat_configure/run_once/set_delivery_profile/update_profile |
| `SovereigntyHandler.swift` | `sovereignty` | query_covenant, propose_covenant_change |
| `NotificationHandler.swift` | `notification` | notify_user |
| `TemporalHandler.swift` | `temporal` | temporal_sync/drift/status |
| `SubAgentHandler.swift` | `sub_agent` | spawn_*, query_job_status, accept_job_result, terminate_job |
| `DiscoveryHandler.swift` | `discovery` | list_tools, get_tool_details, discover_ports, invoke_port |
| `DevicePresenceHandler.swift` | `device_presence` | device presence & handoff tools |
| `SystemStateHandler.swift` | `system_state` | query/change_system_state |
| `BridgeHandler.swift` | `bridge` | mac_* tools (15 bridge tools via MacSystemToolExecutor) |

All handlers:
- Registered in `InternalHandlerRegistryV2.registerBuiltInHandlers()`
- Conform to `ToolHandlerV2` protocol
- Build verified with 0 errors

**API Compatibility Fixes Applied:**
- `TemporalSymmetryService` → `TemporalContextService`
- `DeviceIdentity.deviceName` → `deviceInfo?.deviceName`
- `HeartbeatDeliveryProfile.modules` → `moduleIds`
- `HeartbeatRunResult` struct pattern matching
- `AppSettings.selectedModelId` → `defaultModel`
- `PortRegistryEntry.buildURL` → `generateUrl`

### ✅ Phase 4: Create tool.json Files — COMPLETE
*Completed December 23, 2024*

Created **80 tool.json manifests** in `/Axon/Resources/AxonTools/`:

| Category | Tools |
|----------|-------|
| **Core Tools (33)** | memory (3), agent_state (4), heartbeat (4), discovery (4), notification (1), system_state (2), temporal (3), device_presence (4), sub_agents (6), sovereignty (2), debug (1) |
| **System Tools (16)** | mac_system_info, mac_processes, mac_disk_usage, mac_clipboard_*, mac_notification, mac_spotlight_search, mac_file_*, mac_app_*, mac_screenshot, mac_network_info, mac_ping, mac_shell |
| **Provider Tools (31)** | Gemini (18), OpenAI (11), xAI (5), zAI (5) - see Provider Handlers section for details |

Master index created: `_index.json`

### ✅ Phase 5: Integration — COMPLETE
*Completed December 23, 2024*

- `ToolIndexServiceV2.swift` — Search index and system prompt generation
- `ToolApprovalBridgeV2.swift` — Bridge V2 tools to existing ToolApprovalService
- `ToolSovereigntyBridgeV2.swift` — Bridge V2 tools to existing SovereigntyService
- `ToolExecutionRouterV2.swift` — Updated to use new bridges for approval/sovereignty checks

### ✅ Phase 6: UI Layer — COMPLETE
*Completed December 23, 2024*

- `ToolUIRenderer.swift` — Generates SwiftUI views from JSON `ui` config in tool manifests
  - Widget support: text_field, textarea, slider, segmented, tag_input, toggle, picker, date_picker, stepper, color_picker
  - Result display: header, text, code, list, keyValue, divider, spacer, image, link, badge, progress
  - Template resolution: `{{param}}` and `{{result.field}}` syntax
- `ToolSettingsViewV2.swift` — Browse, search, filter, and enable/disable tools
  - V1/V2 toggle in settings
  - Tool detail sheet with metadata
  - Category filtering and search
- `ToolImportServiceV2.swift` — Import from GitHub/iCloud/local files
  - Security validation for imported tools
  - Manifest parsing and installation to community folder

### ✅ Phase 7: Wire Up Toggle — COMPLETE
*Completed December 23, 2024*

- `ToolSystemQuickToggle` added to AutomationSettingsView
- `ToolSettingsViewV2` or `ToolSettingsView` shown based on toggle
- `ToolRoutingService.swift` — Unified entry point for tool operations
  - Routes to V1 or V2 based on `ToolsV2Toggle.shared.isV2Active`
  - System prompt generation for both systems
  - Tool execution routing
  - Tool request parsing

---

## ✅ Provider Handlers — COMPLETE
*Completed December 23, 2024*

Created **4 provider handlers** in `/Axon/Services/ToolsV2/Handlers/`:

| Handler | Handler ID | Tools |
|---------|-----------|-------|
| `GeminiHandler.swift` | `gemini` | 18 tools (see below) |
| `OpenAIHandler.swift` | `openai` | 10 tools (see below) |
| `XAIHandler.swift` | `xai` | 5 tools (see below) |
| `ZAIHandler.swift` | `zai` | 5 tools (see below) |

All handlers registered in `InternalHandlerRegistryV2.registerBuiltInHandlers()`

### Provider Tool Details

**GeminiHandler (18 tools):**
- Search: `google_search`, `gemini_google_search`
- Code: `code_execution`, `gemini_code_execution`
- Web: `url_context`, `gemini_url_context`
- Maps: `google_maps`, `gemini_google_maps`
- Files: `file_search`, `gemini_file_search`
- Video Gen: `gemini_veo`, `gemini_video_gen`
- Image Gen: `gemini_image_generation`
- Research: `gemini_deep_research`
- Computer: `gemini_computer_use`
- Embeddings: `gemini_embeddings`
- Audio: `gemini_speech_to_text`, `gemini_text_to_speech`
- Video Analysis: `gemini_video_understanding`

**OpenAIHandler (10 tools):**
- Search: `openai_web_search`, `web_search`
- Image Gen: `openai_image_gen`, `openai_image_generation`, `image_generation`
- Research: `openai_deep_research`, `deep_research`
- Video Gen: `openai_video_gen`, `openai_video_generation`, `video_generation`
- Computer: `openai_computer_use`
- Embeddings: `openai_embeddings`
- Audio: `openai_speech_to_text`, `openai_text_to_speech`

**XAIHandler (5 tools):**
- Search: `xai_web_search`, `grok_web_search`, `web_search`
- X/Twitter: `grok_x_search`
- Image Gen: `grok_image_generation`
- Code: `grok_code_execution`

**ZAIHandler (5 tools):**
- Search: `zai_web_search`, `glm_web_search`, `web_search`
- Image Gen: `glm_cogview_4`
- Video Gen: `glm_cogvideo_3`
- Audio: `glm_speech_to_text`

### Provider Tool Manifests

Updated `_index.json` with **31 provider tools** (up from 12):
- Gemini: 18 tool manifests in `/googlegemini/`
- OpenAI: 11 tool manifests in `/openai/`
- xAI: 5 tool manifests in `/xai/`
- zAI: 5 tool manifests in `/zai/`

**Total tools: 80** (33 core + 16 system + 31 provider)

### Provider Native Execution Flow

The `ToolExecutionRouterV2` routes `provider_native` tools automatically:

1. Tool manifest specifies `execution.type = "provider_native"` and `execution.provider = "gemini"` (or `openai`, `xai`, `zai`)
2. Router looks up handler by provider name in `InternalHandlerRegistryV2`
3. Handler receives the full `ToolManifest` and uses `manifest.tool.id` to determine specific tool behavior
4. Handler retrieves API key from `APIKeysStorage.shared.getAPIKey(for: .provider)`
5. Handler executes the appropriate API call and returns `ToolResultV2`

This design means:
- Tool JSON manifests define the tool ID and metadata
- Handlers use the manifest's tool ID to dispatch to the correct implementation
- No need to modify handlers when adding new tool aliases - just update the switch statement

