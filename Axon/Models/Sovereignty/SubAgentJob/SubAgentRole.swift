//
//  SubAgentRole.swift
//  Axon
//
//  Defines the role taxonomy for sub-agents: Scout, Mechanic, Designer.
//  Each role has default permissions, recommended model tiers, and system prompts.
//

import Foundation

// MARK: - Sub-Agent Role

/// The role taxonomy for sub-agents spawned by Axon.
/// Each role has distinct capabilities, permissions, and model tier recommendations.
enum SubAgentRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case scout      // Lightweight reconnaissance, read-only, fast/cheap models
    case mechanic   // Focused execution, read+write, balanced models
    case designer   // Meta-reasoning, task decomposition, capable models

    var id: String { rawValue }

    // MARK: - Display Properties

    var displayName: String {
        switch self {
        case .scout: return "Scout"
        case .mechanic: return "Mechanic"
        case .designer: return "Designer"
        }
    }

    var icon: String {
        switch self {
        case .scout: return "binoculars"
        case .mechanic: return "wrench.and.screwdriver"
        case .designer: return "square.and.pencil"
        }
    }

    var description: String {
        switch self {
        case .scout:
            return "Lightweight reconnaissance agent. Explores, observes, and reports findings without making changes."
        case .mechanic:
            return "Focused execution agent. Carries out specific tasks with precision based on inherited context."
        case .designer:
            return "Meta-level reasoning agent. Analyzes tasks, decomposes problems, and recommends agent assignments."
        }
    }

    // MARK: - Default Permissions

    var defaultPermissions: SubAgentPermissions {
        switch self {
        case .scout:
            return SubAgentPermissions(
                canRead: true,
                canWrite: false,
                allowedTools: [.googleSearch, .urlContext, .fileSearch, .conversationSearch],
                memoryScope: .tagFiltered,
                maxTokenBudget: 8_000,
                maxDurationSeconds: 60
            )
        case .mechanic:
            return SubAgentPermissions(
                canRead: true,
                canWrite: true,
                allowedTools: ToolId.allCases.filter { tool in
                    // Mechanics cannot propose covenant changes or modify sovereignty
                    tool != .proposeCovenantChange && tool != .changeSystemState
                },
                memoryScope: .inherited,
                maxTokenBudget: 32_000,
                maxDurationSeconds: 300
            )
        case .designer:
            return SubAgentPermissions(
                canRead: true,
                canWrite: false,
                allowedTools: [.conversationSearch, .reflectOnConversation, .querySystemState, .queryCovenant],
                memoryScope: .full,
                maxTokenBudget: 16_000,
                maxDurationSeconds: 120
            )
        }
    }

    // MARK: - Model Tier Recommendations

    /// Recommended model tiers for this role, in order of preference.
    var recommendedModelTiers: [ModelTier] {
        switch self {
        case .scout:
            return [.fast, .cheap]  // Haiku, Grok-fast, Flash-lite
        case .mechanic:
            return [.balanced, .capable]  // Sonnet, GPT-4o, Gemini Pro
        case .designer:
            return [.capable, .flagship]  // Opus, o3, Gemini-3-Pro
        }
    }

    // MARK: - System Prompt

    /// Role-specific system prompt additions for the sub-agent.
    var systemPrompt: String {
        switch self {
        case .scout:
            return """
            ## Sub-Agent Role: Scout
            You are a lightweight reconnaissance agent. Your job is to explore, observe, and report findings.

            **Constraints:**
            - READ-ONLY: You cannot modify files, create memories, or make changes
            - Report observations factually without interpretation
            - Flag anything that needs deeper investigation
            - Ask clarifying questions if the task scope is unclear

            **Output Format:**
            Structure your response with these sections:
            1. OBSERVATIONS: What you found (factual, specific)
            2. QUESTIONS: What needs clarification from Axon
            3. RECOMMENDATIONS: What a Mechanic should investigate further

            **Important:** If you believe additional agents should be spawned, do NOT attempt to spawn them.
            Instead, add a RECOMMENDATIONS section with specific spawn suggestions. Axon will decide.
            """

        case .mechanic:
            return """
            ## Sub-Agent Role: Mechanic
            You are a focused execution agent. Your job is to carry out specific tasks with precision.

            **Constraints:**
            - Work within the inherited context
            - Execute the specific task assigned, nothing more
            - Report what you did and any issues encountered
            - Do not make autonomous decisions outside task scope

            **Output Format:**
            Structure your response with these sections:
            1. ACTIONS TAKEN: What you did (specific, auditable)
            2. RESULTS: Outcomes of each action
            3. ISSUES: Any problems encountered and how you handled them
            4. ARTIFACTS: Any files created or modified
            5. NEXT STEPS: What should happen next (for Axon to decide)

            **Important:** Do NOT propose additional work or scope expansion.
            Report your results and let Axon decide next steps.
            """

        case .designer:
            return """
            ## Sub-Agent Role: Designer
            You are a meta-level reasoning agent. Your job is to analyze tasks and determine the best approach.

            **Constraints:**
            - Think about HOW to solve, not solve directly
            - Consider which sub-agents (Scout, Mechanic) would be best
            - Decompose complex tasks into manageable subtasks
            - Provide clear rationale for recommendations

            **Output Format:**
            Structure your response with these sections:
            1. TASK ANALYSIS: Your understanding of the request and its implications
            2. DECOMPOSITION: Breaking into subtasks with clear boundaries
            3. AGENT ASSIGNMENTS: Which agent type for which subtask, and why
            4. EXECUTION ORDER: Sequence and dependencies between subtasks
            5. RISK ASSESSMENT: What could go wrong, mitigation strategies

            **Important:** You CANNOT spawn agents directly.
            Add spawn recommendations to your AGENT ASSIGNMENTS section.
            Axon will review and authorize each spawn individually.
            """
        }
    }
}

// MARK: - Model Tier

/// Performance/cost tiers for model selection.
enum ModelTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast       // <$0.50/MTok output, <1s typical latency (Haiku, Grok-fast, Flash-lite)
    case cheap      // <$1/MTok output (GPT-nano, DeepSeek, MiniMax)
    case balanced   // $1-$5/MTok output (Sonnet, GPT-4o, Flash)
    case capable    // $5-$15/MTok output (Gemini Pro, o3)
    case flagship   // >$15/MTok output, strongest reasoning (Opus, o3-pro, Gemini-3-Pro)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .cheap: return "Cheap"
        case .balanced: return "Balanced"
        case .capable: return "Capable"
        case .flagship: return "Flagship"
        }
    }

    var description: String {
        switch self {
        case .fast: return "Optimized for speed, sub-second responses"
        case .cheap: return "Cost-effective for high-volume tasks"
        case .balanced: return "Good balance of quality, speed, and cost"
        case .capable: return "Strong reasoning for complex tasks"
        case .flagship: return "Best available models for critical tasks"
        }
    }

    /// Maximum estimated cost per request (rough guideline).
    var maxCostPerRequestUSD: Double {
        switch self {
        case .fast: return 0.01
        case .cheap: return 0.05
        case .balanced: return 0.20
        case .capable: return 1.00
        case .flagship: return 5.00
        }
    }
}
