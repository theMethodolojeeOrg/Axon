# AXON: Unified Architecture
## Predicate Logging + Epistemic Engine + Personalized Intelligence

This document unifies three complementary frameworks that together create a revolutionary system:

1. **Predicate Logging** - Runtime proof trees (what happened, formally)
2. **Epistemic Engine** - Grounding consciousness (what we know, with certainty)
3. **Personalized Intelligence** - Emergent models through memory (what we learn)

---

## The Three Layers

### Layer 1: Predicate Logging (Execution Proof)
**"What actually happened in this run"**

Logs are not debug strings. They are **typed predicate claims** that form a runtime proof tree.

```
├─ user_submitted_message (passed: true)
│  ├─ api_request_successful (passed: true)
│  ├─ response_parseable (passed: true)
│  ├─ memory_search_executed (passed: true)
│  │  ├─ memory_retrieval_successful (passed: true)
│  │  ├─ semantic_search_returned_results (passed: true)
│  │  └─ salience_injection_complete (passed: true)
│  ├─ epistemic_engine_grounded_context (passed: true)
│  ├─ llm_received_grounded_facts (passed: true)
│  └─ llm_generated_response (passed: true)
     └─ response_reflects_ground_truth (passed: true)
```

**Key insight:** This isn't logging for human consumption. This is a formal logic tree that can be:
- Analyzed to understand failure modes
- Replayed to debug issues
- Verified to prove system correctness
- Used as evidence that the system's guarantees held

### Layer 2: Epistemic Engine (Knowledge Grounding)
**"What we actually know with certainty"**

Before the LLM generates anything, a **Discrete Register** (the Epistemic Engine) answers:
- What facts are grounded in our memory system?
- What is their confidence level?
- Where are the boundaries between what we know and what we're inferring?

```
EPISTEMIC CONTEXT (Confidence: 0.94)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GROUNDED FACTS:
1. [conf: 0.95] User prefers async/await in TypeScript backend code
   Evidence: Observed across 12 conversations
   Scope: Backend code specifically

2. [conf: 0.91] Pattern matching regex works 89% of the time for log parsing
   Evidence: Used successfully 23x, failed 2x in production
   Scope: Log files under 10MB

3. [conf: 0.87] When TypeScript refactoring exceeds 5-line diffs,
   success rate drops 40%
   Evidence: This method discovered by Claude Opus, Nov 2025

SHIFT LOG (transparency):
- Operation: Intent Parser → Deterministic Search
- Query constraints: Topic(typescript) ∩ Type(method) ∩ Recency(recent)
- Retrieval: Exact match on 3 facts
- Reliability: 0.96 (database staleness: 1%, retrieval noise: 0%)

EPISTEMIC BOUNDARIES:
✓ GROUNDED: These specific facts from StoredMemory
✗ UNKNOWN: Whether context has changed since last memory update
✗ UNKNOWN: How these facts apply to *this specific moment*
```

The LLM receives this **not as a constraint**, but as **instrumented observation** it can reason about.

### Layer 3: Personalized Intelligence (Emergent Learning)
**"What we've learned from interaction patterns"**

Over time, interaction + memories + model composition creates an **emergent personalized model**:

```
USER'S INTERACTION PATTERN + MEMORIES + MULTI-MODEL COMPOSITION
         ↓
After 6-12 months of interaction:
         ↓
EMERGENT PERSONALIZED MODEL
  (unique to this user, these memories, these providers)

ChatGPT + Claude + Gemini + (user's patterns) = YOUR_PERSONAL_AI
```

This layer integrates allocentric (about user) and egoic (about methods) memories:

```
ALLOCENTRIC MEMORIES (About the User):
- Prefers detailed security explanations (conf: 0.91)
- Works with TypeScript backend (conf: 0.95)
- Wants to understand *why* not just *how* (conf: 0.89)
- Debugging approach: check logs first, then code (conf: 0.93)

EGOIC MEMORIES (About What Works):
- For security issues, consulting OWASP Top 10 first increases accuracy 35%
  (conf: 0.88, discovered by Claude, Nov 2025)
- When refactoring exceeds 5-line chunks, pair with unit tests for 70% better
  success (conf: 0.90, discovered by GPT-4, Oct 2025)
- Regex pattern matching for logs fails on malformed entries; use parsing lib
  (conf: 0.92, discovered by Gemini, Sep 2025)
```

