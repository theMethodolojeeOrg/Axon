//
//  PromptManager.swift
//  Axon
//
//  Manages personalized suggested prompts based on user memories
//

import Foundation
import Combine

struct SuggestedPrompts: Codable {
    let explain: String
    let code: String
    let remember: String
    let plan: String
    
    static let defaults = SuggestedPrompts(
        explain: "Explain quantum computing in simple terms",
        code: "Write a Python function to sort a list",
        remember: "Remember that I prefer TypeScript over JavaScript",
        plan: "Help me plan a mobile app project"
    )
}

@MainActor
class PromptManager: ObservableObject {
    static let shared = PromptManager()
    
    private let viewCountKey = "PromptViewCount"
    private let currentPromptsKey = "CurrentPrompts"
    
    @Published private(set) var currentPrompts: SuggestedPrompts
    @Published private(set) var isGenerating = false
    
    private let conversationService = ConversationService.shared
    private let memoryService = MemoryService.shared
    
    private init() {
        // Load cached prompts or use defaults
        if let data = UserDefaults.standard.data(forKey: currentPromptsKey),
           let prompts = try? JSONDecoder().decode(SuggestedPrompts.self, from: data) {
            self.currentPrompts = prompts
        } else {
            self.currentPrompts = .defaults
        }
    }
    
    /// Call this method each time the welcome view appears
    func incrementViewCount() {
        var count = UserDefaults.standard.integer(forKey: viewCountKey)
        count += 1
        
        // Every 2nd view, generate new prompts
        if count >= 2 {
            Task {
                await generateNewPrompts()
            }
            count = 0
        }
        
        UserDefaults.standard.set(count, forKey: viewCountKey)
    }
    
    private func generateNewPrompts() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        
        do {
            // Fetch recent memories
            try await memoryService.getMemories(limit: 10)
            let memories = memoryService.memories
            
            // If no memories, keep current prompts
            guard !memories.isEmpty else {
                print("[PromptManager] No memories available, keeping current prompts")
                return
            }
            
            // Create memory summary for Claude
            let memorySummary = memories.prefix(10).map { memory in
                "- [\(memory.type.displayName)] \(memory.content)"
            }.joined(separator: "\n")
            
            // Create system prompt for Claude Haiku
            let systemPrompt = """
            Based on these user memories, generate 4 extremely concise suggested prompts (max 12 words each):
            
            1. "Explain a concept" - related to user's interests/knowledge
            2. "Write code" - related to user's programming preferences
            3. "Remember something" - help capture new information
            4. "Create a plan" - related to user's goals/projects
            
            Memories:
            \(memorySummary)
            
            Return ONLY valid JSON with no markdown formatting:
            {
              "explain": "prompt here",
              "code": "prompt here",
              "remember": "prompt here",
              "plan": "prompt here"
            }
            """
            
            // Create a temporary conversation for prompt generation
            let conversation = try await conversationService.createConversation(
                title: "Prompt Generation (Internal)",
                firstMessage: systemPrompt
            )
            
            // Override to use Claude Haiku 4.5
            let settingsStorage = SettingsStorage.shared
            var settings = settingsStorage.loadSettings() ?? AppSettings()
            let originalProvider = settings.defaultProvider
            let originalModel = settings.defaultModel
            
            // Temporarily set to Claude Haiku
            settings.defaultProvider = .anthropic
            settings.defaultModel = "claude-haiku-4-5-20251001"
            try? settingsStorage.saveSettings(settings)
            
            // Send message and get response
            let response = try await conversationService.sendMessage(
                conversationId: conversation.id,
                content: systemPrompt
            )
            
            // Restore original settings
            settings.defaultProvider = originalProvider
            settings.defaultModel = originalModel
            try? settingsStorage.saveSettings(settings)
            
            // Parse JSON response
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove markdown code blocks if present
            var jsonString = content
            if jsonString.hasPrefix("```json") {
                jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
                jsonString = jsonString.replacingOccurrences(of: "```", with: "")
                jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if jsonString.hasPrefix("```") {
                jsonString = jsonString.replacingOccurrences(of: "```", with: "")
                jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            guard let data = jsonString.data(using: .utf8) else {
                print("[PromptManager] Failed to convert response to data")
                return
            }
            
            let newPrompts = try JSONDecoder().decode(SuggestedPrompts.self, from: data)
            
            // Validate word counts (max 12 words each)
            let validatedPrompts = SuggestedPrompts(
                explain: validateWordCount(newPrompts.explain),
                code: validateWordCount(newPrompts.code),
                remember: validateWordCount(newPrompts.remember),
                plan: validateWordCount(newPrompts.plan)
            )
            
            // Update and cache
            self.currentPrompts = validatedPrompts
            if let encoded = try? JSONEncoder().encode(validatedPrompts) {
                UserDefaults.standard.set(encoded, forKey: currentPromptsKey)
            }
            
            print("[PromptManager] Successfully generated new prompts")
            
            // Clean up temporary conversation
            Task {
                try? await conversationService.deleteConversation(id: conversation.id)
            }
            
        } catch {
            print("[PromptManager] Error generating prompts: \(error.localizedDescription)")
            // Keep current prompts on error
        }
    }
    
    private func validateWordCount(_ prompt: String) -> String {
        let words = prompt.split(separator: " ")
        if words.count <= 12 {
            return prompt
        }
        // Truncate to 12 words if too long
        return words.prefix(12).joined(separator: " ")
    }
}
