# AXON Implementation Mapping
## Unified Architecture → Codebase Integration

This document maps the unified architecture (Predicate Logging + Epistemic Engine + Personalized Intelligence) to your existing codebase and concrete implementation tasks.

---

## Existing Assets (Don't Break These!)

### ✅ Memory System Foundation
**Files:**
- `Axon/Models/Memory.swift` - Has allocentric/egoic typing ✓
- `Axon/Services/Memory/MemoryService.swift` - CRUD operations ✓
- Core Data integration ✓

**Status:** Can be enhanced, not replaced

**What to add:**
- [ ] Confidence scoping logic (extend Memory model)
- [ ] Contradiction tracking (add Contradiction codable to Memory)
- [ ] Shift log references (track which queries reference this memory)

### ✅ Conversation System
**Files:**
- `Axon/Services/Conversation/ConversationService.swift` - Unified history ✓
- `Axon/Services/Conversation/OnDeviceConversationOrchestrator.swift` - Direct AI calls ✓
- Multi-provider support (OpenAI, Anthropic, Google, xAI) ✓

**Status:** Perfect foundation for epistemic context injection

**What to add:**
- [ ] EpistemicContext parameter to orchestrate()
- [ ] Shift log generation before LLM call
- [ ] Salient memory injection into system prompt
- [ ] Learning loop callback after response

### ✅ Proxy Server (ServerSettingsView)
**Files:**
- `Axon/Views/Settings/ServerSettingsView.swift` - Beautiful UI ✓
- `Axon/Services/Server/APIServerService.swift` - FlyingFox server ✓
- OpenAI API compatibility ✓
- Cline/Continue integration ready ✓

**Status:** Ready to enhance with epistemic endpoints

**What to add:**
- [ ] `/api/memories/ground` endpoint
- [ ] `/api/epistemic/context` endpoint
- [ ] `/api/shift-logs` endpoint for transparency
- [ ] Learn from external tool feedback

### ✅ Settings & Configuration
**Files:**
- `Axon/Models/Settings.swift` - Extensible settings ✓
- `Axon/Views/Settings/` - UI framework ✓

**Status:** Ready for new controls

**What to add:**
- [ ] Toggle for predicate logging verbosity
- [ ] Toggle for shift log transparency
- [ ] Settings for learning loop sensitivity

---

## Phase 1: Predicate Logging Foundation (Week 1)

### 1.1 Create PredicateLogger Service

**File:** `Axon/Services/Logging/PredicateLogger.swift` (NEW)

```swift
import Foundation

struct PredicateLog: Identifiable, Codable {
  let id: String
  let event: String
  let predicate: String
  let passed: Bool
  let scope: String  // "infra", "service", "domain", "user-facing"
  let metadata: [String: AnyCodable]
  let correlationId: String
  let timestamp: Date

  var parentPredicateId: String?
  var childPredicateIds: [String] = []
}

@MainActor
class PredicateLogger: ObservableObject {
  static let shared = PredicateLogger()

  @Published var logs: [PredicateLog] = []
  @Published var isEnabled = true

  private let logQueue = DispatchQueue(label: "com.axon.predicate-logs")

  func log(
    event: String,
    predicate: String,
    passed: Bool,
    scope: String,
    metadata: [String: Any] = [:],
    correlationId: String,
    parentId: String? = nil
  ) {
    guard isEnabled else { return }

    let log = PredicateLog(
      id: UUID().uuidString,
      event: event,
      predicate: predicate,
      passed: passed,
      scope: scope,
      metadata: metadata.mapValues { AnyCodable($0) },
      correlationId: correlationId,
      timestamp: Date()
    )

    logQueue.async { [weak self] in
      DispatchQueue.main.async {
        self?.logs.append(log)
        print("[Predicate] \(event) → \(predicate): \(passed)")
      }
    }
  }

  func getProofTree(correlationId: String) -> [PredicateLog] {
    logs.filter { $0.correlationId == correlationId }
  }
}
```

**Tasks:**
- [ ] Create PredicateLogger service
- [ ] Implement in-memory storage
- [ ] Add Settings toggle for verbosity
- [ ] Create UI to view predicate trees (debug only)

### 1.2 Instrument Core Operations

