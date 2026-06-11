import XCTest
@testable import Axon

final class SubconsciousMemoryLoggingTests: XCTestCase {

    func testAppSettingsRoundTripWithSubconsciousLogging() throws {
        var settings = AppSettings()
        settings.subconsciousMemoryLogging = SubconsciousMemoryLoggingSettings(
            enabled: true,
            builtInProvider: AIProvider.gemini.rawValue,
            customProviderId: nil,
            builtInModel: "gemini-2.5-pro",
            customModelId: nil,
            rollingContextPercent: 0.25,
            maxMemories: 14,
            confidenceThreshold: 0.42,
            minSalienceThreshold: 0.33,
            relevanceWeight: 0.5,
            confidenceWeight: 0.35,
            recencyWeight: 0.2,
            includeEpistemicBoundaries: true,
            showConfidence: false,
            maxToolRounds: 4
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.subconsciousMemoryLogging, settings.subconsciousMemoryLogging)
    }

    func testAppSettingsDecodeWhenSubconsciousFieldMissing() throws {
        var settings = AppSettings()
        settings.subconsciousMemoryLogging = SubconsciousMemoryLoggingSettings(
            enabled: true,
            builtInProvider: AIProvider.openai.rawValue,
            customProviderId: nil,
            builtInModel: "gpt-5.2",
            customModelId: nil,
            rollingContextPercent: 0.4,
            maxMemories: 12,
            confidenceThreshold: 0.6,
            minSalienceThreshold: 0.3,
            relevanceWeight: 0.5,
            confidenceWeight: 0.25,
            recencyWeight: 0.25,
            includeEpistemicBoundaries: false,
            showConfidence: true,
            maxToolRounds: 3
        )

        let encoded = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "subconsciousMemoryLogging")
        let legacyEncoded = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyEncoded)
        XCTAssertNil(decoded.subconsciousMemoryLogging)
        XCTAssertEqual(decoded.resolvedSubconsciousMemoryLogging, .default)
    }

    func testSyncableSettingsRoundTripForSubconsciousLogging() {
        var source = AppSettings()
        source.subconsciousMemoryLogging = SubconsciousMemoryLoggingSettings(
            enabled: true,
            builtInProvider: AIProvider.anthropic.rawValue,
            customProviderId: nil,
            builtInModel: "claude-sonnet-4-6",
            customModelId: nil,
            rollingContextPercent: 0.3,
            maxMemories: 9,
            confidenceThreshold: 0.35,
            minSalienceThreshold: 0.22,
            relevanceWeight: 0.45,
            confidenceWeight: 0.25,
            recencyWeight: 0.3,
            includeEpistemicBoundaries: true,
            showConfidence: false,
            maxToolRounds: 5
        )

        let syncable = SyncableSettings(from: source)
        var applied = AppSettings()
        syncable.apply(to: &applied)

        XCTAssertEqual(applied.subconsciousMemoryLogging, source.subconsciousMemoryLogging)
    }

    func testRollingContextBudgetMathAndClamping() {
        XCTAssertEqual(MemoryService.clampedRollingTokenBudget(percent: 0.25, contextWindow: 4_000), 1_000)
        XCTAssertEqual(MemoryService.clampedRollingTokenBudget(percent: 0.25, contextWindow: 1_000_000), 250_000)
        XCTAssertEqual(MemoryService.clampedRollingTokenBudget(percent: 2.0, contextWindow: 8_000), 8_000)
        XCTAssertEqual(MemoryService.clampedRollingTokenBudget(percent: 0.0, contextWindow: 8_000), 256)
    }

    func testThreadOverrideIgnoreFlagPersistence() {
        let manager = ConversationOverridesManager.shared
        let conversationId = "subconscious-ignore-\(UUID().uuidString)"

        defer {
            manager.deleteOverrides(for: conversationId)
        }

        XCTAssertFalse(manager.isSubconsciousLoggingDisabled(for: conversationId))
        manager.setSubconsciousLoggingDisabled(true, for: conversationId)
        XCTAssertTrue(manager.isSubconsciousLoggingDisabled(for: conversationId))

        manager.setSubconsciousLoggingDisabled(false, for: conversationId)
        XCTAssertFalse(manager.isSubconsciousLoggingDisabled(for: conversationId))
    }

    func testOnlyCreateMemoryToolRequestsAreAllowed() {
        let requests = [
            ToolRequest(tool: ToolId.createMemory.rawValue, query: "{\"memory\":\"remember this\"}"),
            ToolRequest(tool: ToolId.codeExecution.rawValue, query: "print('unsafe')")
        ]

        let filtered = MemoryService.filterSubconsciousToolRequests(requests)
        XCTAssertEqual(filtered.allowed.count, 1)
        XCTAssertEqual(filtered.allowed.first?.tool, ToolId.createMemory.rawValue)
        XCTAssertEqual(filtered.ignored.count, 1)
        XCTAssertEqual(filtered.ignored.first?.tool, ToolId.codeExecution.rawValue)
    }

    // MARK: - Runtime Resolution

    @MainActor
    func testResolverAppleFoundationProducesOnDeviceBackend() throws {
        let settings = AppSettings()
        var selection = SubconsciousMemoryLoggingSettings.default
        selection.enabled = true
        selection.builtInProvider = AIProvider.appleFoundation.rawValue

        let result = MemoryService.shared.resolveSubconsciousRuntimeConfig(selection: selection, settings: settings)

        let runtime = try result.get()
        XCTAssertEqual(runtime.backend, .appleFoundation)
        // AFM context is clamped to leave headroom for prompts and tool-feedback rounds.
        XCTAssertLessThanOrEqual(runtime.contextWindow, 3_000)
        XCTAssertGreaterThanOrEqual(runtime.contextWindow, 1_024)
    }

    /// Regression test for the always-on "Apple Intelligence is not currently supported"
    /// banner: with no explicit subconscious provider selection, the resolver falls back
    /// to the default provider (Apple Foundation) and must now resolve successfully
    /// instead of returning the hard-block failure.
    @MainActor
    func testResolverDefaultProviderFallbackAppleFoundationSucceeds() throws {
        var settings = AppSettings()
        settings.defaultProvider = .appleFoundation
        var selection = SubconsciousMemoryLoggingSettings.default
        selection.enabled = true
        selection.builtInProvider = nil

        let result = MemoryService.shared.resolveSubconsciousRuntimeConfig(selection: selection, settings: settings)

        let runtime = try result.get()
        XCTAssertEqual(runtime.backend, .appleFoundation)
    }

    @MainActor
    func testResolverLocalMLX() {
        let settings = AppSettings()
        var selection = SubconsciousMemoryLoggingSettings.default
        selection.enabled = true
        selection.builtInProvider = AIProvider.localMLX.rawValue

        let result = MemoryService.shared.resolveSubconsciousRuntimeConfig(selection: selection, settings: settings)

        #if targetEnvironment(simulator)
        guard case .failure(let error) = result else {
            return XCTFail("Expected simulator failure for local MLX")
        }
        XCTAssertTrue(error.message.contains("physical device"))
        #else
        switch result {
        case .success(let runtime):
            guard case .localMLX(let modelId) = runtime.backend else {
                return XCTFail("Expected localMLX backend, got \(runtime.backend)")
            }
            XCTAssertEqual(modelId, runtime.model)
        case .failure(let error):
            // Acceptable only when no MLX models are configured in this environment.
            XCTAssertTrue(error.message.contains("no models"), "Unexpected failure: \(error.message)")
        }
        #endif
    }

    /// Cloud providers must never hit the old on-device hard block; they either resolve
    /// to an HTTP backend or fail solely because an API key is missing.
    @MainActor
    func testResolverCloudProviderResolvesToHTTPOrMissingKey() {
        let settings = AppSettings()
        var selection = SubconsciousMemoryLoggingSettings.default
        selection.enabled = true
        selection.builtInProvider = AIProvider.anthropic.rawValue

        let result = MemoryService.shared.resolveSubconsciousRuntimeConfig(selection: selection, settings: settings)

        switch result {
        case .success(let runtime):
            guard case .http(let provider, let apiKey, _) = runtime.backend else {
                return XCTFail("Expected http backend, got \(runtime.backend)")
            }
            XCTAssertEqual(provider, "anthropic")
            XCTAssertFalse(apiKey.isEmpty)
        case .failure(let error):
            XCTAssertTrue(error.message.contains("missing API key"), "Unexpected failure: \(error.message)")
            XCTAssertFalse(error.message.contains("not currently supported"))
        }
    }
}