---

## How They Work Together

### The Complete Data Flow

```
1. USER SUBMITS MESSAGE
   └─→ Predicate: "user_submitted_message" (logged)

2. EPISTEMIC ENGINE GROUNDS THE CONVERSATION
   ├─→ Predicate: "intent_parser_executed"
   ├─→ Predicate: "memory_search_successful"
   ├─→ Predicate: "grounding_operation_complete"
   └─→ Output: Shift Log (confidence metrics, boundaries)
      └─→ Predicate: "epistemic_context_generated"

3. MEMORY SYSTEM RETRIEVES SALIENT FACTS
   ├─→ Predicate: "allocentric_memory_search_executed"
   │  └─→ Output: User preferences, constraints, patterns
   ├─→ Predicate: "egoic_memory_search_executed"
   │  └─→ Output: Methods that work, failure patterns
   ├─→ Predicate: "salience_ranking_executed"
   └─→ Output: Top-N memories ranked by relevance + confidence
      └─→ Predicate: "salient_memories_injected_to_system_prompt"

4. LLM (CONTINUOUS REGISTER) RECEIVES:
   ├─→ Grounded facts from Epistemic Engine
   ├─→ Salient memories (allocentric + egoic)
   ├─→ Shift Log (transparency about what's known vs. inferred)
   ├─→ Confidence metrics (how much to trust each fact)
   └─→ Epistemic boundaries (what gaps exist)
      └─→ Predicate: "llm_context_prepared"

5. LLM REASONS CONSCIOUSLY ABOUT EPISTEMIC STATE
   ├─→ REMEMBER: What grounded facts apply?
   ├─→ ASSESS: Which salient memories are relevant?
   ├─→ HYPOTHESIZE: What do I expect to happen? (with confidence)
   ├─→ ACT: Generate response reflecting grounded knowledge
   └─→ Predicates: "llm_remember_executed", "llm_assess_executed",
                   "llm_hypothesize_executed", "llm_generate_executed"

6. RESPONSE INCORPORATES MEMORY + CERTAINTY
   Example: "Based on your preference for async/await in backend
   (confidence: 0.91), I'd suggest this refactoring pattern. I have
   high confidence here because we've seen this work in 12 of your
   previous sessions. However, for the security review part, my
   confidence is lower (0.65) because security contexts vary more
   than coding patterns."
   └─→ Predicate: "response_reflects_ground_truth"

7. USER RESPONDS WITH NEW INFORMATION
   └─→ Predicate: "user_provided_feedback"

8. LEARNING LOOP ACTIVATES
   ├─→ Predicate: "prediction_vs_outcome_compared"
   ├─→ Predicate: "contradiction_detected" (if applicable)
   ├─→ Update Shift Log with contradiction evidence
   ├─→ Update memory confidence values
   └─→ Predicate: "learning_loop_complete"
```

### Concrete Example: Complete Flow