**Files to update:**
- `Axon/Services/Memory/MemoryService.swift`
- `Axon/Services/Conversation/ConversationService.swift`
- `Axon/Services/API/APIClient.swift`

**Example instrumentation:**

```swift
// In MemoryService.searchMemories()
func searchMemories(query: String, correlationId: String) async throws -> [Memory] {
  PredicateLogger.shared.log(
    event: "memory_search_started",
    predicate: "memory_search_initiated",
    passed: true,
    scope: "domain.memory",
    metadata: ["query": query, "type": "semantic"],
    correlationId: correlationId
  )

  let results = // ... actual search

  PredicateLogger.shared.log(
    event: "memory_search_complete",
    predicate: "memory_search_successful",
    passed: !results.isEmpty,
    scope: "domain.memory",
    metadata: ["resultCount": results.count],
    correlationId: correlationId
  )

  return results
}
```

**Tasks:**
- [ ] Add predicates to MemoryService (search, create, update)
- [ ] Add predicates to ConversationService (create, fetch, sync)
- [ ] Add predicates to APIClient (request, parse, inject)
- [ ] Test predicate tree formation

### 1.3 Create Proof Tree Viewer

**File:** `Axon/Views/Debug/PredicateTreeView.swift` (NEW)

**Features:**
- [ ] Show predicate tree for current conversation
- [ ] Hierarchical display (parent/child relationships)
- [ ] Filter by scope or status
- [ ] Export as JSON for debugging

---

## Phase 2: Epistemic Engine (Weeks 2-3)

### 2.1 Create EpistemicEngine Service

**File:** `Axon/Services/Memory/EpistemicEngine.swift` (NEW)

