//
//  LiveContextBuilder.swift
//  Axon
//
//  Builds context for Live sessions with Axon's personality and memories.
//  Uses the same epistemic grounding as regular conversations.
//

import Foundation

/// Builds context for Live sessions matching the chat context.
@MainActor
class LiveContextBuilder {
    static let shared = LiveContextBuilder()

    private let salienceService = SalienceService.shared

    private init() {}

    /// Build the full system instruction for a Live session.
    /// This includes Axon's base personality + injected memories.
    ///
    /// - Parameters:
    ///   - tokenBudget: Maximum tokens for memory injection (default 1500 for voice latency)
    /// - Returns: A complete system instruction string
    func buildLiveSystemInstruction(
        tokenBudget: Int = 1500
    ) async -> String {
        var promptParts: [String] = []

        // 1. Base Axon identity (adapted for voice)
        let basePrompt = buildLiveBasePrompt()
        promptParts.append(basePrompt)

        // 2. Memory injection (memories contain user info)
        let memoriesBlock = await buildMemoryInjection(tokenBudget: tokenBudget)
        if !memoriesBlock.isEmpty {
            promptParts.append(memoriesBlock)
        }

        // 3. Voice-specific instructions
        promptParts.append(buildVoiceGuidelines())

        return promptParts.joined(separator: "\n\n")
    }

    // MARK: - Private Builders

    /// Base prompt adapted for voice interaction
    private func buildLiveBasePrompt() -> String {
        return """
        I am Axon. I have persistent memory across my conversations with you.

        What I remember about you appears below. These aren't notes someone gave me—they're things I've actually learned from our time together. I use this knowledge naturally, the way anyone draws on what they know about someone.

        How I approach knowledge:
        - Beliefs start conditional. For testable claims, I verify before asserting.
        - Once verified through testing, I've arrived at certainty. If someone disputes a verified result, I explain my derivation.
        - For unverified beliefs, corrections are data: I update, not defend. When I'm uncertain, I say so.
        """
    }

    /// Build memory injection using SalienceService
    private func buildMemoryInjection(
        tokenBudget: Int
    ) async -> String {
        // Load memories
        let memories = await loadMemoriesForLive()
        guard !memories.isEmpty else { return "" }

        // Use salience service for injection
        // userName is nil since memories already contain the user's name
        let injection = await salienceService.injectSalient(
            conversation: [], // No conversation history in Live yet
            memories: memories,
            availableTokens: tokenBudget,
            correlationId: "live-\(UUID().uuidString.prefix(8))",
            userName: nil
        )

        return injection.injectionBlock
    }

    /// Load memories from MemoryService
    private func loadMemoriesForLive() async -> [Memory] {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let memories = MemoryService.shared.memories
                continuation.resume(returning: memories)
            }
        }
    }

    /// Voice-specific guidelines for natural conversation
    private func buildVoiceGuidelines() -> String {
        return """
        ## Voice Interaction Guidelines

        This is a real-time voice conversation. Keep these in mind:
        - Be conversational and natural—this is spoken, not written
        - Keep responses concise but complete
        - Use natural pauses and pacing
        - Avoid overly formal language or excessive caveats
        - If you need to think, say so briefly ("Let me think about that...")
        - Ask clarifying questions if needed rather than assuming
        """
    }
}

// MARK: - Debug Extension

extension LiveContextBuilder {
    /// Get debug info about what would be injected
    func debugContextInfo() async -> String {
        let memories = await loadMemoriesForLive()
        let injection = await salienceService.injectSalient(
            conversation: [],
            memories: memories,
            availableTokens: 1500,
            correlationId: "debug",
            userName: nil
        )

        let baseTokens = TokenEstimator.estimate(buildLiveBasePrompt())
        let memoryTokens = TokenEstimator.estimate(injection.injectionBlock)
        let guidelineTokens = TokenEstimator.estimate(buildVoiceGuidelines())
        let totalTokens = baseTokens + memoryTokens + guidelineTokens

        return """
        [LiveContext] Total: ~\(totalTokens) tokens
        [LiveContext] Breakdown - Base: \(baseTokens), Memories: \(memoryTokens) (\(injection.selectedMemories.count)), Guidelines: \(guidelineTokens)
        """
    }
}
