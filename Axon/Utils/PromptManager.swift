//
//  PromptManager.swift
//  Axon
//
//  Manages personalized suggested prompts based on user memories.
//  Uses Apple Intelligence (free, on-device) as primary generator,
//  with fallback to direct Haiku API call (no conversation/thread creation).
//

import Foundation
import Combine

#if canImport(FoundationModels)
import FoundationModels

/// Structured output for Apple Intelligence prompt generation
@Generable
struct SuggestedPromptsOutput {
    @Guide(description: "A concise prompt (max 12 words) asking to explain a concept related to the user's interests")
    var explain: String

    @Guide(description: "A concise prompt (max 12 words) asking to write code related to the user's programming preferences")
    var code: String

    @Guide(description: "A concise prompt (max 12 words) asking to remember something new")
    var remember: String

    @Guide(description: "A concise prompt (max 12 words) asking to create a plan related to the user's goals")
    var plan: String
}
#endif

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

            // Create memory summary
            let memorySummary = memories.prefix(10).map { memory in
                "- [\(memory.type.displayName)] \(memory.content)"
            }.joined(separator: "\n")

            // Try Apple Intelligence first (free, on-device)
            if let prompts = await tryAppleIntelligence(memorySummary: memorySummary) {
                updatePrompts(prompts)
                print("[PromptManager] Generated prompts via Apple Intelligence (free)")
                return
            }

            // Fallback to direct Haiku API call (no conversation creation)
            if let prompts = await tryDirectHaikuAPI(memorySummary: memorySummary) {
                updatePrompts(prompts)
                print("[PromptManager] Generated prompts via direct Haiku API")
                return
            }

            print("[PromptManager] All generation methods failed, keeping current prompts")

        } catch {
            print("[PromptManager] Error generating prompts: \(error.localizedDescription)")
        }
    }

    // MARK: - Apple Intelligence (Primary - Free)

    private func tryAppleIntelligence(memorySummary: String) async -> SuggestedPrompts? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            print("[PromptManager] Apple Intelligence not available on this OS version")
            return nil
        }

        do {
            let prompt = """
            Based on these user memories, generate 4 personalized suggested prompts:

            \(memorySummary)

            Each prompt should be concise (max 12 words) and relevant to the user's interests shown in their memories.
            """

            let session = LanguageModelSession()
            let result = try await session.respond(to: prompt, generating: SuggestedPromptsOutput.self)

            return SuggestedPrompts(
                explain: validateWordCount(result.content.explain),
                code: validateWordCount(result.content.code),
                remember: validateWordCount(result.content.remember),
                plan: validateWordCount(result.content.plan)
            )
        } catch {
            print("[PromptManager] Apple Intelligence failed: \(error.localizedDescription)")
            return nil
        }
        #else
        print("[PromptManager] FoundationModels not available")
        return nil
        #endif
    }

    // MARK: - Direct Haiku API (Fallback - No Thread Creation)

    private func tryDirectHaikuAPI(memorySummary: String) async -> SuggestedPrompts? {
        // Get Anthropic API key
        guard let apiKey = try? APIKeysStorage.shared.getAPIKey(for: .anthropic),
              !apiKey.isEmpty else {
            print("[PromptManager] No Anthropic API key configured")
            return nil
        }

        let prompt = """
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

        do {
            let response = try await callAnthropicDirect(
                apiKey: apiKey,
                model: "claude-haiku-4-5-20251001",
                prompt: prompt
            )

            // Parse JSON response
            let jsonString = extractJSON(from: response)
            guard let data = jsonString.data(using: .utf8) else {
                print("[PromptManager] Failed to convert response to data")
                return nil
            }

            let newPrompts = try JSONDecoder().decode(SuggestedPrompts.self, from: data)

            return SuggestedPrompts(
                explain: validateWordCount(newPrompts.explain),
                code: validateWordCount(newPrompts.code),
                remember: validateWordCount(newPrompts.remember),
                plan: validateWordCount(newPrompts.plan)
            )
        } catch {
            print("[PromptManager] Direct Haiku API failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Direct API call to Anthropic - no conversation/thread creation
    private func callAnthropicDirect(apiKey: String, model: String, prompt: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "messages": [
                ["role": "user", "content": [["type": "text", "text": prompt]]]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PromptGenerationError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw PromptGenerationError.apiError(httpResponse.statusCode)
        }

        struct AnthropicResponse: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    // MARK: - Helpers

    private func extractJSON(from text: String) -> String {
        var content = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if content.hasPrefix("```json") {
            content = content.replacingOccurrences(of: "```json", with: "")
            content = content.replacingOccurrences(of: "```", with: "")
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if content.hasPrefix("```") {
            content = content.replacingOccurrences(of: "```", with: "")
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON object directly
        if let start = content.firstIndex(of: "{"),
           let end = content.lastIndex(of: "}") {
            return String(content[start...end])
        }

        return content
    }

    private func validateWordCount(_ prompt: String) -> String {
        let words = prompt.split(separator: " ")
        if words.count <= 12 {
            return prompt
        }
        // Truncate to 12 words if too long
        return words.prefix(12).joined(separator: " ")
    }

    private func updatePrompts(_ prompts: SuggestedPrompts) {
        self.currentPrompts = prompts
        if let encoded = try? JSONEncoder().encode(prompts) {
            UserDefaults.standard.set(encoded, forKey: currentPromptsKey)
        }
    }
}

// MARK: - Errors

enum PromptGenerationError: Error, LocalizedError {
    case networkError(String)
    case apiError(Int)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .apiError(let statusCode):
            return "API error: HTTP \(statusCode)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