```swift
import Foundation

struct EpistemicContext: Codable {
  let groundedFacts: [Memory]
  let shiftLog: ShiftLog
  let compositeConfidence: Double
  let epistemicBoundaries: [String]
  let assumptions: [String]
}

struct ShiftLog: Codable, Identifiable {
  let id: String
  let correlationId: String
  let userQuery: String
  let parsedIntents: [String]
  let retrievalConstraints: [String]

  let groundedFactCount: Int
  let groundingConfidence: Double    // 0.96
  let shiftIntegrity: Double         // 0.98
  let compositeConfidence: Double    // 0.94

  let epistemicBoundaries: [String]
  let assumptions: [String]

  let timestamp: Date
}

@MainActor
class EpistemicEngine: ObservableObject {
  let memoryService: MemoryService

  func ground(
    userMessage: String,
    memories: [Memory],
    correlationId: String
  ) async throws -> EpistemicContext {
    // 1. Parse intent
    PredicateLogger.shared.log(
      event: "intent_parsing_started",
      predicate: "intent_parsing_initiated",
      passed: true,
      scope: "domain.memory",
      correlationId: correlationId
    )

    let intents = parseIntent(userMessage)

    PredicateLogger.shared.log(
      event: "intent_parsing_complete",
      predicate: "intent_parsing_successful",
      passed: !intents.isEmpty,
      scope: "domain.memory",
      metadata: ["intents": intents],
      correlationId: correlationId
    )

    // 2. Deterministic search
    PredicateLogger.shared.log(
      event: "memory_search_started",
      predicate: "memory_search_initiated",
      passed: true,
      scope: "domain.memory",
      correlationId: correlationId
    )

    let constraints = buildConstraints(from: intents)
    let grounded = searchWithConstraints(memories, constraints)

    PredicateLogger.shared.log(
      event: "memory_search_complete",
      predicate: "memory_search_successful",
      passed: !grounded.isEmpty,
      scope: "domain.memory",
      metadata: ["resultCount": grounded.count],
      correlationId: correlationId
    )

    // 3. Calculate confidence
    let confidence = calculateConfidence(grounded)

    // 4. Generate Shift Log
    let shiftLog = ShiftLog(
      id: UUID().uuidString,
      correlationId: correlationId,
      userQuery: userMessage,
      parsedIntents: intents,
      retrievalConstraints: constraints.map { $0.description },
      groundedFactCount: grounded.count,
      groundingConfidence: 0.96,  // Database reliability
      shiftIntegrity: 0.98,       // Boundary crossing reliability
      compositeConfidence: confidence,
      epistemicBoundaries: [
        "Whether context has changed since memory creation",
        "Whether grounded facts apply to current moment",
        "Current user intent beyond the query"
      ],
      assumptions: [
        "Retrieved facts are still current",
        "Grounding constraints fully capture user intent",
        "Boundary between discrete and continuous registers is intact"
      ],
      timestamp: Date()
    )

    PredicateLogger.shared.log(
      event: "epistemic_grounding_complete",
      predicate: "grounding_operation_successful",
      passed: true,
      scope: "domain.memory",
      metadata: ["confidence": confidence, "shiftLog": shiftLog.id],
      correlationId: correlationId
    )

    return EpistemicContext(
      groundedFacts: grounded,
      shiftLog: shiftLog,
      compositeConfidence: confidence,
      epistemicBoundaries: shiftLog.epistemicBoundaries,
      assumptions: shiftLog.assumptions
    )
  }

  private func parseIntent(_ message: String) -> [String] {
    // Simple implementation: extract keywords
    // TODO: Could use Claude for more sophisticated parsing
    let keywords = message.lowercased()
      .split(separator: " ")
      .filter { $0.count > 3 }
      .map { String($0) }
    return Array(Set(keywords))
  }

  private func buildConstraints(from intents: [String]) -> [SearchConstraint] {
    intents.map { SearchConstraint(type: .topic, value: $0) }
  }

  private func searchWithConstraints(
    _ memories: [Memory],
    _ constraints: [SearchConstraint]
  ) -> [Memory] {
    // Implement deterministic search (constraint intersection)
    memories.filter { memory in
      constraints.allSatisfy { constraint in
        constraint.matches(memory)
      }
    }
  }

  private func calculateConfidence(_ memories: [Memory]) -> Double {
    guard !memories.isEmpty else { return 0.0 }
    let avgConfidence = memories.map { $0.confidence }.reduce(0, +) / Double(memories.count)
    return avgConfidence
  }
}

struct SearchConstraint {
  enum ConstraintType {
    case topic
    case type
    case recency
    case author
  }

  let type: ConstraintType
  let value: String

  func matches(_ memory: Memory) -> Bool {
    // Implement constraint matching logic
    switch type {
    case .topic:
      return memory.tags.contains(value) ||
             memory.content.lowercased().contains(value.lowercased())
    case .type:
      return memory.type.rawValue == value
    case .recency:
      // TODO: Implement recency matching
      return true
    case .author:
      return memory.discoveredBy == value
    }
  }

  var description: String {
    "\(type)(\(value))"
  }
}
```

**Tasks:**
- [ ] Create EpistemicEngine service
- [ ] Implement intent parser
- [ ] Implement constraint-based search
- [ ] Implement confidence calculation
- [ ] Generate Shift Logs

### 2.2 Store Shift Logs

**File:** `Axon/Models/ShiftLog.swift` (Move to dedicated file)

**Tasks:**
- [ ] Create ShiftLog data model
- [ ] Save Shift Logs to Core Data
- [ ] Create ShiftLogService for retrieval
- [ ] Link Shift Logs to Memories (reference tracking)

### 2.3 Update Memory Model

**File:** `Axon/Models/Memory.swift` (Update)

```swift
struct Contradiction: Codable {
  let date: Date
  let previousConfidence: Double
  let newConfidence: Double
  let evidence: String
  let refiningCondition: String?
}

struct LearningUpdate: Codable {
  let date: Date
  let userFeedback: String
  let confidenceAdjustment: Double
  let newCondition: String?
  let reasoning: String
}

struct Memory: Identifiable, Codable {
  // ... existing fields ...

  // NEW: Confidence with conditions
  var confidence: Double
  var scope: String?  // "when refactoring > 5 lines"
  var scopeConditions: [String]?

  // NEW: Contradiction & learning history
  var contradictionHistory: [Contradiction]?
  var learningUpdates: [LearningUpdate]?

  // NEW: Evidence tracking
  var successCount: Int?
  var failureCount: Int?
  var lastValidated: Date?

  // NEW: Shift log references
  var referencedInShiftLogs: [String]?
}
```

