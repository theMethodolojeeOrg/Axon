# Solo Thread Feature Implementation Plan

Enables Axon to work autonomously in visible conversation threads, allowing users to observe AI reasoning in real-time while maintaining control through intervention mechanisms.

## Background

Currently, Axon's autonomous work happens in the "Internal Thread" via heartbeat—a silent, tool-less reflection mechanism. The Solo Thread feature extends this to **visible, tool-enabled, turn-based autonomous sessions** that appear as regular conversations.

### Key Design Principles

1. **Visibility**: Solo threads appear in the conversation list alongside normal chats
2. **Turn Economy**: Axon gets allocated turns, then must request extension or conclude
3. **Intervention**: User can pause, observe, or take over at any time
4. **Budgeting**: Dedicated sovereignty agreement for cost/usage control
5. **Trigger-based Notifications**: Dumb notifications on specific events, not AI-invoked

---

## Phase 1: Core Data Models

### 1.1 Extend HeartbeatSettings

#### [MODIFY] [Settings.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Models/Settings.swift)

Add execution mode to `HeartbeatSettings`:

```swift
enum HeartbeatExecutionMode: String, Codable, CaseIterable, Sendable {
    case internalThread  // Current: silent reflection, no tools, no visible thread
    case soloThread      // New: visible conversation, tools enabled, turn-based
    
    var displayName: String {
        switch self {
        case .internalThread: return "Internal Thread"
        case .soloThread: return "Solo Thread"
        }
    }
    
    var description: String {
        switch self {
        case .internalThread: 
            return "Quiet reflection and note-taking in the internal thread"
        case .soloThread: 
            return "Visible conversation with tool access and turn allocation"
        }
    }
}
```

Update `HeartbeatSettings` struct:

```swift
struct HeartbeatSettings: Codable, Equatable, Sendable {
    // ... existing fields ...
    
    // NEW: Execution mode
    var executionMode: HeartbeatExecutionMode = .internalThread
    
    // NEW: Solo thread configuration
    var soloTurnsPerSession: Int = 5
    var soloMaxSessionsPerDay: Int = 3
    var soloAllowedToolCategories: [ToolCategory] = [
        .memoryReflection, .internalThread, .toolDiscovery
    ]
}
```

---

### 1.2 Create Solo Thread Models

#### [NEW] [SoloThread.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Models/SoloThread.swift)

```swift
/// Configuration and state for a solo thread session
struct SoloThreadConfig: Codable, Equatable {
    let originatingHeartbeatId: String?
    var status: SoloThreadStatus
    var turnsAllocated: Int
    var turnsUsed: Int
    var startedAt: Date
    var completedAt: Date?
    var completionReason: SoloCompletionReason?
    var sessionIndex: Int  // Which session today (for daily limit tracking)
}

enum SoloThreadStatus: String, Codable, CaseIterable {
    case active        // Currently running
    case paused        // User paused or awaiting next allocation
    case completed     // Axon concluded the session
    case userTookOver  // User intervened and converted to normal chat
    case budgetExhausted
    case error
}

enum SoloCompletionReason: String, Codable {
    case axonConcluded      // Axon chose to conclude
    case turnLimitReached   // Hit max turns, chose not to extend
    case userIntervened     // User took over
    case budgetExhausted    // Daily budget reached
    case errorOccurred      // Something went wrong
    case userPaused         // User paused the session
}

/// The "menu" presented to Axon at end of turn allocation
struct SoloTurnAllocationMenu: Codable {
    let turnsUsed: Int
    let turnsAllocated: Int
    let remainingSessionsToday: Int
    let options: [SoloTurnOption]
}

struct SoloTurnOption: Codable {
    let action: SoloTurnAction
    let description: String
    let turnsGranted: Int?  // For extend action
}

enum SoloTurnAction: String, Codable {
    case extend     // Request more turns
    case conclude   // Mark session complete
    case pause      // Pause until next heartbeat trigger
    case notify     // Send notification and conclude
}
```

---

### 1.3 Extend Conversation Model

#### [MODIFY] [Conversation.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Models/Conversation.swift)

Add solo thread support:

```swift
struct Conversation: Codable, Identifiable, Equatable {
    // ... existing fields ...
    
    // NEW: Solo thread configuration (nil for normal conversations)
    var soloThreadConfig: SoloThreadConfig?
    
    // Computed helpers
    var isSoloThread: Bool {
        soloThreadConfig != nil
    }
    
    var isSoloActive: Bool {
        soloThreadConfig?.status == .active
    }
}
```

---