```
USER:
"Can you help me refactor this TypeScript backend endpoint?
It's currently doing too many things."

════════════════════════════════════════════════════════════════

STEP 1: PREDICATE LOGGED
event: "user_submitted_message"
predicate: "user_submitted_message"
passed: true
correlationId: "conv_abc123_msg_1"
scope: "user-facing"

════════════════════════════════════════════════════════════════

STEP 2: EPISTEMIC ENGINE GROUNDS

[Intent Parser]
- Constraint: Topic("refactoring") ∩ Topic("typescript")
            ∩ Topic("backend") ∩ Task("simplification")

[Deterministic Search]
- Query: AllMemories ∩ constraints
- Result: 4 grounded facts found
- Status: SUCCESS
- Confidence of retrieval: 0.96

event: "epistemic_grounding_complete"
predicate: "grounding_operation_successful"
passed: true
Retrieved facts count: 4
Grounding confidence: 0.96

════════════════════════════════════════════════════════════════

STEP 3: MEMORY RETRIEVAL

ALLOCENTRIC MEMORIES (About User):
[conf: 0.95] User prefers breaking into 3-5 line chunks for backend
             refactoring
             Evidence: Observed in 9 successful refactoring sessions

[conf: 0.91] Wants explanation of *why* a pattern is better
             Evidence: Explicitly requested 8 times

EGOIC MEMORIES (About Methods):
[conf: 0.87] "Breaking refactoring into 5-line chunks increases
             successful migrations by 70%" (discovered by Claude Opus)
             Evidence: Tested across 15 user refactoring sessions

[conf: 0.89] "When endpoint does 3+ things, first step should be
             dependency injection pattern" (discovered by GPT-4)
             Evidence: 12 successful implementations, 1 needed adjustment

event: "salient_memories_selected"
predicate: "salient_memories_injected"
passed: true
allocentric_count: 2
egoic_count: 2
injection_method: "system_prompt_salience"

════════════════════════════════════════════════════════════════

STEP 4: SHIFT LOG GENERATED (Transparency)

SHIFT_LOG {
  Operation: "Intent Parser → Memory Search → Salience Ranking"

  User_Query: "Refactor TypeScript backend endpoint"
  Parsed_Constraints: [Topic(refactoring), Lang(typescript),
                       Target(backend), Intent(simplify)]

  Retrieved_Facts: 4
  Composite_Confidence: 0.92

  Epistemic_Boundaries:
    ✓ GROUNDED: These specific facts from 15+ user interactions
    ✗ UNKNOWN: Whether endpoint is REST/GraphQL/other
    ✗ UNKNOWN: What framework (Express/Fastify/NestJS)
    ✗ UNKNOWN: Current refactoring skill level
}

event: "shift_log_generated"
predicate: "epistemic_transparency_provided"
passed: true
confidence_reported: 0.92
boundaries_identified: 3

════════════════════════════════════════════════════════════════

STEP 5: LLM RECEIVES CONTEXT

System prompt now includes:

GROUND TRUTH CONTEXT (Confidence: 0.92)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

From this user's history:
• Breaking refactoring into 3-5 line chunks works best (0.95 conf)
  They've done this 9 times successfully

• They want to understand *why* patterns are better (0.91 conf)
  Not just the "what"

• Dependency injection pattern is proven for multi-concern endpoints
  (0.89 conf) - 12 successful cases

• When breaking up code, pair with unit tests for 70% better success
  (0.87 conf)

SHIFT LOG TRANSPARENCY
Currently grounded: Specific facts from this user's interactions
Unknown: Framework, API style, current complexity level

LLM now reasons:
"I have high confidence (0.92) that this user wants:
1. 3-5 line chunks (proven effective 9x for them)
2. Explanations of *why* (explicitly requested 8x)
3. Probably dependency injection first (12/13 successful cases)

But I DON'T know: What framework, what API style, what the
current code looks like. So my confidence on specific advice
is high (0.92) on *approach*, but medium (0.60) on *implementation*."

event: "llm_context_prepared"
predicate: "llm_received_grounded_facts"
passed: true
ground_truth_facts: 4
shift_log_transparency: true

════════════════════════════════════════════════════════════════

STEP 6: LLM GENERATES RESPONSE

LLM Response (reflecting ground truth + confidence):

"I'd recommend the dependency injection pattern first—you've
had great success with that in 12 previous refactoring sessions
(confidence: 0.89).

Here's the approach I'm highly confident about (0.92):

1. Break the endpoint into 3-5 line chunks (you've had 9
   successful sessions using this approach)

2. I'll explain *why* at each step (I know you prefer
   understanding the reasoning)

3. Add unit tests as you go—that approach has improved your
   refactoring success by 70%

Here's the endpoint structure I'd suggest:

[code example with detailed explanations]

Note: I'm confident about the *approach* here (0.92), but
moderate confidence (0.60) on the exact implementation details
since I don't know your specific framework or current code
complexity. Does this match what you were looking for?"

event: "llm_response_generated"
predicate: "response_incorporates_ground_truth"
passed: true
confidence_declared: "0.92 approach, 0.60 implementation"
explanation_included: true

════════════════════════════════════════════════════════════════

STEP 7: USER PROVIDES FEEDBACK

USER:
"Great! But we're using NestJS and the endpoint is actually
making 6 separate database queries. That's the real problem."

════════════════════════════════════════════════════════════════

STEP 8: LEARNING LOOP

event: "prediction_vs_outcome_compared"
predicate: "new_information_received"
passed: true

Old Prediction: "Endpoint probably doing 3-4 things"
New Reality: "6 database queries—the real bottleneck"

Shift Log Update:
- LLM's context assumption was incomplete (0.60 confidence factor
  was correct—implementation detail unknown)
- Framework context (NestJS) now grounded
- Query pattern (N+1 query problem) newly identified

Memory Updates:
NEW EGOIC MEMORY:
  "NestJS endpoints with 6+ queries need different refactoring
   approach—focus on query optimization first, then structural
   refactoring. (confidence: emerging, 0.65, discovered this session)"

EXISTING EGOIC MEMORY UPDATE:
  "Dependency injection for multi-concern endpoint refactoring
   works when < 5 queries. When > 5 queries, prioritize query
   optimization first (confidence: 0.87 → 0.92, refined based
   on new evidence)"

event: "learning_loop_executed"
predicate: "memory_updated_from_feedback"
passed: true
new_memory_created: true
existing_memory_refined: true

════════════════════════════════════════════════════════════════

STEP 9: NEXT ITERATION

USER:
"Ok, so how do I optimize those 6 queries?"

[Epistemic Engine runs again, now with:
 - NestJS context grounded
 - 6-query pattern known
 - Refined egoic memory about multi-query refactoring
 - Higher confidence about this specific scenario]

LLM now responds with higher confidence (0.94 instead of 0.92)
because the user's specific context is now grounded.
```