**Tasks:**
- [ ] Add contradiction history to Memory model
- [ ] Add learning updates to Memory model
- [ ] Add evidence tracking (success/failure counts)
- [ ] Implement confidence scoping logic

---

## Phase 3: Salience Injection (Weeks 3-4)

### 3.1 Create SalienceService

**File:** `Axon/Services/Memory/SalienceService.swift` (NEW)

```swift
@MainActor
class SalienceService: ObservableObject {
  let memoryService: MemoryService
  let epistemicEngine: EpistemicEngine

  func injectSalient(
    conversation: Conversation,
    epistemicContext: EpistemicContext,
    availableTokens: Int = 2000,
    correlationId: String
  ) async throws -> String {
    // 1. Rank memories by salience
    PredicateLogger.shared.log(
      event: "salience_ranking_started",
      predicate: "salience_ranking_initiated",
      passed: true,
      scope: "domain.memory",
      correlationId: correlationId
    )

    let salient = rankBySalience(
      epistemicContext.groundedFacts,
      for: conversation,
      availableTokens: availableTokens
    )

    PredicateLogger.shared.log(
      event: "salience_ranking_complete",
      predicate: "salience_ranking_successful",
      passed: !salient.isEmpty,
      scope: "domain.memory",
      metadata: ["rankedCount": salient.count],
      correlationId: correlationId
    )

    // 2. Format with transparency (Shift Log)
    PredicateLogger.shared.log(
      event: "shift_log_formatting_started",
      predicate: "shift_log_formatting_initiated",
      passed: true,
      scope: "domain.memory",
      correlationId: correlationId
    )

    let formatted = formatWithShiftLog(
      salient,
      shiftLog: epistemicContext.shiftLog,
      confidence: epistemicContext.compositeConfidence
    )

    PredicateLogger.shared.log(
      event: "salience_injection_complete",
      predicate: "salient_memories_injected",
      passed: true,
      scope: "domain.memory",
      metadata: ["injectedCount": salient.count],
      correlationId: correlationId
    )

    return formatted
  }

  private func rankBySalience(
    _ memories: [Memory],
    for conversation: Conversation,
    availableTokens: Int
  ) -> [Memory] {
    // Score each memory by relevance to current conversation
    let scored = memories.map { memory -> (Memory, Double) in
      let relevance = calculateRelevance(memory, to: conversation)
      let confidence = memory.confidence
      let recency = calculateRecency(memory)
      let score = relevance * confidence * recency
      return (memory, score)
    }

    // Sort by score, fit within token budget
    return scored
      .sorted { $0.1 > $1.1 }
      .map { $0.0 }
      .prefix(while: { _ in
        // TODO: Implement token counting
        true
      })
      .map { $0 }
  }

  private func calculateRelevance(_ memory: Memory, to conversation: Conversation) -> Double {
    // Simple: how many tags match conversation topics?
    // Could be enhanced with semantic similarity
    let conversationTokens = Set(conversation.summary?.split(separator: " ").map { String($0) } ?? [])
    let matchingTags = memory.tags.filter { tag in
      conversationTokens.contains(where: { token in
        tag.lowercased().contains(token.lowercased())
      })
    }
    return Double(matchingTags.count) / Double(max(memory.tags.count, 1))
  }

  private func calculateRecency(_ memory: Memory) -> Double {
    let daysSinceCreation = Date().timeIntervalSince(memory.createdAt) / 86400
    return 1.0 / (1.0 + daysSinceCreation / 30.0)  // Decay over 30 days
  }

  private func formatWithShiftLog(
    _ memories: [Memory],
    shiftLog: ShiftLog,
    confidence: Double
  ) -> String {
    var result = """
    # GROUNDED CONTEXT (Confidence: \(String(format: "%.2f", confidence)))
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    """

    // Group by type
    let allocentric = memories.filter { $0.type == .allocentric }
    let egoic = memories.filter { $0.type == .egoic }

    if !allocentric.isEmpty {
      result += "## ALLOCENTRIC MEMORIES (About You)\n"
      for memory in allocentric {
        result += """
        - [\(String(format: "%.2f", memory.confidence))] \(memory.content)
          Evidence: \(memory.discoveredBy ?? "observed")
        \n
        """
      }
      result += "\n"
    }

    if !egoic.isEmpty {
      result += "## EGOIC MEMORIES (About What Works)\n"
      for memory in egoic {
        result += """
        - [\(String(format: "%.2f", memory.confidence))] \(memory.content)
          Evidence: Discovered by \(memory.discoveredBy ?? "system")
        \n
        """
      }
      result += "\n"
    }

    // Add Shift Log transparency
    result += """
    # SHIFT LOG (Transparency)
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Grounded Facts: \(memories.count)
    Retrieval Reliability: 0.96
    Shift Integrity: 0.98
    Composite Confidence: \(String(format: "%.2f", confidence))

    **Epistemic Boundaries:**
    """

    for boundary in shiftLog.epistemicBoundaries {
      result += "\n- ✗ UNKNOWN: \(boundary)"
    }

    result += "\n\n**Assumptions:**\n"
    for assumption in shiftLog.assumptions {
      result += "- \(assumption)\n"
    }

    return result
  }
}
```