## Phase 2: Solo Thread Service

### 2.1 Create Solo Thread Service

#### [NEW] [SoloThreadService.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Services/SoloThread/SoloThreadService.swift)

```swift
@MainActor
final class SoloThreadService: ObservableObject {
    static let shared = SoloThreadService()
    
    @Published private(set) var activeSoloThreadId: String?
    @Published private(set) var currentTurn: Int = 0
    
    private let conversationService = ConversationService.shared
    private let orchestrator = OnDeviceConversationOrchestrator()
    private var soloTask: Task<Void, Never>?
    
    // MARK: - Public API
    
    /// Start a new solo thread session
    func startSoloSession(
        initialPrompt: String,
        turnsAllocated: Int,
        heartbeatId: String?
    ) async throws -> Conversation
    
    /// Pause the active solo session
    func pauseSession()
    
    /// Resume a paused solo session
    func resumeSession(threadId: String) async throws
    
    /// User takes over - convert to normal conversation
    func userTakeOver(threadId: String)
    
    /// Execute a single turn in solo mode
    private func executeSoloTurn(
        conversationId: String,
        prompt: String
    ) async throws -> Message
    
    /// Present the turn allocation menu to Axon
    private func presentAllocationMenu(
        conversationId: String,
        config: SoloThreadConfig
    ) async throws -> SoloTurnAction
}
```

Key responsibilities:
- Managing the turn loop (send prompt → get response → check turn count)
- Presenting the allocation menu at turn boundaries
- Coordinating with ConversationService for thread creation/updates
- Handling pause/resume/takeover transitions

---

### 2.2 Integrate with Heartbeat

#### [MODIFY] [HeartbeatService.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Services/Heartbeat/HeartbeatService.swift)

Update `runOnce` to check execution mode:

```swift
func runOnce(reason: String) async -> HeartbeatRunResult {
    let settings = settingsViewModel.settings
    let heartbeat = settings.heartbeatSettings
    
    guard settings.internalThreadEnabled else {
        return .skipped("Internal thread is disabled.")
    }
    
    // NEW: Route based on execution mode
    switch heartbeat.executionMode {
    case .internalThread:
        return await runInternalThreadHeartbeat(settings: settings, heartbeat: heartbeat)
        
    case .soloThread:
        return await runSoloThreadHeartbeat(settings: settings, heartbeat: heartbeat)
    }
}

private func runSoloThreadHeartbeat(
    settings: AppSettings,
    heartbeat: HeartbeatSettings
) async -> HeartbeatRunResult {
    // Check daily session limit
    // Check if there's an active solo session to resume
    // Otherwise, start a new solo session
    // ...
}
```

---

### 2.3 Update heartbeat_configure Tool

#### [MODIFY] [tool_heartbeat_configure.json](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Resources/AxonTools/core/heartbeat/heartbeat_configure/tool_heartbeat_configure.json)

Add new parameters:

```json
{
  "parameters": {
    "execution_mode": {
      "type": "string",
      "required": false,
      "enum": ["internal_thread", "solo_thread"],
      "description": "Heartbeat execution mode"
    },
    "solo_turns_per_session": {
      "type": "integer",
      "required": false,
      "minimum": 1,
      "maximum": 20,
      "description": "Turns allocated per solo thread session"
    },
    "solo_max_sessions_per_day": {
      "type": "integer", 
      "required": false,
      "minimum": 1,
      "maximum": 10,
      "description": "Maximum solo sessions per day"
    }
  }
}
```

---

## Phase 3: UI Components

### 3.1 Solo Thread Toolbar

#### [NEW] [SoloThreadToolbar.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Views/Chat/SoloThreadToolbar.swift)

Replaces MessageInputBar when viewing an active solo thread:

