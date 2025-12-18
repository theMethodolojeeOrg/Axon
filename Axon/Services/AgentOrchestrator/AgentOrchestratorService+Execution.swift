//
//  AgentOrchestratorService+Execution.swift
//  Axon
//
//  Job execution logic with attestation gate enforcement.
//
//  **Architectural Commandment #1**: The attestation is the cryptographic gatekeeper.
//  No valid signature = no execution.
//

import Foundation
import os.log

// MARK: - Execution Extension

extension AgentOrchestratorService {

    // MARK: - Execute Job

    /// Execute an approved job.
    ///
    /// **THE GATE**: This method strictly requires a valid approval attestation.
    /// The signature is verified before any API call is dispatched.
    func executeJob(_ jobId: String) async throws -> SubAgentJob {
        guard var job = activeJobs.first(where: { $0.id == jobId }) else {
            throw AgentOrchestratorError.jobNotFound(jobId)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // THE ATTESTATION GATE (Commandment #1)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        guard let attestation = job.approvalAttestation else {
            logger.error("Execution blocked: Job \(jobId.prefix(8)) has no approval attestation")
            throw AgentOrchestratorError.missingAttestation(jobId)
        }

        // Verify the attestation signature is valid
        let isValid = attestation.verify { [weak self] data in
            self?.sovereigntyService.generateSignature(data: data) ?? ""
        }

        guard isValid else {
            logger.error("Execution blocked: Job \(jobId.prefix(8)) attestation signature invalid")
            throw AgentOrchestratorError.invalidAttestation(jobId, reason: "Signature verification failed")
        }

        guard attestation.type == .approval else {
            throw AgentOrchestratorError.wrongAttestationType(expected: .approval, got: attestation.type)
        }

        guard job.state == .approved else {
            throw AgentOrchestratorError.invalidStateTransition(from: job.state, to: .running)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // EXECUTION SETUP
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        executingJobId = jobId

        // Create silo for this job
        let silo = SubAgentMemorySilo.create(for: job)
        silos[silo.id] = silo
        job = job.withSilo(silo.id)

        // Transition to running
        job = job.started()
        job = job.transitioning(to: .running, reason: "Execution started")
        updateJob(job)

        logger.info("Executing job \(jobId.prefix(8)) - role: \(job.role.rawValue)")

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MODEL SELECTION & CONTEXT BUILDING
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        do {
            // Select model for execution
            let (provider, model) = try selectModelForJob(job)
            logger.info("Selected \(provider.rawValue)/\(model) for job \(jobId.prefix(8))")

            // Build context with tag-filtered memories
            let context = try await buildContextForJob(job)

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // EXECUTE THE SUB-AGENT CALL
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            let startTime = Date()

            let result = try await executeSubAgentCall(
                job: job,
                provider: provider,
                model: model,
                context: context
            )

            let latencyMs = Date().timeIntervalSince(startTime) * 1000
            let costUSD = calculateCost(provider: provider, model: model, usage: result.tokenUsage)

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // PROCESS RESULTS
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            // Update silo with results
            if var updatedSilo = silos[silo.id] {
                for entry in result.siloEntries {
                    try? updatedSilo.addEntry(entry)
                }
                silos[silo.id] = updatedSilo
            }

            // Update job with result
            job = job.withResult(result.jobResult)
            job = job.withExecutionMetadata(
                provider: provider,
                model: model,
                tokenUsage: result.tokenUsage,
                costUSD: costUSD
            )

            // Determine next state based on result
            if let questions = result.jobResult.clarificationQuestions, !questions.isEmpty {
                job = job.transitioning(
                    to: .awaitingInput,
                    reason: "Sub-agent has \(questions.count) question(s)"
                )
            } else if result.jobResult.success {
                job = job.finished()
                job = job.transitioning(to: .completed, reason: "Task completed successfully")

                // Record success for affinity learning
                updateAffinitySuccess(
                    provider: provider,
                    modelId: model,
                    taskType: inferTaskType(from: job),
                    contextTags: job.contextInjectionTags,
                    latencyMs: latencyMs,
                    costUSD: costUSD
                )
            } else {
                job = job.transitioning(
                    to: .failed,
                    reason: result.jobResult.errorMessage ?? "Task failed"
                )

                // Record failure for affinity learning
                updateAffinityFailure(
                    provider: provider,
                    modelId: model,
                    taskType: inferTaskType(from: job),
                    contextTags: job.contextInjectionTags,
                    reason: .unknown,
                    taskSummary: job.task.prefix(200).description,
                    errorMessage: result.jobResult.errorMessage
                )
            }

            updateJob(job)
            executingJobId = nil

            logger.info("Job \(jobId.prefix(8)) execution completed - state: \(job.state.rawValue)")
            return job

        } catch {
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // HANDLE EXECUTION FAILURE
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            executingJobId = nil

            job = job.transitioning(to: .failed, reason: error.localizedDescription)
            job = job.withResult(SubAgentJobResult(
                summary: "Job failed",
                fullResponse: "",
                success: false,
                errorMessage: error.localizedDescription
            ))

            updateJob(job)

            // Record failure for affinity (if we know the model)
            if let provider = job.provider ?? job.executedProvider,
               let model = job.model ?? job.executedModel {
                let failureReason: FailureReason
                if let orchError = error as? AgentOrchestratorError {
                    failureReason = orchError.failureReasonForAffinity
                } else {
                    failureReason = .apiError
                }

                updateAffinityFailure(
                    provider: provider,
                    modelId: model,
                    taskType: inferTaskType(from: job),
                    contextTags: job.contextInjectionTags,
                    reason: failureReason,
                    taskSummary: job.task.prefix(200).description,
                    errorMessage: error.localizedDescription
                )
            }

            logger.error("Job \(jobId.prefix(8)) execution failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Sub-Agent Call

    /// Execute the actual API call to the sub-agent
    private func executeSubAgentCall(
        job: SubAgentJob,
        provider: AIProvider,
        model: String,
        context: SubAgentContext
    ) async throws -> SubAgentExecutionResult {
        let startTime = Date()

        // Build system prompt with role instructions
        var systemPrompt = job.role.systemPrompt

        // Add memory context if available
        if !context.memoryInjection.isEmpty {
            systemPrompt += "\n\n## Injected Context\n\(context.memoryInjection)"
        }

        // Add inherited context if available
        if let inherited = context.inheritedContext {
            systemPrompt += "\n\n## Inherited Context from Parent Job\n\(inherited)"
        }

        // Build user message with task
        let userMessage = job.task

        // Get API key for provider
        guard let apiKey = try getAPIKey(for: provider) else {
            throw AgentOrchestratorError.providerNotConfigured(provider)
        }

        // Make the API call
        let response = try await callProvider(
            provider: provider,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            timeout: job.permissions.timeoutInterval ?? 120
        )

        let latencyMs = Date().timeIntervalSince(startTime) * 1000

        // Parse response for structured output
        let parsed = parseSubAgentResponse(response, role: job.role)

        // Estimate token usage
        let inputTokens = estimateTokens(systemPrompt + userMessage)
        let outputTokens = estimateTokens(response)

        return SubAgentExecutionResult(
            jobResult: SubAgentJobResult(
                summary: parsed.summary,
                fullResponse: response,
                clarificationQuestions: parsed.questions.isEmpty ? nil : parsed.questions,
                artifactsProduced: parsed.artifacts.isEmpty ? nil : parsed.artifacts,
                siloEntriesCreated: nil,  // Will be set after silo update
                toolsUsed: nil,
                success: parsed.questions.isEmpty,  // If questions, needs input
                errorMessage: nil,
                spawnRecommendations: parsed.spawnRecommendations.isEmpty ? nil : parsed.spawnRecommendations
            ),
            siloEntries: parsed.siloEntries,
            tokenUsage: SubAgentTokenUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cachedTokens: 0
            ),
            latencyMs: latencyMs
        )
    }

    // MARK: - Provider API Calls

    private func callProvider(
        provider: AIProvider,
        model: String,
        apiKey: String,
        systemPrompt: String,
        userMessage: String,
        timeout: TimeInterval
    ) async throws -> String {
        switch provider {
        case .anthropic:
            return try await callAnthropic(
                apiKey: apiKey,
                model: model,
                system: systemPrompt,
                userMessage: userMessage,
                timeout: timeout
            )

        case .openai:
            return try await callOpenAI(
                apiKey: apiKey,
                model: model,
                system: systemPrompt,
                userMessage: userMessage,
                timeout: timeout
            )

        case .gemini:
            return try await callGemini(
                apiKey: apiKey,
                model: model,
                system: systemPrompt,
                userMessage: userMessage,
                timeout: timeout
            )

        case .xai:
            return try await callXAI(
                apiKey: apiKey,
                model: model,
                system: systemPrompt,
                userMessage: userMessage,
                timeout: timeout
            )

        case .deepseek:
            return try await callDeepSeek(
                apiKey: apiKey,
                model: model,
                system: systemPrompt,
                userMessage: userMessage,
                timeout: timeout
            )

        default:
            throw AgentOrchestratorError.providerNotConfigured(provider)
        }
    }

    // MARK: - Anthropic

    private func callAnthropic(
        apiKey: String,
        model: String,
        system: String,
        userMessage: String,
        timeout: TimeInterval
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": [["role": "user", "content": userMessage]]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentOrchestratorError.apiCallFailed("Anthropic: \(errorText)")
        }

        struct AnthropicResponse: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    // MARK: - OpenAI

    private func callOpenAI(
        apiKey: String,
        model: String,
        system: String,
        userMessage: String,
        timeout: TimeInterval
    ) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentOrchestratorError.apiCallFailed("OpenAI: \(errorText)")
        }

        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    // MARK: - Gemini

    private func callGemini(
        apiKey: String,
        model: String,
        system: String,
        userMessage: String,
        timeout: TimeInterval
    ) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": userMessage]]]
            ],
            "systemInstruction": ["parts": [["text": system]]],
            "generationConfig": ["maxOutputTokens": 4096]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentOrchestratorError.apiCallFailed("Gemini: \(errorText)")
        }

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return decoded.candidates.first?.content.parts.first?.text ?? ""
    }

    // MARK: - xAI (Grok)

    private func callXAI(
        apiKey: String,
        model: String,
        system: String,
        userMessage: String,
        timeout: TimeInterval
    ) async throws -> String {
        let url = URL(string: "https://api.x.ai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentOrchestratorError.apiCallFailed("xAI: \(errorText)")
        }

        struct XAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(XAIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    // MARK: - DeepSeek

    private func callDeepSeek(
        apiKey: String,
        model: String,
        system: String,
        userMessage: String,
        timeout: TimeInterval
    ) async throws -> String {
        let url = URL(string: "https://api.deepseek.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentOrchestratorError.apiCallFailed("DeepSeek: \(errorText)")
        }

        struct DeepSeekResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    // MARK: - Response Parsing

    private func parseSubAgentResponse(
        _ response: String,
        role: SubAgentRole
    ) -> ParsedSubAgentResponse {
        var questions: [String] = []
        var siloEntries: [SiloEntry] = []
        var artifacts: [String] = []
        var spawnRecommendations: [SpawnRecommendation] = []

        // Parse sections based on role output format
        let sections: [(String, SiloEntryType)] = [
            ("OBSERVATIONS", .observation),
            ("ACTIONS TAKEN", .observation),
            ("TASK ANALYSIS", .observation),
            ("RESULTS", .inference),
            ("DECOMPOSITION", .inference),
            ("ISSUES", .observation),
            ("RECOMMENDATIONS", .recommendation),
            ("AGENT ASSIGNMENTS", .recommendation),
            ("RISK ASSESSMENT", .inference),
            ("ARTIFACTS", .artifact),
            ("NEXT STEPS", .inference)
        ]

        for (sectionName, entryType) in sections {
            if let content = extractSection(named: sectionName, from: response) {
                siloEntries.append(SiloEntry(
                    type: entryType,
                    content: content,
                    confidence: 0.8,
                    tags: [sectionName.lowercased().replacingOccurrences(of: " ", with: "_"), role.rawValue]
                ))

                // Track artifacts
                if entryType == .artifact {
                    artifacts.append(sectionName)
                }

                // Parse spawn recommendations from AGENT ASSIGNMENTS
                if sectionName == "AGENT ASSIGNMENTS" {
                    let parsed = parseSpawnRecommendations(from: content)
                    spawnRecommendations.append(contentsOf: parsed)
                }
            }
        }

        // Parse QUESTIONS section
        if let questionsContent = extractSection(named: "QUESTIONS", from: response) {
            questions = parseQuestionsList(from: questionsContent)

            if !questions.isEmpty {
                siloEntries.append(SiloEntry(
                    type: .question,
                    content: questions.joined(separator: "\n"),
                    tags: ["questions", role.rawValue]
                ))
            }
        }

        // If no sections parsed, store full response
        if siloEntries.isEmpty {
            siloEntries.append(SiloEntry(
                type: .observation,
                content: response,
                confidence: 0.7,
                tags: [role.rawValue, "full_response"]
            ))
        }

        // Generate summary
        let summary = generateSummary(from: response, siloEntries: siloEntries)

        return ParsedSubAgentResponse(
            summary: summary,
            questions: questions,
            siloEntries: siloEntries,
            artifacts: artifacts,
            spawnRecommendations: spawnRecommendations
        )
    }

    private func extractSection(named name: String, from text: String) -> String? {
        // Look for section header (case-insensitive)
        let patterns = [
            "\(name):",
            "## \(name)",
            "**\(name)**:",
            "### \(name)"
        ]

        var startIndex: String.Index?
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .caseInsensitive) {
                startIndex = range.upperBound
                break
            }
        }

        guard let start = startIndex else { return nil }

        let afterSection = text[start...]

        // Find next section or end
        let nextSectionPatterns = [
            "OBSERVATIONS:", "ACTIONS TAKEN:", "TASK ANALYSIS:",
            "RESULTS:", "DECOMPOSITION:", "ISSUES:",
            "RECOMMENDATIONS:", "AGENT ASSIGNMENTS:",
            "RISK ASSESSMENT:", "NEXT STEPS:", "QUESTIONS:",
            "ARTIFACTS:", "## ", "### ", "**"
        ]

        var endIndex = afterSection.endIndex
        for pattern in nextSectionPatterns {
            if let nextRange = afterSection.range(of: pattern, options: .caseInsensitive),
               nextRange.lowerBound > afterSection.startIndex,
               nextRange.lowerBound < endIndex {
                endIndex = nextRange.lowerBound
            }
        }

        let content = String(afterSection[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    private func parseQuestionsList(from content: String) -> [String] {
        var questions: [String] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•") ||
               trimmed.first?.isNumber == true {
                let question = trimmed
                    .drop(while: { !$0.isLetter })
                    .trimmingCharacters(in: .whitespaces)
                if !question.isEmpty {
                    questions.append(String(question))
                }
            }
        }

        return questions
    }

    private func parseSpawnRecommendations(from content: String) -> [SpawnRecommendation] {
        var recommendations: [SpawnRecommendation] = []

        // Look for patterns like "Scout for: ..." or "Mechanic: ..."
        let rolePatterns: [(SubAgentRole, [String])] = [
            (.scout, ["scout for:", "scout:", "deploy scout"]),
            (.mechanic, ["mechanic for:", "mechanic:", "deploy mechanic"]),
            (.designer, ["designer for:", "designer:", "deploy designer"])
        ]

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let lineLower = line.lowercased()

            for (role, patterns) in rolePatterns {
                for pattern in patterns {
                    if lineLower.contains(pattern) {
                        // Extract the task description after the pattern
                        if let range = lineLower.range(of: pattern) {
                            let task = String(line[range.upperBound...])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !task.isEmpty {
                                recommendations.append(SpawnRecommendation(
                                    role: role,
                                    task: task,
                                    rationale: "Recommended by sub-agent",
                                    priority: .medium
                                ))
                            }
                        }
                        break
                    }
                }
            }
        }

        return recommendations
    }

    private func generateSummary(from response: String, siloEntries: [SiloEntry]) -> String {
        // Try to use RESULTS or first inference
        if let results = siloEntries.first(where: { $0.type == .inference }) {
            return String(results.content.prefix(200))
        }

        // Fall back to first 200 chars of response
        return String(response.prefix(200))
    }

    // MARK: - Helpers

    private func getAPIKey(for provider: AIProvider) throws -> String? {
        guard let apiProvider = provider.apiProvider else {
            return nil
        }
        return try apiKeysStorage.getAPIKey(for: apiProvider)
    }

    private func estimateTokens(_ text: String) -> Int {
        // Rough estimate: ~4 characters per token
        max(1, text.count / 4)
    }

    func calculateCost(provider: AIProvider, model: String, usage: SubAgentTokenUsage) -> Double {
        // Get pricing from ModelConfigurationService or PricingRegistry
        let pricing: ModelPricing
        if let jsonPricing = ModelConfigurationService.shared.pricing(for: model) {
            pricing = jsonPricing
        } else {
            let canonical = PricingKeyResolver.canonicalKey(for: model) ?? PricingKeyResolver.defaultKey(for: provider)
            pricing = PricingRegistry.price(for: canonical, usedContextTokens: nil, inputIsAudio: false)
        }

        let inputCost = Double(usage.inputTokens) * pricing.inputPerMTokUSD / 1_000_000
        let outputCost = Double(usage.outputTokens) * pricing.outputPerMTokUSD / 1_000_000
        return inputCost + outputCost
    }
}

// MARK: - Supporting Types

struct SubAgentExecutionResult {
    let jobResult: SubAgentJobResult
    let siloEntries: [SiloEntry]
    let tokenUsage: SubAgentTokenUsage
    let latencyMs: Double
}

struct ParsedSubAgentResponse {
    let summary: String
    let questions: [String]
    let siloEntries: [SiloEntry]
    let artifacts: [String]
    let spawnRecommendations: [SpawnRecommendation]
}
