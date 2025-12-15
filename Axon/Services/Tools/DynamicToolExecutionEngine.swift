//
//  DynamicToolExecutionEngine.swift
//  Axon
//
//  Engine for executing dynamic tool pipelines with support for
//  model calls, API calls, conditionals, and parallel execution.
//

import Foundation
import Combine
import os.log

@MainActor
final class DynamicToolExecutionEngine: ObservableObject {
    static let shared = DynamicToolExecutionEngine()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "DynamicToolExec")

    // MARK: - Published State

    @Published private(set) var isExecuting: Bool = false
    @Published private(set) var currentStep: String?
    @Published private(set) var progress: Double = 0

    // MARK: - Dependencies

    private let configService = DynamicToolConfigurationService.shared
    private let apiKeysStorage = APIKeysStorage.shared

    private init() {}

    // MARK: - Execution

    /// Execute a dynamic tool with given inputs
    func execute(
        toolId: String,
        inputs: [String: Any]
    ) async throws -> DynamicToolResult {
        guard let tool = configService.tool(withId: toolId) else {
            throw DynamicToolError.toolNotFound(toolId)
        }

        guard tool.enabled else {
            throw DynamicToolError.executionFailed("Tool '\(toolId)' is not enabled")
        }

        isExecuting = true
        progress = 0
        currentStep = nil

        defer {
            isExecuting = false
            currentStep = nil
            progress = 1.0
        }

        logger.info("Executing dynamic tool: \(toolId)")

        // Load required secrets
        var secrets: [String: String] = [:]
        for secretKey in tool.requiredSecrets {
            if let secret = try? loadSecret(forKey: secretKey) {
                secrets[secretKey] = secret
            } else {
                throw DynamicToolError.secretNotConfigured(secretKey)
            }
        }

        // Create execution context
        var context = PipelineExecutionContext(inputs: inputs, secrets: secrets)

        // Execute pipeline
        let totalSteps = Double(tool.pipeline.count)
        for (index, step) in tool.pipeline.enumerated() {
            currentStep = step.id
            progress = Double(index) / totalSteps

            let output = try await executeStep(step, context: &context)
            context.stepOutputs[step.id] = output
        }

        progress = 1.0

        // Format output using template
        let output: String
        if let template = tool.outputTemplate {
            output = context.resolve(template)
        } else if let lastOutput = context.stepOutputs[tool.pipeline.last?.id ?? ""] {
            output = String(describing: lastOutput)
        } else {
            output = "Tool executed successfully"
        }

        logger.info("Tool '\(toolId)' executed successfully")

        return DynamicToolResult(
            toolId: toolId,
            success: true,
            output: output,
            stepOutputs: context.stepOutputs
        )
    }

    // MARK: - Step Execution

    private func executeStep(
        _ step: PipelineStep,
        context: inout PipelineExecutionContext
    ) async throws -> Any {
        logger.debug("Executing step: \(step.id) (\(step.type.rawValue))")

        switch step.type {
        case .modelCall:
            return try await executeModelCall(step, context: context)

        case .apiCall:
            return try await executeAPICall(step, context: context)

        case .transform:
            return try executeTransform(step, context: context)

        case .conditional:
            return try await executeConditional(step, context: &context)

        case .parallel:
            return try await executeParallel(step, context: &context)

        case .loop:
            return try await executeLoop(step, context: &context)
        }
    }

    // MARK: - Model Call

    private func executeModelCall(
        _ step: PipelineStep,
        context: PipelineExecutionContext
    ) async throws -> Any {
        guard let config = step.config,
              let providerStr = config.provider,
              let modelId = config.model else {
            throw DynamicToolError.executionFailed("model_call step '\(step.id)' missing provider or model")
        }

        guard let provider = AIProvider(rawValue: providerStr) else {
            throw DynamicToolError.executionFailed("Unknown provider: \(providerStr)")
        }

        // Get API key for provider
        let apiProvider = mapToAPIProvider(provider)
        guard let apiKey = try? apiKeysStorage.getAPIKey(for: apiProvider) else {
            throw DynamicToolError.secretNotConfigured("\(providerStr)_api_key")
        }

        // Resolve prompts
        let systemPrompt = config.systemPrompt.map { context.resolve($0) }
        let userPrompt = config.userPrompt.map { context.resolve($0) } ?? ""

        // Build messages
        var messages: [[String: Any]] = []
        if let system = systemPrompt {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": userPrompt])

        // Call the appropriate API
        let response: String
        switch provider {
        case .anthropic:
            response = try await callAnthropicAPI(apiKey: apiKey, model: modelId, messages: messages)
        case .openai:
            response = try await callOpenAIAPI(apiKey: apiKey, model: modelId, messages: messages)
        case .gemini:
            response = try await callGeminiAPI(apiKey: apiKey, model: modelId, messages: messages)
        default:
            throw DynamicToolError.executionFailed("Provider \(providerStr) not supported for model calls")
        }

        // Parse JSON if requested
        if config.responseFormat == "json" {
            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return json
            }
        }

        return response
    }

    private func mapToAPIProvider(_ aiProvider: AIProvider) -> APIProvider {
        switch aiProvider {
        case .anthropic: return .anthropic
        case .openai: return .openai
        case .gemini: return .gemini
        case .xai: return .xai
        case .perplexity: return .perplexity
        case .deepseek: return .deepseek
        case .zai: return .zai
        case .minimax: return .minimax
        case .mistral: return .mistral
        }
    }

    // MARK: - API Call

    private func executeAPICall(
        _ step: PipelineStep,
        context: PipelineExecutionContext
    ) async throws -> Any {
        guard let config = step.config,
              let methodStr = config.method,
              let endpointTemplate = config.endpoint else {
            throw DynamicToolError.executionFailed("api_call step '\(step.id)' missing method or endpoint")
        }

        let endpoint = context.resolve(endpointTemplate)
        guard let url = URL(string: endpoint) else {
            throw DynamicToolError.executionFailed("Invalid URL: \(endpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = methodStr
        request.timeoutInterval = 60

        // Add headers
        if let headers = config.headers {
            for (key, value) in headers {
                request.setValue(context.resolve(value), forHTTPHeaderField: key)
            }
        }

        // Add body
        if let body = config.body, methodStr != "GET" {
            let resolvedBody = context.resolveInDictionary(body.toDictionary() ?? [:])
            request.httpBody = try JSONSerialization.data(withJSONObject: resolvedBody)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DynamicToolError.executionFailed("Invalid response from \(endpoint)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DynamicToolError.executionFailed("API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        // Try to parse as JSON
        if let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Transform

    private func executeTransform(
        _ step: PipelineStep,
        context: PipelineExecutionContext
    ) throws -> Any {
        guard let config = step.config,
              let expression = config.expression else {
            throw DynamicToolError.executionFailed("transform step '\(step.id)' missing expression")
        }

        // Simple template resolution for now
        return context.resolve(expression)
    }

    // MARK: - Conditional

    private func executeConditional(
        _ step: PipelineStep,
        context: inout PipelineExecutionContext
    ) async throws -> Any {
        guard let condition = step.condition else {
            throw DynamicToolError.executionFailed("conditional step '\(step.id)' missing condition")
        }

        let resolvedCondition = context.resolve(condition)
        let conditionMet = evaluateCondition(resolvedCondition)

        let stepsToExecute = conditionMet ? step.then : step.else

        var lastOutput: Any = conditionMet
        if let steps = stepsToExecute {
            for nestedStep in steps {
                let output = try await executeStep(nestedStep, context: &context)
                context.stepOutputs[nestedStep.id] = output
                lastOutput = output
            }
        }

        return lastOutput
    }

    private func evaluateCondition(_ condition: String) -> Bool {
        // Simple condition evaluation
        // Supports: "value == true", "value == false", "value != null"
        let trimmed = condition.trimmingCharacters(in: .whitespaces)

        if trimmed == "true" { return true }
        if trimmed == "false" { return false }

        // Check for == comparison
        if trimmed.contains("==") {
            let parts = trimmed.components(separatedBy: "==").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                return parts[0] == parts[1]
            }
        }

        // Check for != comparison
        if trimmed.contains("!=") {
            let parts = trimmed.components(separatedBy: "!=").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                return parts[0] != parts[1]
            }
        }

        // Default: treat non-empty as true
        return !trimmed.isEmpty && trimmed != "null" && trimmed != "nil"
    }

    // MARK: - Parallel

    private func executeParallel(
        _ step: PipelineStep,
        context: inout PipelineExecutionContext
    ) async throws -> Any {
        guard let parallelSteps = step.steps, !parallelSteps.isEmpty else {
            throw DynamicToolError.executionFailed("parallel step '\(step.id)' has no steps")
        }

        // Execute all steps concurrently
        var results: [String: Any] = [:]

        try await withThrowingTaskGroup(of: (String, Any).self) { group in
            for parallelStep in parallelSteps {
                // Create a copy of context for each parallel execution
                var stepContext = context

                group.addTask {
                    let output = try await self.executeStep(parallelStep, context: &stepContext)
                    return (parallelStep.id, output)
                }
            }

            for try await (stepId, output) in group {
                results[stepId] = output
                context.stepOutputs[stepId] = output
            }
        }

        return results
    }

    // MARK: - Loop

    private func executeLoop(
        _ step: PipelineStep,
        context: inout PipelineExecutionContext
    ) async throws -> Any {
        guard let config = step.config,
              let itemsTemplate = config.items,
              let thenSteps = step.then else {
            throw DynamicToolError.executionFailed("loop step '\(step.id)' missing items or then steps")
        }

        let itemsResolved = context.resolve(itemsTemplate)

        // Try to parse as JSON array
        guard let data = itemsResolved.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw DynamicToolError.executionFailed("loop items must be a JSON array")
        }

        let itemVariable = config.itemVariable ?? "item"
        var results: [Any] = []

        for (index, item) in items.enumerated() {
            // Add current item to context
            context.inputs[itemVariable] = item
            context.inputs["\(itemVariable)_index"] = index

            var lastOutput: Any = item
            for nestedStep in thenSteps {
                let output = try await executeStep(nestedStep, context: &context)
                context.stepOutputs[nestedStep.id] = output
                lastOutput = output
            }

            results.append(lastOutput)
        }

        return results
    }

    // MARK: - API Implementations

    private func callAnthropicAPI(
        apiKey: String,
        model: String,
        messages: [[String: Any]]
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert messages format for Anthropic
        var anthropicMessages: [[String: Any]] = []
        var systemPrompt: String?

        for msg in messages {
            if msg["role"] as? String == "system" {
                systemPrompt = msg["content"] as? String
            } else {
                anthropicMessages.append(msg)
            }
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": anthropicMessages
        ]

        if let system = systemPrompt {
            body["system"] = system
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DynamicToolError.executionFailed("Anthropic API error: \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw DynamicToolError.executionFailed("Failed to parse Anthropic response")
        }

        return text
    }

    private func callOpenAIAPI(
        apiKey: String,
        model: String,
        messages: [[String: Any]]
    ) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": messages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DynamicToolError.executionFailed("OpenAI API error: \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DynamicToolError.executionFailed("Failed to parse OpenAI response")
        }

        return content
    }

    private func callGeminiAPI(
        apiKey: String,
        model: String,
        messages: [[String: Any]]
    ) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert to Gemini format
        var contents: [[String: Any]] = []
        var systemInstruction: String?

        for msg in messages {
            let role = msg["role"] as? String ?? "user"
            let content = msg["content"] as? String ?? ""

            if role == "system" {
                systemInstruction = content
            } else {
                contents.append([
                    "role": role == "assistant" ? "model" : "user",
                    "parts": [["text": content]]
                ])
            }
        }

        var body: [String: Any] = ["contents": contents]
        if let system = systemInstruction {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DynamicToolError.executionFailed("Gemini API error: \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw DynamicToolError.executionFailed("Failed to parse Gemini response")
        }

        return text
    }

    // MARK: - Secret Loading

    private func loadSecret(forKey key: String) throws -> String {
        // Map common secret keys to API providers
        switch key {
        case "jules_api_key":
            // Jules uses a custom secret stored via SecureVault
            if let secret = try? SecureVault.shared.retrieveString(forKey: "custom_secret_jules") {
                return secret
            }
            throw DynamicToolError.secretNotConfigured(key)

        case "linear_api_key":
            if let secret = try? SecureVault.shared.retrieveString(forKey: "custom_secret_linear") {
                return secret
            }
            throw DynamicToolError.secretNotConfigured(key)

        case "perplexity_api_key":
            if let secret = try? apiKeysStorage.getAPIKey(for: .perplexity) {
                return secret
            }
            throw DynamicToolError.secretNotConfigured(key)

        case "openai_api_key":
            if let secret = try? apiKeysStorage.getAPIKey(for: .openai) {
                return secret
            }
            throw DynamicToolError.secretNotConfigured(key)

        case "anthropic_api_key":
            if let secret = try? apiKeysStorage.getAPIKey(for: .anthropic) {
                return secret
            }
            throw DynamicToolError.secretNotConfigured(key)

        case "gemini_api_key":
            if let secret = try? apiKeysStorage.getAPIKey(for: .gemini) {
                return secret
            }
            throw DynamicToolError.secretNotConfigured(key)

        default:
            // Try loading from custom secrets
            if let secret = try? SecureVault.shared.retrieveString(forKey: "custom_secret_\(key)") {
                return secret
            }
            throw DynamicToolError.secretNotConfigured(key)
        }
    }
}

// MARK: - Result Type

struct DynamicToolResult {
    let toolId: String
    let success: Bool
    let output: String
    let stepOutputs: [String: Any]

    func toToolResult() -> ToolResult {
        ToolResult(
            tool: toolId,
            success: success,
            result: output,
            sources: nil,
            memoryOperation: nil
        )
    }
}
