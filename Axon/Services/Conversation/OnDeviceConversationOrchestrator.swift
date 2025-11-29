//
//  OnDeviceConversationOrchestrator.swift
//  Axon
//
//  Implementation of ConversationOrchestrator that calls AI providers directly from the device.
//

import Foundation

class OnDeviceConversationOrchestrator: ConversationOrchestrator {
    
    func sendMessage(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment],
        geminiTools: Bool,
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> (assistantMessage: Message, memories: [Memory]?) {
        
        let systemPrompt = "You are Axon, a helpful AI assistant." // Could be configurable
        
        // 1. Prepare context (history)
        // Convert internal Message format to provider-specific format
        // For simplicity, we'll implement a generic handler or switch
        
        var responseContent: String = ""
        
        switch config.provider {
        case "anthropic":
            guard let apiKey = config.anthropicKey else { throw APIError.unauthorized }
            responseContent = try await callAnthropic(apiKey: apiKey, model: config.model, system: systemPrompt, messages: messages, newContent: content)
            
        case "openai":
            guard let apiKey = config.openaiKey else { throw APIError.unauthorized }
            responseContent = try await callOpenAI(apiKey: apiKey, model: config.model, system: systemPrompt, messages: messages, newContent: content)
            
        case "gemini":
            guard let apiKey = config.geminiKey else { throw APIError.unauthorized }
            responseContent = try await callGemini(apiKey: apiKey, model: config.model, system: systemPrompt, messages: messages, newContent: content)
            
        case "openai-compatible":
             guard let apiKey = config.customApiKey, let baseUrl = config.customBaseUrl else { throw APIError.unauthorized }
             responseContent = try await callOpenAICompatible(apiKey: apiKey, baseUrl: baseUrl, model: config.model, system: systemPrompt, messages: messages, newContent: content)
            
        default:
            throw APIError.networkError("Provider \(config.provider) not supported in On-Device mode yet.")
        }
        
        // 2. Create Assistant Message
        let assistantMessage = Message(
            conversationId: conversationId,
            role: .assistant,
            content: responseContent,
            modelName: config.model,
            providerName: config.providerName
        )
        
        // 3. Memory Extraction (Optional/Future)
        // In on-device mode, we might skip automatic memory extraction for now
        // or implement a second call to do it.
        
        return (assistantMessage, nil)
    }

    func regenerateAssistantMessage(
        conversationId: String,
        messageId: String,
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> Message {
        // For regeneration, we basically re-run the chat flow but with the history up to that point
        // This is a simplified implementation
        
        // Find the context
        // In a real implementation, we'd filter `messages` to exclude the one being regenerated and anything after it.
        // Assuming `messages` passed in is already the correct context or we need to filter.
        
        // Reuse sendMessage logic but with empty new content (assuming the last user message is in `messages`)
        // Actually, `sendMessage` appends new content.
        // We need to extract the last user message from `messages` if we want to "retry" it,
        // or just pass the history if the API supports it.
        
        // For now, throw not implemented or simple error
        throw APIError.networkError("Regeneration not fully implemented for On-Device mode yet.")
    }
    
    // MARK: - Provider Implementations
    
    private func callAnthropic(apiKey: String, model: String, system: String, messages: [Message], newContent: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        
        // Convert messages
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        apiMessages.append(["role": "user", "content": newContent])
        
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": apiMessages
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
             if let errorText = String(data: data, encoding: .utf8) {
                 print("Anthropic Error: \(errorText)")
             }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        // Decode response
        struct AnthropicResponse: Decodable {
            struct Content: Decodable {
                let text: String
            }
            let content: [Content]
        }
        
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }
    
    private func callOpenAI(apiKey: String, model: String, system: String, messages: [Message], newContent: String) async throws -> String {
        return try await callOpenAICompatible(apiKey: apiKey, baseUrl: "https://api.openai.com/v1", model: model, system: system, messages: messages, newContent: newContent)
    }
    
    private func callOpenAICompatible(apiKey: String, baseUrl: String, model: String, system: String, messages: [Message], newContent: String) async throws -> String {
        let url = URL(string: "\(baseUrl)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var apiMessages: [[String: Any]] = []
        apiMessages.append(["role": "system", "content": system])
        for msg in messages {
            apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        apiMessages.append(["role": "user", "content": newContent])
        
        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                 print("OpenAI Error: \(errorText)")
             }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }
    
    private func callGemini(apiKey: String, model: String, system: String, messages: [Message], newContent: String) async throws -> String {
        // Gemini API: https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
        // Model name usually needs "models/" prefix or just the ID.
        // The app uses "gemini-2.5-flash" etc.
        
        let modelId = model.starts(with: "models/") ? model : "models/\(model)"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(modelId):generateContent?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert messages to Gemini format (contents: [{role, parts: [{text}]}])
        // Gemini roles: "user", "model" (not "assistant")
        var contents: [[String: Any]] = []
        
        for msg in messages {
            let role = msg.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }
        contents.append([
            "role": "user",
            "parts": [["text": newContent]]
        ])
        
        let body: [String: Any] = [
            "contents": contents,
            "system_instruction": [
                "parts": [["text": system]]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                 print("Gemini Error: \(errorText)")
             }
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }
        
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return decoded.candidates?.first?.content.parts.first?.text ?? ""
    }
}