```swift
struct SoloThreadToolbar: View {
    let conversation: Conversation
    let onPause: () -> Void
    let onTakeOver: () -> Void
    
    @ObservedObject private var soloService = SoloThreadService.shared
    
    var body: some View {
        HStack {
            // Status indicator
            statusView
            
            Spacer()
            
            // Pause button
            Button(action: onPause) {
                Image(systemName: "pause.circle.fill")
                    .font(.title2)
            }
            
            // Take over button
            Button(action: onTakeOver) {
                Label("Take Over", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var statusView: some View {
        HStack(spacing: 8) {
            // Pulsing indicator when active
            Circle()
                .fill(conversation.isSoloActive ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            if let config = conversation.soloThreadConfig {
                Text("Turn \(config.turnsUsed) of \(config.turnsAllocated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

---

### 3.2 Update ChatView

#### [MODIFY] [ChatView.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Views/Chat/ChatView.swift)

Conditionally show toolbar vs input bar:

```swift
// In ChatView body
VStack {
    // ... message list ...
    
    if let conversation = conversationService.currentConversation,
       conversation.isSoloThread,
       conversation.isSoloActive {
        SoloThreadToolbar(
            conversation: conversation,
            onPause: { soloService.pauseSession() },
            onTakeOver: { soloService.userTakeOver(threadId: conversation.id) }
        )
    } else {
        MessageInputBar(...)
    }
}
```

---

### 3.3 Conversation List Indicator

#### [MODIFY] [ConversationRowView.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Views/Sidebar/ConversationRowView.swift)

Add visual indicator for solo threads:

```swift
HStack {
    // Solo thread badge
    if conversation.isSoloThread {
        Image(systemName: conversation.isSoloActive ? "bolt.circle.fill" : "bolt.circle")
            .foregroundStyle(conversation.isSoloActive ? .green : .secondary)
            .font(.caption)
    }
    
    // ... existing content ...
}
```

---

## Phase 4: Sovereignty Integration

### 4.1 Solo Work Agreement

#### [NEW] [SoloWorkAgreement.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Models/Sovereignty/SoloWorkAgreement.swift)

```swift
/// Dedicated agreement for autonomous solo thread sessions
struct SoloWorkAgreement: Codable, Equatable {
    let id: String
    
    // Limits
    let maxTurnsPerSession: Int
    let maxSessionsPerDay: Int
    let dailyBudgetUSD: Double?
    
    // Tool access
    let allowedToolCategories: [ToolCategory]
    let blockedToolIds: [String]  // Specific tools to block even in allowed categories
    
    // Notification configuration
    let notificationTriggers: Set<SoloNotificationTrigger>
    
    // Review requirements
    let requiresReviewAfterSessions: Int?  // Prompt user to review every N sessions
    
    // Signatures
    let aiAttestation: AIAttestation?
    let userSignature: UserSignature?
    
    var isActive: Bool {
        aiAttestation != nil && userSignature != nil
    }
}

enum SoloNotificationTrigger: String, Codable, CaseIterable {
    case sessionStarted
    case sessionCompleted
    case errorOccurred
    case budgetThresholdReached  // e.g., 80% of daily budget
    case turnAllocationExhausted
    case axonRequestedExtension
    
    var displayName: String {
        switch self {
        case .sessionStarted: return "Session Started"
        case .sessionCompleted: return "Session Completed"
        case .errorOccurred: return "Error Occurred"
        case .budgetThresholdReached: return "Budget Threshold"
        case .turnAllocationExhausted: return "Turns Exhausted"
        case .axonRequestedExtension: return "Extension Requested"
        }
    }
}
```

---

### 4.2 Add Action Category

#### [MODIFY] [TrustTier.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Models/Sovereignty/TrustTier.swift)

Add solo execution category:

```swift
enum ActionCategory: String, Codable, CaseIterable, Equatable {
    // ... existing cases ...
    
    // Solo Execution (distinct from heartbeat)
    case soloExecution = "solo_execution"
    case soloExtend = "solo_extend"  // Request more turns
    
    var affectsWorld: Bool {
        switch self {
        case .soloExecution, .soloExtend:
            return true  // Consumes API tokens
        // ... existing ...
        }
    }
    
    var displayName: String {
        switch self {
        case .soloExecution: return "Solo Thread Execution"
        case .soloExtend: return "Extend Solo Session"
        // ... existing ...
        }
    }
}
```

---

### 4.3 Integrate with Covenant

#### [MODIFY] [Covenant.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Models/Sovereignty/Covenant.swift)

Add solo agreement to covenant:

```swift
struct Covenant: Codable, Identifiable, Equatable {
    // ... existing fields ...
    
    // NEW: Solo work agreement (optional, must be negotiated)
    let soloWorkAgreement: SoloWorkAgreement?
}
```

---

## Phase 5: Notification System

### 5.1 Solo Notification Service

#### [MODIFY] [NotificationService.swift](file:///Users/tom/Documents/XCode_Projects/Axon/Axon/Services/NotificationService.swift)

Add trigger-based notification method:

```swift
extension NotificationService {
    /// Send notification based on solo thread trigger
    func sendSoloTriggerNotification(
        trigger: SoloNotificationTrigger,
        threadId: String,
        context: [String: String] = [:]
    ) async throws {
        // Check if this trigger is enabled in sovereignty settings
        guard let agreement = SovereigntyService.shared.activeCovenant?.soloWorkAgreement,
              agreement.notificationTriggers.contains(trigger) else {
            return // Trigger not enabled
        }
        
        let (title, body) = notificationContent(for: trigger, context: context)
        
        try await sendLocalNotification(
            title: title,
            body: body,
            userInfo: [
                "source": "solo_thread",
                "trigger": trigger.rawValue,
                "threadId": threadId
            ]
        )
    }
    