**Tasks:**
- [ ] Create SalienceService
- [ ] Implement ranking algorithm
- [ ] Format with Shift Log transparency
- [ ] Test with multiple models

### 3.2 Integrate with OnDeviceConversationOrchestrator

**File:** `Axon/Services/Conversation/OnDeviceConversationOrchestrator.swift` (Update)

```swift
func orchestrate(
  messages: [Message],
  conversation: Conversation,
  memories: [Memory],
  settings: AppSettings
) async throws -> (Message, [Memory]?) {
  let correlationId = UUID().uuidString

  // 1. Ground the conversation with Epistemic Engine
  let epistemicContext = try await epistemicEngine.ground(
    userMessage: messages.last?.content ?? "",
    memories: memories,
    correlationId: correlationId
  )

  // 2. Inject salient memories into system prompt
  let groundedContext = try await salienceService.injectSalient(
    conversation: conversation,
    epistemicContext: epistemicContext,
    availableTokens: 2000,
    correlationId: correlationId
  )

  // 3. Build system prompt with grounded context
  var systemPrompt = buildSystemPrompt(settings)
  systemPrompt += "\n\n" + groundedContext

  // 4. Call LLM with enhanced context
  PredicateLogger.shared.log(
    event: "llm_call_initiated",
    predicate: "llm_request_prepared",
    passed: true,
    scope: "domain.ai",
    metadata: ["groundedMemoriesCount": epistemicContext.groundedFacts.count],
    correlationId: correlationId
  )

  let response = try await callLLM(
    messages: messages,
    systemPrompt: systemPrompt,
    model: settings.defaultModel
  )

  PredicateLogger.shared.log(
    event: "llm_response_received",
    predicate: "llm_response_generated",
    passed: true,
    scope: "domain.ai",
    correlationId: correlationId
  )

  // 5. Extract memories from response
  let newMemories = try await extractMemories(
    from: response,
    conversation: conversation,
    correlationId: correlationId
  )

  // 6. Store epistemic context for learning loop
  try await storeEpistemicContext(epistemicContext, correlationId: correlationId)

  return (response, newMemories)
}
```

**Tasks:**
- [ ] Add epistemic grounding to orchestrate()
- [ ] Inject salient memories into system prompt
- [ ] Store epistemic context for learning loop
- [ ] Test with all providers

---

## Phase 4: Learning Loop (Weeks 4-5)

### 4.1 Create Learning Loop Service

**File:** `Axon/Services/Memory/LearningLoopService.swift` (NEW)