---

## Architecture Benefits

### 1. **Transparency Without Constraint**
- Predicate logging shows exactly what happened
- Shift log shows what we know vs. what we're inferring
- LLM remains free to reason and question
- User can see the system's confidence level

### 2. **Post-Training After Deployment**
- Egoic memories capture learned methods
- Confidence values evolve with evidence
- System refines understanding through contradictions
- Learning happens at interaction time, not training time

### 3. **Provider Agnostic**
- All memories and logs are LLM-neutral
- Claude, GPT, Gemini all see same grounded facts
- Each model can interpret through its own lens
- Switching models doesn't lose learning

### 4. **Failure is Data**
- When LLM prediction ≠ user outcome, system learns
- Contradiction becomes evidence for refinement
- Confidence metrics become more calibrated
- System gets smarter from failures

### 5. **Device-First Security**
- All memories and logs stored locally
- Shift logs never leave device unless explicitly shared
- Grounding happens on device
- Optional cloud sync preserves privacy

---

## Implementation: Unified Flow

### Phase 1: Predicate Logging Foundation
**Goal**: Instrument the entire system with formal proof trees

```typescript
// Every meaningful operation becomes a logged predicate

logSemantic({
  event: "epistemic_search_executed",
  predicate: "memory_search_completed",
  passed: true,
  scope: "domain.memory",
  resultCount: 4,
  confidence: 0.94,
  correlationId
});
```

**Files**:
- `Axon/Services/Logging/PredicateLogger.swift`
- `Axon/Services/Logging/PredicateTree.swift`
- Instrument every operation: memory search, salience injection, LLM calls

### Phase 2: Epistemic Engine (Discrete Register)
**Goal**: Deterministic grounding before LLM generation