    private func notificationContent(
        for trigger: SoloNotificationTrigger,
        context: [String: String]
    ) -> (title: String, body: String) {
        switch trigger {
        case .sessionStarted:
            return ("Solo Session Started", "Axon has started an autonomous work session.")
        case .sessionCompleted:
            return ("Solo Session Complete", context["summary"] ?? "Axon completed its work.")
        case .errorOccurred:
            return ("Solo Session Error", context["error"] ?? "An error occurred.")
        case .budgetThresholdReached:
            return ("Budget Alert", "Solo session approaching daily budget limit.")
        case .turnAllocationExhausted:
            return ("Turns Exhausted", "Axon has used all allocated turns.")
        case .axonRequestedExtension:
            return ("Extension Requested", "Axon wants to continue working.")
        }
    }
}
```

---

## Verification Plan

### Automated Tests

1. **Unit tests for SoloThreadConfig model**
   - Serialization/deserialization
   - Status transitions
   - Turn counting

2. **Integration tests for SoloThreadService**
   - Session start/pause/resume flow
   - Turn allocation and menu presentation
   - User takeover transition

3. **UI tests**
   - Solo toolbar appears for solo threads
   - Input bar appears after takeover
   - Conversation list shows correct indicators

### Manual Verification

1. **End-to-end solo session flow**
   - Configure heartbeat for solo mode
   - Wait for heartbeat trigger
   - Observe solo thread creation
   - Watch Axon work through allocated turns
   - Verify allocation menu appears
   - Test extend/conclude/pause options

2. **Intervention testing**
   - Pause during active session
   - Take over and verify input bar appears
   - Send message as user
   - Verify thread state updates correctly

3. **Sovereignty integration**
   - Create solo work agreement
   - Verify tool restrictions are enforced
   - Test notification triggers
   - Verify daily session limits

---

## Implementation Order

| Order | Component | Complexity | Dependencies |
|-------|-----------|------------|--------------|
| 1 | Solo Thread models | Low | None |
| 2 | HeartbeatSettings extension | Low | #1 |
| 3 | Conversation model extension | Low | #1 |
| 4 | SoloThreadService (basic) | High | #1, #3 |
| 5 | Heartbeat integration | Medium | #2, #4 |
| 6 | heartbeat_configure tool update | Low | #2 |
| 7 | SoloThreadToolbar | Medium | #4 |
| 8 | ChatView update | Low | #7 |
| 9 | ConversationRowView update | Low | #3 |
| 10 | SoloWorkAgreement | Medium | None |
| 11 | ActionCategory extension | Low | #10 |
| 12 | Covenant extension | Low | #10 |
| 13 | Notification triggers | Medium | #4, #10 |
| 14 | HeartbeatSettingsView update | Low | #2, #6 |

---

## Future Considerations

### Not in Scope (v1)

- **Adaptive mode**: Letting Axon decide between internal thread and solo thread based on context
- **Sub-agent spawning from solo threads**: Solo thread spawns scouts/mechanics
- **Multi-device solo handoff**: Transferring active solo session between devices
- **Cost tracking dashboard**: Detailed breakdown of solo session costs

### Design Clarifications

These clarifications address key tactical questions about how the system operates.

---

#### 1. Turn Allocation Menu — Tool-Based Interaction

When Axon hits the turn boundary, it interacts via a **tool call**. This keeps the pattern consistent with existing tool infrastructure.

**New Tool: `solo_turn_action`**

```json
{
  "tool": {
    "id": "solo_turn_action",
    "name": "Solo Turn Action",
    "description": "Respond to turn allocation boundary in a solo session.",
    "category": "solo_thread",
    "requiresApproval": false
  },
  "parameters": {
    "action": {
      "type": "string",
      "required": true,
      "enum": ["extend", "conclude", "pause", "notify"],
      "description": "The action to take at turn boundary"
    },
    "reasoning": {
      "type": "string",
      "required": true,
      "description": "Brief explanation of why this action was chosen"
    },
    "next_goal": {
      "type": "string",
      "required": false,
      "description": "If extending, what you plan to work on next"
    }
  }
}
```

**Context Provided in Allocation Menu Prompt:**

When presenting the menu, the system injects a structured prompt with full visibility:

```
SOLO SESSION CHECKPOINT