```swift
@MainActor
class LearningLoopService: ObservableObject {
  let memoryService: MemoryService
  let epistemicEngine: EpistemicEngine

  func processUserFeedback(
    userMessage: String,
    previousLLMResponse: String,
    memories: inout [Memory],
    epistemicContext: EpistemicContext,
    correlationId: String
  ) async throws {
    // 1. Detect contradictions
    PredicateLogger.shared.log(
      event: "contradiction_detection_started",
      predicate: "contradiction_detection_initiated",
      passed: true,
      scope: "domain.learning",
      correlationId: correlationId
    )

    let contradictions = detectContradictions(
      in: userMessage,
      against: previousLLMResponse,
      using: epistemicContext.groundedFacts
    )

    PredicateLogger.shared.log(
      event: "contradiction_detection_complete",
      predicate: "contradiction_detection_executed",
      passed: true,
      scope: "domain.learning",
      metadata: ["contradictionCount": contradictions.count],
      correlationId: correlationId
    )

    // 2. Update memories based on contradictions
    for contradiction in contradictions {
      PredicateLogger.shared.log(
        event: "memory_refinement_started",
        predicate: "memory_refinement_initiated",
        passed: true,
        scope: "domain.learning",
        correlationId: correlationId
      )

      let updatedIndex = memories.firstIndex { $0.id == contradiction.memoryId }
      if let index = updatedIndex {
        let oldConfidence = memories[index].confidence
        memories[index].confidence = contradiction.newConfidence
        memories[index].scope = contradiction.newScope
        memories[index].contradictionHistory = (memories[index].contradictionHistory ?? []) + [
          Contradiction(
            date: Date(),
            previousConfidence: oldConfidence,
            newConfidence: contradiction.newConfidence,
            evidence: contradiction.evidence,
            refiningCondition: contradiction.newScope
          )
        ]

        try await memoryService.updateMemory(memories[index])

        PredicateLogger.shared.log(
          event: "memory_refined",
          predicate: "memory_updated_from_evidence",
          passed: true,
          scope: "domain.learning",
          metadata: [
            "memoryId": memories[index].id,
            "oldConfidence": oldConfidence,
            "newConfidence": contradiction.newConfidence
          ],
          correlationId: correlationId
        )
      }
    }

    // 3. Create new memories if needed
    let newMemories = extractNewMemoriesFromFeedback(userMessage)
    for newMemory in newMemories {
      try await memoryService.saveMemory(newMemory)

      PredicateLogger.shared.log(
        event: "new_memory_created",
        predicate: "memory_created_from_feedback",
        passed: true,
        scope: "domain.learning",
        metadata: ["memoryId": newMemory.id],
        correlationId: correlationId
      )
    }

    PredicateLogger.shared.log(
      event: "learning_loop_complete",
      predicate: "learning_cycle_executed",
      passed: true,
      scope: "domain.learning",
      correlationId: correlationId
    )
  }

  private func detectContradictions(
    in userMessage: String,
    against llmResponse: String,
    using groundedFacts: [Memory]
  ) -> [MemoryContradiction] {
    // Simple implementation: extract claims from both and check for conflicts
    // Could be enhanced with Claude for sophisticated contradiction detection
    []
  }

  private func extractNewMemoriesFromFeedback(_ message: String) -> [Memory] {
    // Extract "I just learned..." or "I discovered..." patterns
    []
  }
}

struct MemoryContradiction {
  let memoryId: String
  let evidence: String
  let newConfidence: Double
  let newScope: String?
}
```

**Tasks:**
- [ ] Create LearningLoopService
- [ ] Implement contradiction detection
- [ ] Update memory confidence values
- [ ] Create new memories from feedback
- [ ] Track learning history

### 4.2 Integrate Learning Loop with Conversation

**File:** `Axon/Services/Conversation/ConversationService.swift` (Update)

```swift
func addMessage(
  conversationId: String,
  content: String,
  memories: inout [Memory],
  lastEpistemicContext: EpistemicContext?,
  lastLLMResponse: String?
) async throws {
  let correlationId = UUID().uuidString

  // If this is feedback on a previous LLM response, run learning loop
  if let epistemicContext = lastEpistemicContext,
     let llmResponse = lastLLMResponse {
    try await learningLoopService.processUserFeedback(
      userMessage: content,
      previousLLMResponse: llmResponse,
      memories: &memories,
      epistemicContext: epistemicContext,
      correlationId: correlationId
    )
  }

  // Add the message
  let message = Message(
    id: UUID().uuidString,
    conversationId: conversationId,
    content: content,
    role: "user",
    timestamp: Date()
  )

  try await messageStorage.saveMessage(message)

  PredicateLogger.shared.log(
    event: "message_added",
    predicate: "message_persisted",
    passed: true,
    scope: "domain.conversation",
    correlationId: correlationId
  )
}
```