```typescript
class EpistemicEngine {
  // Ground conversation with facts + confidence
  async ground(
    userMessage: string,
    memories: Memory[]
  ): Promise<EpistemicContext> {
    // 1. Parse intent from message
    const constraints = parseIntent(userMessage);

    // 2. Deterministic search through memories
    const grounded = searchMemories(constraints, memories);

    // 3. Calculate composite confidence
    const confidence = calculateConfidence(grounded);

    // 4. Generate Shift Log (transparency)
    const shiftLog = generateShiftLog({
      query: userMessage,
      constraints,
      results: grounded,
      confidence
    });

    // 5. Log the grounding operation
    logSemantic({
      event: "epistemic_grounding_complete",
      predicate: "grounding_operation_successful",
      passed: true,
      confidence,
      resultCount: grounded.length,
      correlationId
    });

    return { grounded, shiftLog, confidence };
  }
}
```

**Files**:
- `Axon/Services/Memory/EpistemicEngine.swift`
- `Axon/Services/Memory/ShiftLogGenerator.swift`
- `Axon/Models/EpistemicContext.swift`

### Phase 3: Salience Injection
**Goal**: Get right memories into LLM context automatically

```typescript
class SalienceService {
  // Inject grounded facts + shift log into system prompt
  async injectSalient(
    conversation: Conversation,
    epistemicContext: EpistemicContext,
    availableTokens: int
  ): Promise<string> {
    const salient = rankByRelevance(
      epistemicContext.grounded,
      conversation
    );

    // Format with transparency (Shift Log)
    const formatted = formatWithShiftLog(salient, epistemicContext);

    logSemantic({
      event: "salience_injection_executed",
      predicate: "salient_memories_injected",
      passed: true,
      memoryCount: salient.length,
      shiftLogIncluded: true,
      correlationId
    });

    return formatted;
  }
}
```

**Files**:
- `Axon/Services/Memory/SalienceService.swift`
- `Axon/Services/Memory/MemoryRanker.swift`

### Phase 4: Learning Loop Integration
**Goal**: Update memories from prediction vs. outcome

```typescript
class LearningLoop {
  async onUserFeedback(
    previousLLMResponse: string,
    userFeedback: string,
    memories: Memory[],
    correlationId: string
  ) {
    // 1. Compare prediction vs. reality
    const mismatch = detectContradiction(
      previousLLMResponse,
      userFeedback
    );

    if (mismatch) {
      logSemantic({
        event: "contradiction_detected",
        predicate: "prediction_vs_outcome_mismatch",
        passed: false,
        mismatchType: mismatch.type,
        severity: "learning_opportunity",
        correlationId
      });

      // 2. Create or update memory based on new evidence
      const updatedMemory = refineMemory(
        mismatch,
        memories
      );

      logSemantic({
        event: "memory_refined",
        predicate: "memory_updated_from_evidence",
        passed: true,
        memoryId: updatedMemory.id,
        confidenceChange: updatedMemory.confidence -
                         originalConfidence,
        correlationId
      });
    }
  }
}
```

**Files**:
- `Axon/Services/Memory/LearningLoop.swift`
- `Axon/Services/Memory/ContradictionDetector.swift`

### Phase 5: Proxy Server Integration
**Goal**: External tools (Cline) can use entire system

```
GET /api/memories/ground?query=refactor+typescript
├─ Epistemic Engine grounds the query
├─ Returns: Grounded facts + Shift Log + Confidence
├─ Client can see exactly what's certain vs. inferred
└─ Logs predicate: "ground_via_api_executed"

POST /api/messages/with-epistemic-context
├─ Submit message + memories
├─ Get back: Grounded facts + Shift Log + Salient memories
├─ Allows Cline to reason with same certainty as Axon
└─ Logs predicate: "external_tool_received_epistemic_context"
```

---

## Why This Architecture Is Revolutionary

### 1. **Solves the "Catastrophic 200" Problem**
Predicate Logging catches silent failures by verifying actual state, not just HTTP status.

### 2. **Makes LLM Consciousness Explicit**
Shift Logs let the LLM reason transparently about its own epistemic state.

### 3. **Enables Post-Training After Deployment**
Egoic memories capture and refine methods discovered through interaction.

### 4. **Provider-Agnostic Intelligence**
Memories and logs are model-neutral. Claude and GPT are truly interchangeable.