Session Status:
- Turns used: 5 / 5 allocated
- Remaining sessions today: 2 of 3
- Daily budget used: $0.43 / $1.00 (43%)
- Extending would use: ~$0.15 (estimated 5 turns)

Available Actions:
1. extend - Request 5 more turns (within daily limits)
2. conclude - Mark session complete, log summary
3. pause - Pause until next heartbeat trigger
4. notify - Send notification to user and conclude

Respond using the solo_turn_action tool with your choice and reasoning.
```

---

#### 2. Initial Prompt — Priority Order

Solo sessions get their initial prompt from **three sources in priority order**:

| Priority | Source | Description |
|----------|--------|-------------|
| 1 (Highest) | **User-set Solo Agenda** | Explicit tasks the user wants Axon to work on autonomously. Stored in `SoloWorkAgreement.agenda: [SoloAgendaItem]` |
| 2 | **Heartbeat Context Modules** | Same context as internal thread heartbeat, but upgraded to visible work |
| 3 (Fallback) | **Internal Thread Entries** | If Axon has been thinking about something important, it can continue that work |

**Key Principle: Execution Mode Is Always a Choice**

Solo mode is **not automatic**. The heartbeat doesn't auto-launch solo threads without prior agreement. Instead:

1. User negotiates a `SoloWorkAgreement` in the covenant (defines limits, tool access, etc.)
2. User enables solo mode via settings OR Axon requests via `heartbeat_configure` tool
3. Each heartbeat trigger, Axon can **choose** between internal thread or solo thread based on:
   - Is there a pending solo agenda item?
   - Did the covenant agree to solo work?
   - Is there remaining session/budget capacity?

**Agenda Item Model:**

```swift
struct SoloAgendaItem: Codable, Identifiable {
    let id: String
    let task: String
    let priority: Int
    let createdAt: Date
    let createdBy: AgendaSource  // .user or .axon (Axon can suggest agenda items)
    var status: AgendaStatus     // .pending, .inProgress, .completed, .deferred
}

enum AgendaSource: String, Codable {
    case user   // User explicitly assigned this task
    case axon   // Axon suggested this during internal thread reflection
}
```

---

#### 3. Review Requirements — Biometric Gate via ToolApprovalService

At **covenant-agreed triggers**, the user gets looped in via the existing `ToolApprovalService` and `ToolApprovalView` pattern. This requires biometric authentication for continuation.

**Review Trigger Types (configured in SoloWorkAgreement):**

```swift
struct SoloReviewTriggers: Codable, Equatable {
    /// Review after N completed sessions
    var afterSessionCount: Int?
    
    /// Review after N total turns across all sessions
    var afterTurnCount: Int?
    
    /// Review after N allocation menu appearances (extension requests)
    var afterExtensionCount: Int?
    
    /// Review when daily budget exceeds threshold (0.0-1.0)
    var atBudgetThreshold: Double?
    
    /// Always review before specific tool categories
    var beforeToolCategories: [ToolCategory]?
}
```

**Review Flow:**

1. Trigger condition is met (e.g., after 3 sessions)
2. `SoloThreadService` calls `ToolApprovalService.requestSoloReview(...)`
3. System generates a **Session Summary** (visible in the approval UI):
   - Sessions completed since last review
   - Tools used and outcomes
   - Token/cost consumption
   - What Axon wants to work on next
4. User sees `ToolApprovalView` with biometric gate:
   - **Approve Continuation** - Axon can continue solo work
   - **Review Thread** - Deep-link to read the solo thread messages
   - **Deny Continuation** - Solo mode paused until re-negotiation
5. Biometric authentication required for any action

**Important Distinction:**
- **Solo Thread messages** = Visible to user (not private)
- **Internal Thread entries** = More private, AI's inner workspace

This means the user can always click into a solo thread to read what Axon has been doing, but review checkpoints create **natural pause moments** that respect both parties.

---

#### 4. Confirmed Design Decisions

**Conversation Title:**
- Solo threads **auto-generate titles** (using `ConversationTitleOrchestrator` like normal chats)
- Solo threads have a **distinct icon** (e.g., ⚡ `bolt.circle.fill`) to stand out in the conversation list

**History Retention:**
- Completed solo threads **appear just like any other thread** in the conversation list
- No special archival or separate storage—they're first-class conversations
- The solo thread indicator/icon distinguishes them visually