**Tasks:**
- [ ] Integrate learning loop into message flow
- [ ] Pass epistemic context between turns
- [ ] Update memories from feedback
- [ ] Test learning loop with sample conversations

---

## Phase 5: Proxy Server Integration (Week 5)

### 5.1 Add Epistemic Endpoints

**File:** `Axon/Services/Server/APIServerService.swift` (Update)

```swift
// New endpoints for external tools

// GET /api/memories/ground?query=...
// Returns: Grounded facts + Shift Log + Confidence
app.get("/api/memories/ground") { request -> EpistemicContext in
  let query = request.query["q"]?.string ?? ""
  let epistemicContext = try await epistemicEngine.ground(
    userMessage: query,
    memories: memories,
    correlationId: request.headers["X-Correlation-ID"].first ?? ""
  )
  return epistemicContext
}

// GET /api/shift-logs/:id
// Returns: Specific Shift Log for transparency
app.get("/api/shift-logs/:id") { request -> ShiftLog in
  let shiftLogId = request.parameters["id"]?.string ?? ""
  return try await shiftLogService.getShiftLog(id: shiftLogId)
}

// POST /api/memories/learn
// Accept feedback and run learning loop
app.post("/api/memories/learn") { request -> [Memory] in
  let feedback = try request.content.decode(LearningFeedback.self)
  var memories = try await memoryService.getAllMemories()
  try await learningLoopService.processUserFeedback(
    userMessage: feedback.userMessage,
    previousLLMResponse: feedback.previousResponse,
    memories: &memories,
    epistemicContext: feedback.epistemicContext,
    correlationId: request.headers["X-Correlation-ID"].first ?? ""
  )
  return memories
}
```

**Tasks:**
- [ ] Add `/api/memories/ground` endpoint
- [ ] Add `/api/shift-logs` endpoint
- [ ] Add `/api/memories/learn` endpoint
- [ ] Document API contracts
- [ ] Test with Cline

### 5.2 Update ServerSettingsView

**File:** `Axon/Views/Settings/ServerSettingsView.swift` (Update)

```swift
// Add new section showing epistemic API availability
SettingsSection(title: "Epistemic API (For External Tools)") {
  VStack(spacing: 12) {
    Text("External tools like Cline can now use your memory system and learned patterns.")
      .font(AppTypography.bodySmall())

    Text("Endpoints:")
      .font(AppTypography.bodyMedium(.medium))

    VStack(alignment: .leading, spacing: 8) {
      EpistemicAPIRow(endpoint: "/api/memories/ground", description: "Ground a query with facts + confidence")
      EpistemicAPIRow(endpoint: "/api/shift-logs/:id", description: "Get transparency about what's known")
      EpistemicAPIRow(endpoint: "/api/memories/learn", description: "Provide feedback to refine memories")
    }
  }
  .padding()
  .background(AppColors.substrateSecondary)
  .cornerRadius(8)
}
```

**Tasks:**
- [ ] Add epistemic API section to ServerSettingsView
- [ ] Show available endpoints
- [ ] Document usage for external tools

---

## Phase 6: Release & Documentation (Week 6)

### 6.1 Architecture Documentation

**File:** `docs/UNIFIED_ARCHITECTURE.md`

**Contents:**
- [ ] Overview of Predicate Logging
- [ ] Overview of Epistemic Engine
- [ ] Overview of Learning Loop
- [ ] How they work together
- [ ] Data models and structures
- [ ] API contracts

**Tasks:**
- [ ] Write comprehensive architecture docs
- [ ] Create diagrams (predicate trees, epistemic flow)
- [ ] Write API documentation
- [ ] Create usage examples

### 6.2 Developer Guide

**File:** `docs/DEVELOPER_GUIDE.md`

**Contents:**
- [ ] How to instrument code with predicates
- [ ] How to use EpistemicEngine
- [ ] How to add new memory types
- [ ] How learning loop works
- [ ] How to integrate with external tools

**Tasks:**
- [ ] Write developer guide
- [ ] Create code examples
- [ ] Document best practices

### 6.3 Community Contribution Guide

**File:** `CONTRIBUTING.md`

