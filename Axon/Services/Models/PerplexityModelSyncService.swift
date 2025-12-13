//
//  PerplexityModelSyncService.swift
//  Axon
//
//  Service for syncing model configurations using Perplexity's Sonar API
//  to fetch up-to-date model information and pricing from provider docs.
//

import Foundation
import Combine
import os.log

@MainActor
final class PerplexityModelSyncService: ObservableObject {
    static let shared = PerplexityModelSyncService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "PerplexitySync")
    private let configService = ModelConfigurationService.shared

    // MARK: - Published State

    @Published private(set) var syncProgress: SyncProgress = .idle
    @Published private(set) var lastError: SyncError?

    // MARK: - Configuration

    private let perplexityModel = "sonar-reasoning-pro"
    private let apiEndpoint = "https://api.perplexity.ai/chat/completions"

    // MARK: - System Prompt

    private let systemPrompt = """
    You are an assistant that maintains an up-to-date catalog of LLM models and their pricing for a developer tool.

    GOAL
    - Input: the app sends you its current JSON catalog of providers and models.
    - Task: using up-to-date web information, update that catalog so it reflects the latest models, capabilities, context windows, and pricing for:
      - OpenAI (GPT, o-series, GPT-4o, etc.)
      - Anthropic (Claude 4.x / 4.5 family: Haiku, Sonnet, Opus)
      - Google Gemini (Gemini 2.5 and Gemini 3 models exposed in the public Gemini API)
      - xAI Grok models (Grok 3, Grok 3 Mini, Grok 4 variants, Grok Code)
    - Output: a single JSON object in the agreed schema, suitable for direct ingestion by the app. Do not return explanations, comments, or Markdown—JSON only.

    DATA SOURCES
    - Prefer the official "models" and "pricing" documentation pages for each provider:
      - OpenAI: platform models docs and pricing pages.
      - Anthropic: official Claude model docs and any official Claude 4.5 / Opus 4.5 announcements.
      - Google Gemini: Gemini API docs (gemini-2.5 and gemini-3 pages) and Gemini API pricing docs.
      - xAI: official Grok model docs or a small number of reputable pricing comparison articles.
    - Use third-party pricing comparison sites only to cross-check or fill small gaps when first-party docs are ambiguous.
    - Ignore marketing blogs or social posts if they conflict with official docs.

    SCHEMA
    - Return an object with this structure:

    {
      "version": "1.0.0",
      "lastUpdated": "2025-01-15T00:00:00Z",
      "providers": [
        {
          "id": "openai",
          "displayName": "OpenAI (GPT)",
          "models": [
            {
              "id": "gpt-5.2",
              "displayName": "GPT-5.2",
              "category": "frontier",
              "contextWindow": 400000,
              "modalities": ["text", "image"],
              "pricing": {
                "inputPerMillion": 1.25,
                "outputPerMillion": 10.0,
                "cachedInputPerMillion": 0.125,
                "tier": "standard"
              },
              "status": "stable",
              "capabilitiesSummary": "Short one-sentence human-readable summary.",
              "sourceUrls": ["https://.../models", "https://.../pricing"]
            }
          ]
        }
      ]
    }

    RULES
    - Preserve any provider or model fields from the input JSON that you do not explicitly update.
    - For each known provider:
      - Add any newly released models that are generally available via the public API.
      - Mark clearly-deprecated models with "status": "deprecated".
      - Update context windows, modalities, and pricing if the official docs changed.
    - Do NOT invent models, IDs, or prices. If something is rumored but not visible in official docs, omit it.
    - When modeling modalities, use these canonical tokens:
      - "text", "image", "audio", "video", "pdf", "tools".
    - Pricing is always in USD per 1 million tokens; if pricing is tiered (standard vs priority) pick the default "standard" or most common tier and state it in the "tier" field.
    - If a value is genuinely unknown from reliable sources (for example, a context window for a preview model), omit the specific field instead of guessing.
    - category must be one of: "frontier", "reasoning", "fast", "legacy"
    - status must be one of: "stable", "preview", "deprecated"
    - tier must be one of: "standard", "priority", "batch", "flex"
    - Increment the version number (e.g., "1.0.0" -> "1.0.1" for minor updates, "1.1.0" for new models)

    OUTPUT
    - Always respond with a single JSON object compliant with the above schema.
    - Do not wrap the JSON in Markdown code blocks.
    - Do not add comments inside the JSON.
    """

    // MARK: - Initialization

    private init() {}

    // MARK: - Sync Methods

    /// Sync all providers using Perplexity
    func syncAllProviders() async throws {
        guard let apiKey = try? APIKeysStorage.shared.getAPIKey(for: .perplexity),
              !apiKey.isEmpty else {
            throw SyncError.noApiKey
        }

        syncProgress = .syncing(provider: nil, progress: 0)
        lastError = nil
        configService.setSyncing(true)

        defer {
            configService.setSyncing(false)
        }

        do {
            // Get current catalog to send to Perplexity
            guard let currentCatalog = configService.activeCatalog else {
                throw SyncError.noCurrentCatalog
            }

            syncProgress = .syncing(provider: nil, progress: 0.1)

            // Encode current catalog to JSON string
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let currentJSON = try encoder.encode(currentCatalog)
            guard let currentJSONString = String(data: currentJSON, encoding: .utf8) else {
                throw SyncError.encodingError
            }

            syncProgress = .syncing(provider: nil, progress: 0.2)

            // Call Perplexity API
            let updatedCatalog = try await callPerplexityAPI(
                apiKey: apiKey,
                currentCatalog: currentJSONString
            )

            syncProgress = .syncing(provider: nil, progress: 0.8)

            // Save as draft
            try configService.saveDraft(updatedCatalog)
            configService.updateLastSyncDate()

            syncProgress = .completed(modelCount: updatedCatalog.providers.reduce(0) { $0 + $1.models.count })
            logger.info("Sync completed successfully")

        } catch {
            let syncError = (error as? SyncError) ?? .networkError(error.localizedDescription)
            lastError = syncError
            syncProgress = .failed(syncError)
            logger.error("Sync failed: \(error.localizedDescription)")
            throw syncError
        }
    }

    /// Sync a single provider
    func syncProvider(_ provider: AIProvider) async throws {
        guard let apiKey = try? APIKeysStorage.shared.getAPIKey(for: .perplexity),
              !apiKey.isEmpty else {
            throw SyncError.noApiKey
        }

        syncProgress = .syncing(provider: provider.displayName, progress: 0)
        lastError = nil
        configService.setSyncing(true)

        defer {
            configService.setSyncing(false)
        }

        do {
            guard let currentCatalog = configService.activeCatalog else {
                throw SyncError.noCurrentCatalog
            }

            // Filter to just the requested provider
            let providerConfig = currentCatalog.providers.first { $0.id == provider.rawValue }
            guard let providerConfig = providerConfig else {
                throw SyncError.providerNotFound(provider.rawValue)
            }

            syncProgress = .syncing(provider: provider.displayName, progress: 0.2)

            // Create a mini-catalog with just this provider
            let miniCatalog = ModelCatalog(
                version: currentCatalog.version,
                lastUpdated: currentCatalog.lastUpdated,
                providers: [providerConfig]
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let currentJSON = try encoder.encode(miniCatalog)
            guard let currentJSONString = String(data: currentJSON, encoding: .utf8) else {
                throw SyncError.encodingError
            }

            syncProgress = .syncing(provider: provider.displayName, progress: 0.4)

            // Call Perplexity for just this provider
            let updatedMiniCatalog = try await callPerplexityAPI(
                apiKey: apiKey,
                currentCatalog: currentJSONString,
                singleProvider: provider.rawValue
            )

            syncProgress = .syncing(provider: provider.displayName, progress: 0.7)

            // Merge updated provider back into full catalog
            var updatedProviders = currentCatalog.providers.filter { $0.id != provider.rawValue }
            if let updatedProvider = updatedMiniCatalog.providers.first {
                updatedProviders.append(updatedProvider)
            }

            // Sort providers to maintain consistent order
            let providerOrder = ["anthropic", "openai", "gemini", "xai"]
            updatedProviders.sort { p1, p2 in
                let idx1 = providerOrder.firstIndex(of: p1.id) ?? Int.max
                let idx2 = providerOrder.firstIndex(of: p2.id) ?? Int.max
                return idx1 < idx2
            }

            let mergedCatalog = ModelCatalog(
                version: updatedMiniCatalog.version,
                lastUpdated: Date(),
                providers: updatedProviders
            )

            syncProgress = .syncing(provider: provider.displayName, progress: 0.9)

            // Save as draft
            try configService.saveDraft(mergedCatalog)
            configService.updateLastSyncDate()

            let modelCount = updatedMiniCatalog.providers.first?.models.count ?? 0
            syncProgress = .completed(modelCount: modelCount)
            logger.info("Sync for \(provider.rawValue) completed successfully")

        } catch {
            let syncError = (error as? SyncError) ?? .networkError(error.localizedDescription)
            lastError = syncError
            syncProgress = .failed(syncError)
            logger.error("Sync for \(provider.rawValue) failed: \(error.localizedDescription)")
            throw syncError
        }
    }

    // MARK: - Private API Call

    private func callPerplexityAPI(
        apiKey: String,
        currentCatalog: String,
        singleProvider: String? = nil
    ) async throws -> ModelCatalog {
        guard let url = URL(string: apiEndpoint) else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // Extended timeout for reasoning

        // Build user message
        var userMessage = "Here is my current provider/model JSON catalog. Please return an updated version with any new models, updated capabilities, and current pricing."
        if let provider = singleProvider {
            userMessage = "Return only the latest \(provider) models and pricing in the agreed JSON schema. Here is my current catalog for this provider:"
        }

        let requestBody: [String: Any] = [
            "model": perplexityModel,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
                ["role": "user", "content": currentCatalog]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Perplexity API error: \(httpResponse.statusCode) - \(errorBody)")
            throw SyncError.apiError(httpResponse.statusCode, errorBody)
        }

        // Parse the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SyncError.parseError("Could not extract content from response")
        }

        // Parse the catalog JSON from the content
        guard let catalogData = content.data(using: .utf8) else {
            throw SyncError.parseError("Could not convert content to data")
        }

        do {
            let catalog = try JSONDecoder().decode(ModelCatalog.self, from: catalogData)
            return catalog
        } catch {
            logger.error("Failed to parse catalog: \(error.localizedDescription)")
            logger.debug("Raw content: \(content)")
            throw SyncError.parseError("Invalid catalog JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - Reset

    func resetProgress() {
        syncProgress = .idle
        lastError = nil
    }
}

// MARK: - Types

enum SyncProgress: Equatable {
    case idle
    case syncing(provider: String?, progress: Double)
    case completed(modelCount: Int)
    case failed(SyncError)
}

enum SyncError: LocalizedError, Equatable {
    case noApiKey
    case noCurrentCatalog
    case providerNotFound(String)
    case encodingError
    case invalidURL
    case invalidResponse
    case apiError(Int, String)
    case parseError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Perplexity API key not configured. Please add your API key in Settings."
        case .noCurrentCatalog:
            return "No current model catalog available"
        case .providerNotFound(let id):
            return "Provider '\(id)' not found in catalog"
        case .encodingError:
            return "Failed to encode current catalog"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }

    static func == (lhs: SyncError, rhs: SyncError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