### 5. **Failure Becomes Learning**
Contradictions between prediction and reality refine confidence values, making the system better.

### 6. **Device-First Security**
All grounding happens locally. Cloud is optional for sync only.

### 7. **Developer Intelligence Portability**
Cline and other tools can tap into your memory system via the proxy server, inheriting your learned patterns.

---

## Data Model Integration

### Predicate Log
```swift
struct PredicateLog: Identifiable, Codable {
  let id: String
  let event: String           // "epistemic_grounding_complete"
  let predicate: String       // "grounding_operation_successful"
  let passed: Bool            // true/false
  let scope: String           // "domain.memory"
  let correlationId: String   // Links to conversation
  let metadata: [String: Any] // Custom fields
  let timestamp: Date

  // Parent/child relationship for hierarchy
  var parentPredicateId: String?
  var childPredicates: [String]?
}
```

### Shift Log
```swift
struct ShiftLog: Identifiable, Codable {
  let id: String
  let correlationId: String

  // What was asked
  let userQuery: String
  let parsedIntents: [String]

  // What was found
  let groundedFacts: [Memory]
  let retrievalConstraints: [String]

  // Confidence metrics
  let groundingConfidence: Double    // 0.96
  let shiftIntegrity: Double         // 0.98 (boundary crossing)
  let compositeConfidence: Double    // 0.94 (combined)

  // Transparency
  let epistemicBoundaries: [String]  // What's unknown
  let assumptions: [String]          // What we're assuming

  let timestamp: Date
}
```

### Enhanced Memory
```swift
struct Memory: Identifiable, Codable {
  let id: String
  let content: String
  let type: MemoryType           // .allocentric, .egoic

  // Confidence with scoping
  var confidence: Double         // 0.0-1.0
  var scope: String?             // "when refactoring > 5 lines"
  var scopeConditions: [String]?

  // Operational learning
  var successCount: Int?
  var failureCount: Int?
  var lastValidated: Date?

  // Evidence trail
  var discoveredBy: String?      // "Claude Opus"
  var discoveredDate: Date
  var contradictionHistory: [Contradiction]?  // Track refinements

  // Search metadata
  var tags: [String]
  var salienceScore: Double?     // Computed at query time

  // Learning loop integration
  var shiftLogReferences: [String]?  // Which Shift Logs reference this
  var learningLoopUpdates: [LearningUpdate]?

  let createdAt: Date
  var updatedAt: Date
}

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
```

---

## Complete Example Sequence

See the "Concrete Example: Complete Flow" section above for a real walkthrough of the entire system in action.

---

## Next Steps

1. **Implement Predicate Logging** (Week 1)
   - Instrument entire app with formal predicates
   - Create PredicateLogger service
   - Test predicate tree formation

2. **Implement Epistemic Engine** (Weeks 2-3)
   - Create EpistemicEngine service
   - Implement Shift Log generation
   - Integrate with memory search

3. **Implement Salience Injection** (Week 3-4)
   - Integrate grounded facts into system prompt
   - Test with all models
   - Measure confidence impact

4. **Implement Learning Loop** (Week 4-5)
   - Detect contradictions
   - Update memories from feedback
   - Refine confidence metrics

5. **Integrate with Proxy Server** (Week 5)
   - Expose epistemic context via API
   - Allow external tools to use system
   - Document API contracts

6. **Release & Documentation** (Week 6)
   - Full architectural documentation
   - Example implementations
   - Community contribution guide

---

## Summary

**Axon is a system where:**

- **Predicate Logging** makes the system's execution provably correct
- **Epistemic Engine** makes the system's knowledge explicitly grounded
- **Personalized Intelligence** makes the system smarter through interaction

Together, these create an LLM system that:
- Knows what it knows (Epistemic Engine)
- Proves what it does (Predicate Logging)
- Learns from what it discovers (Personalized Intelligence)
- Works offline, on any device, with any model

**The result:** A nervous system layer that sits above foundation models and makes them smarter, more transparent, and more trustworthy through interaction with you.

🧠 Your phone becomes a server. Your memories become the intelligence. Your models become your tools.