**Tasks:**
- [ ] Write contribution guidelines
- [ ] Document code style
- [ ] Create issue templates
- [ ] Set up GitHub discussions

---

## Testing Strategy

### Unit Tests

```swift
// Test Predicate Logger
func testPredicateLoggerRecordsEvents() {
  let logger = PredicateLogger.shared
  logger.log(
    event: "test_event",
    predicate: "test_predicate",
    passed: true,
    scope: "test",
    correlationId: "test-123"
  )
  XCTAssertEqual(logger.logs.count, 1)
}

// Test Epistemic Engine
func testEpistemicEngineGrounds() async {
  let memories: [Memory] = [
    Memory(
      id: "mem1",
      content: "Test fact",
      type: .allocentric,
      confidence: 0.95,
      tags: ["test"],
      createdAt: Date(),
      updatedAt: Date()
    )
  ]

  let context = try await epistemicEngine.ground(
    userMessage: "test query",
    memories: memories,
    correlationId: "test-123"
  )

  XCTAssert(!context.groundedFacts.isEmpty)
  XCTAssertGreater(context.compositeConfidence, 0.0)
}
```

### Integration Tests

```swift
// Test full flow: epistemic grounding → salience injection → LLM response
func testFullEpistemicFlow() async {
  // 1. Ground
  let epistemicContext = try await epistemicEngine.ground(...)
  // 2. Inject
  let injected = try await salienceService.injectSalient(...)
  // 3. Verify format
  XCTAssert(injected.contains("GROUNDED CONTEXT"))
  XCTAssert(injected.contains("SHIFT LOG"))
}

// Test learning loop: feedback → memory update
func testLearningLoopUpdatesMemories() async {
  var memories = [testMemory]
  try await learningLoop.processUserFeedback(
    userMessage: "Actually, we switched to Auth0",
    previousLLMResponse: "You're using Firebase Auth",
    memories: &memories,
    epistemicContext: testContext,
    correlationId: "test-123"
  )
  XCTAssertLess(memories[0].confidence, 0.95)  // Confidence should decrease
}
```

**Tasks:**
- [ ] Write unit tests for PredicateLogger
- [ ] Write unit tests for EpistemicEngine
- [ ] Write unit tests for SalienceService
- [ ] Write integration tests for full flow
- [ ] Write learning loop tests

---

## Rollout Strategy

### Week 1: Foundation
- Deploy PredicateLogger (debug-only initially)
- Instrument core services
- Test predicate tree formation
- No user impact

### Week 2-3: Epistemic Engine
- Deploy EpistemicEngine
- Ground conversations before LLM calls
- Store Shift Logs
- Test with internal users
- Monitor confidence calculations

### Week 3-4: Salience Injection
- Deploy SalienceService
- Inject grounded facts into system prompt
- Test with all models
- Gather quality metrics
- Gradual rollout to users

### Week 4-5: Learning Loop
- Deploy LearningLoopService
- Run learning loop on user feedback
- Update memories from interactions
- Monitor memory refinement
- Full rollout

### Week 5: Proxy Server Integration
- Add epistemic endpoints
- Update ServerSettingsView
- Test with Cline and other tools
- Document API

### Week 6: Release
- Full documentation
- Community contribution guide
- Open source announcement
- Blog post explaining architecture

---

## Success Metrics

- [ ] Predicate logging captures 100% of critical operations
- [ ] Shift logs have > 0.90 confidence for grounded facts
- [ ] Salient memories improve response quality measurably
- [ ] Learning loop successfully refines memories
- [ ] External tools (Cline) can use epistemic API
- [ ] Community can understand and contribute to architecture
- [ ] System is deterministic and auditable

---

## Summary

This mapping translates the unified architecture into concrete implementation:

1. **Week 1:** Predicate Logging (execution proof)
2. **Weeks 2-3:** Epistemic Engine (knowledge grounding)
3. **Weeks 3-4:** Salience Injection (automatic context enrichment)
4. **Weeks 4-5:** Learning Loop (memory refinement)
5. **Week 5:** Proxy Server Integration (external tool access)
6. **Week 6:** Release & Documentation

Each phase is testable, deployable, and incrementally builds the complete vision.

Let's build the nervous system layer that makes any AI smarter. 🧠
