import XCTest
import AxonProviderKitCore
@testable import Axon

private typealias AxonProvider = Axon.AIProvider
private typealias AxonLocalMLXModel = Axon.LocalMLXModel

@MainActor
final class AgentStateConfigureRuntimeHandlerTests: XCTestCase {
    private let handler = AgentStateHandler()
    private let runtimeManager = ConversationRuntimeOverrideManager.shared
    private var originalSettings: AppSettings!

    override func setUp() {
        super.setUp()
        originalSettings = SettingsViewModel.shared.settings
        var updated = originalSettings!
        updated.sovereigntySettings.agentSelfReconfigApprovalMode = .noApproval
        SettingsViewModel.shared.settings = updated
        AgentRuntimeCatalog.resetTestingOverrides()
    }

    override func tearDown() {
        AgentRuntimeCatalog.resetTestingOverrides()
        SettingsViewModel.shared.settings = originalSettings
        super.tearDown()
    }

    func testTurnScopeWithoutTurnsFails() async throws {
        let conversationId = makeConversationId()
        defer { cleanup(conversationId) }

        let result = try await handler.executeV2(
            inputs: [
                "action": "set",
                "scope": "turn",
                "sampling": ["temperature": 0.3]
            ],
            manifest: try manifest(),
            context: makeContext(conversationId: conversationId)
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("'turns' is required"))
    }

    func testInvalidProviderModelPairingFails() async throws {
        let conversationId = makeConversationId()
        defer { cleanup(conversationId) }

        let result = try await handler.executeV2(
            inputs: [
                "action": "set",
                "scope": "conversation",
                "provider": "openai",
                "model": "claude-sonnet-4-6"
            ],
            manifest: try manifest(),
            context: makeContext(conversationId: conversationId)
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("not available for"))
    }

    func testUnsupportedSamplingParameterFailsWithExplicitReason() async throws {
        let conversationId = makeConversationId()
        defer { cleanup(conversationId) }

        let result = try await handler.executeV2(
            inputs: [
                "action": "set",
                "scope": "conversation",
                "sampling": ["top_k": 40]
            ],
            manifest: try manifest(),
            context: makeContext(conversationId: conversationId, runtimeProvider: "openai", runtimeModel: "gpt-5.2")
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("top_k is not supported"))
    }

    func testClearOnlyRemovesTargetedScopeState() async throws {
        let conversationId = makeConversationId()
        defer { cleanup(conversationId) }

        runtimeManager.setConversationRuntimeOverrides(
            conversationId: conversationId,
            provider: nil,
            model: nil,
            samplingOverride: ConversationSamplingOverride(
                temperature: 0.4,
                topP: nil,
                topK: nil
            )
        )
        runtimeManager.setTurnLease(
            conversationId: conversationId,
            turns: 2,
            provider: AxonProvider.anthropic.rawValue,
            model: "claude-sonnet-4-6",
            samplingOverride: nil
        )

        let result = try await handler.executeV2(
            inputs: [
                "action": "clear",
                "scope": "conversation"
            ],
            manifest: try manifest(),
            context: makeContext(conversationId: conversationId)
        )

        XCTAssertTrue(result.success)
        XCTAssertNil(runtimeManager.loadConversationOverrides(conversationId: conversationId)?.samplingOverride)
        XCTAssertNotNil(runtimeManager.loadTurnLease(conversationId: conversationId))
    }

    func testConfigureRuntimeSucceedsWithConversationContext() async throws {
        let conversationId = makeConversationId()
        defer { cleanup(conversationId) }

        let result = try await handler.executeV2(
            inputs: [
                "action": "set",
                "scope": "conversation",
                "sampling": ["temperature": 0.2, "top_p": 0.9]
            ],
            manifest: try manifest(),
            context: makeContext(conversationId: conversationId)
        )

        XCTAssertTrue(result.success)
        let storedSampling = runtimeManager.loadConversationOverrides(conversationId: conversationId)?.samplingOverride
        XCTAssertNotNil(storedSampling)
        XCTAssertEqual(storedSampling?.temperature ?? 0.0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(storedSampling?.topP ?? 0.0, 0.9, accuracy: 0.0001)
    }

    func testConfigureRuntimeFailsWithoutConversationContext() async throws {
        let result = try await handler.executeV2(
            inputs: [
                "action": "set",
                "scope": "conversation",
                "sampling": ["temperature": 0.2]
            ],
            manifest: try manifest(),
            context: ToolContextV2(
                conversationId: nil,
                runtimeProvider: "openai",
                runtimeModel: "gpt-5.2"
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("Conversation context is required"))
    }

    func testCloudProviderModelChangeFailsWhenAPIKeyIsMissing() async throws {
        let conversationId = makeConversationId()
        defer { cleanup(conversationId) }

        let modelId = try XCTUnwrap(ProviderKitModelCatalogAdapter.models(for: .openai).first?.id)
        AgentRuntimeCatalog.apiKeyConfiguredOverride = { _ in false }

        let result = try await handler.executeV2(
            inputs: [
                "action": "set",
                "scope": "conversation",
                "provider": "openai",
                "model": modelId
            ],
            manifest: try manifest(),
            context: makeContext(conversationId: conversationId, runtimeProvider: "anthropic", runtimeModel: "claude-sonnet-4-6")
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("Missing API key for OpenAI"))
    }

    func testCloudProviderModelChangeSucceedsWhenAPIKeyIsConfigured() async throws {
        let conversationId = makeConversationId()
        defer { cleanup(conversationId) }

        let modelId = try XCTUnwrap(ProviderKitModelCatalogAdapter.models(for: .openai).first?.id)
        AgentRuntimeCatalog.apiKeyConfiguredOverride = { _ in true }

        let result = try await handler.executeV2(
            inputs: [
                "action": "set",
                "scope": "conversation",
                "provider": "openai",
                "model": modelId
            ],
            manifest: try manifest(),
            context: makeContext(conversationId: conversationId, runtimeProvider: "anthropic", runtimeModel: "claude-sonnet-4-6")
        )

        XCTAssertTrue(result.success)
        let overrides = runtimeManager.loadConversationOverrides(conversationId: conversationId)
        XCTAssertEqual(overrides?.builtInProvider, AxonProvider.openai.rawValue)
        XCTAssertEqual(overrides?.builtInModel, modelId)
    }

    func testAppleFoundationProviderModelChangeSucceedsWhenDeviceAvailable() async throws {
        let conversationId = makeConversationId()
        defer { cleanup(conversationId) }

        let modelId = try XCTUnwrap(ProviderKitModelCatalogAdapter.models(for: .appleFoundation).first?.id)
        AgentRuntimeCatalog.apiKeyConfiguredOverride = { _ in true }
        AgentRuntimeCatalog.providerAvailabilityOverride = { provider in
            provider == .appleFoundation ? true : provider.isAvailable
        }

        let result = try await handler.executeV2(
            inputs: [
                "action": "set",
                "scope": "conversation",
                "provider": "appleFoundation",
                "model": modelId
            ],
            manifest: try manifest(),
            context: makeContext(conversationId: conversationId, runtimeProvider: "openai", runtimeModel: "gpt-5.2")
        )

        XCTAssertTrue(result.success)
        let overrides = runtimeManager.loadConversationOverrides(conversationId: conversationId)
        XCTAssertEqual(overrides?.builtInProvider, AxonProvider.appleFoundation.rawValue)
        XCTAssertEqual(overrides?.builtInModel, modelId)
    }

    func testLocalMLXCatalogOnlyModelIsListedButRejectedForExecution() async throws {
        applyTestMLXConfig()
        let conversationId = makeConversationId()
        defer { cleanup(conversationId) }

        let catalogOnlyModelId = AxonLocalMLXModel.smolLM.rawValue
        AgentRuntimeCatalog.providerAvailabilityOverride = { provider in
            provider == .localMLX ? true : provider.isAvailable
        }
        AgentRuntimeCatalog.mlxModelDownloadedOverride = { _ in false }

        let catalog = AgentRuntimeCatalog.snapshot(settings: SettingsViewModel.shared.settings)
        let mlxProvider = try XCTUnwrap(catalog.provider(id: AxonProvider.localMLX.rawValue))
        let catalogOnlyModel = try XCTUnwrap(mlxProvider.model(id: catalogOnlyModelId))
        XCTAssertTrue(catalogOnlyModel.modelExists)
        XCTAssertFalse(catalogOnlyModel.usableNow)
        XCTAssertTrue(catalogOnlyModel.unavailableReason?.contains("not bundled or downloaded") == true)

        let result = try await handler.executeV2(
            inputs: [
                "action": "set",
                "scope": "conversation",
                "provider": "localMLX",
                "model": catalogOnlyModelId
            ],
            manifest: try manifest(),
            context: makeContext(conversationId: conversationId, runtimeProvider: "openai", runtimeModel: "gpt-5.2")
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("not bundled or downloaded"))
    }

    private func manifest() throws -> ToolManifest {
        let json = """
        {
          "version": "1.0.0",
          "tool": {
            "id": "agent_state_configure_runtime",
            "name": "Configure Agent Runtime",
            "description": "Configure runtime overrides.",
            "category": "agent_state",
            "requiresApproval": false
          },
          "execution": {
            "type": "internal_handler",
            "handler": "agent_state"
          }
        }
        """
        return try JSONDecoder().decode(ToolManifest.self, from: Data(json.utf8))
    }

    private func makeContext(
        conversationId: String,
        runtimeProvider: String = "openai",
        runtimeModel: String = "gpt-5.2"
    ) -> ToolContextV2 {
        ToolContextV2(
            conversationId: conversationId,
            runtimeProvider: runtimeProvider,
            runtimeModel: runtimeModel
        )
    }

    private func makeConversationId() -> String {
        "test-agent-state-runtime-\(UUID().uuidString)"
    }

    private func cleanup(_ conversationId: String) {
        runtimeManager.clearConversationRuntimeOverrides(conversationId: conversationId)
        runtimeManager.clearTurnLease(conversationId: conversationId)
    }

    private func applyTestMLXConfig() {
        let config = AxonProviderKitCore.MLXModelConfig(
            version: 1,
            defaultModelId: AxonLocalMLXModel.defaultModel.rawValue,
            models: [
                .init(
                    id: AxonLocalMLXModel.defaultModel.rawValue,
                    displayName: AxonLocalMLXModel.defaultModel.displayName,
                    summary: "Bundled test model",
                    contextWindow: AxonLocalMLXModel.defaultModel.contextWindow,
                    modalities: AxonLocalMLXModel.defaultModel.modalities,
                    bundled: true,
                    localPath: "MLXModels/google_gemma-4-E2B-it-MLX"
                ),
                .init(
                    id: AxonLocalMLXModel.smolLM.rawValue,
                    displayName: AxonLocalMLXModel.smolLM.displayName,
                    summary: "Downloadable test model",
                    contextWindow: AxonLocalMLXModel.smolLM.contextWindow,
                    modalities: AxonLocalMLXModel.smolLM.modalities,
                    bundled: false,
                    localPath: nil
                )
            ],
            excludeDefaults: []
        )

        MLXModelConfigLoader.shared.apply(config)
        MLXModelRegistry.shared.updateModels([])
        ProviderKitModelCatalogAdapter.bootstrapMLXCatalog()
    }
}

final class ToolInputNormalizationV2Tests: XCTestCase {
    func testParseCSVStringNormalizesAndDedupes() {
        let parsed = ToolInputNormalizationV2.parseNormalizedStringArray(" Preferences, #Workflow ,preferences ")
        XCTAssertEqual(parsed, ["preferences", "workflow"])
    }

    func testParseJSONArrayString() {
        let parsed = ToolInputNormalizationV2.parseNormalizedStringArray("[\"Auth\", \"#Security\", \"auth\"]")
        XCTAssertEqual(parsed, ["auth", "security"])
    }

    func testParseRawAnyArrayWithMixedTypes() {
        let parsed = ToolInputNormalizationV2.parseNormalizedStringArray(["#iOS", "Swift", 42, "swift"])
        XCTAssertEqual(parsed, ["ios", "swift", "42"])
    }

    func testParseDropsEmptyValues() {
        let parsed = ToolInputNormalizationV2.parseNormalizedStringArray(" , ,# , project ,, ")
        XCTAssertEqual(parsed, ["project"])
    }

    func testAgentStateTagsInputStyleParses() {
        let parsed = ToolInputNormalizationV2.parseNormalizedStringArray("preferences, #workflow, preferences")
        XCTAssertEqual(parsed, ["preferences", "workflow"])
    }

    func testSubAgentContextTagsInputStyleParses() {
        let parsed = ToolInputNormalizationV2.parseNormalizedStringArray("[\"Auth\", \"Security\", \"auth\"]")
        XCTAssertEqual(parsed, ["auth", "security"])
    }

    func testHeartbeatModulesInputStyleParses() {
        let parsed = ToolInputNormalizationV2.parseNormalizedStringArray(["Calendar", " weather ", "calendar"])
        XCTAssertEqual(parsed, ["calendar", "weather"])
    }

    func testTemporalTagDetectionRecognizesYears() {
        XCTAssertTrue(ToolInputNormalizationV2.isTemporalLikeTag("today"))
        XCTAssertTrue(ToolInputNormalizationV2.isTemporalLikeTag("2026"))
        XCTAssertFalse(ToolInputNormalizationV2.isTemporalLikeTag("swift"))
    }

    func testGeneratedTemporalStorageTagDetectionPreservesWeekdays() {
        XCTAssertTrue(ToolInputNormalizationV2.isGeneratedTemporalStorageTag("today"))
        XCTAssertTrue(ToolInputNormalizationV2.isGeneratedTemporalStorageTag("2026"))
        XCTAssertTrue(ToolInputNormalizationV2.isGeneratedTemporalStorageTag("spring"))
        XCTAssertFalse(ToolInputNormalizationV2.isGeneratedTemporalStorageTag("monday"))
        XCTAssertFalse(ToolInputNormalizationV2.isGeneratedTemporalStorageTag("swift"))
    }

    func testGenerateSemanticTagsExcludesTemporalNoiseAndStopwords() {
        let content = "Today we should really discuss swift concurrency and payment retry logic in checkout."
        let tags = ToolInputNormalizationV2.generateSemanticTags(from: content, maxCount: 4)
        XCTAssertLessThanOrEqual(tags.count, 4)
        XCTAssertFalse(tags.contains("today"))
        XCTAssertFalse(tags.contains("should"))
    }
}

@MainActor
final class AgentStateConfigureRuntimeDiscoveryTests: XCTestCase {
    private let handler = DiscoveryHandler()

    override func setUp() {
        super.setUp()
        AgentRuntimeCatalog.resetTestingOverrides()
    }

    override func tearDown() {
        AgentRuntimeCatalog.resetTestingOverrides()
        super.tearDown()
    }

    func testGetToolDetailsIncludesCallGrammarAndRuntimeCatalogPointer() async throws {
        AgentRuntimeCatalog.apiKeyConfiguredOverride = { provider in
            provider == .openai
        }

        await ToolPluginLoader.shared.loadAllTools()

        let result = try await handler.executeV2(
            inputs: ["query": "agent_state_configure_runtime"],
            manifest: try manifest(),
            context: .empty
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("## Parameters"))
        XCTAssertTrue(result.output.contains("`set`"))
        XCTAssertTrue(result.output.contains("`clear`"))
        XCTAssertTrue(result.output.contains("`conversation`"))
        XCTAssertTrue(result.output.contains("`turn`"))
        XCTAssertTrue(result.output.contains("default: `set`"))
        XCTAssertTrue(result.output.contains("default: `conversation`"))
        XCTAssertTrue(result.output.contains("range: 1-100"))
        XCTAssertTrue(result.output.contains("`temperature` (number)"))
        XCTAssertTrue(result.output.contains("`top_p` (number)"))
        XCTAssertTrue(result.output.contains("`top_k` (integer)"))
        XCTAssertTrue(result.output.contains("## Examples"))
        XCTAssertTrue(result.output.contains("Set a 2-turn lease on provider/model"))
        XCTAssertTrue(result.output.contains("## When to use"))
        XCTAssertTrue(result.output.contains("Temporarily switch model"))
        XCTAssertTrue(result.output.contains("## System prompt guidance"))
        XCTAssertTrue(result.output.contains("Call `get_runtime_catalog`"))
        XCTAssertFalse(result.output.contains("## Runtime Options"))
        XCTAssertTrue(result.output.contains("agent_state_configure_runtime"))
        XCTAssertTrue(result.output.contains("Call `get_runtime_catalog` to inspect current provider/model availability"))

        XCTAssertNil(result.structuredOutput?["runtimeOptions"])
        XCTAssertEqual(result.structuredOutput?["runtimeCatalogTool"] as? String, "get_runtime_catalog")
    }

    func testGetRuntimeCatalogStructuredOutputIncludesStatusFieldsAndUnavailableReasons() async throws {
        AgentRuntimeCatalog.apiKeyConfiguredOverride = { _ in false }

        let result = try await handler.executeV2(
            inputs: [:],
            manifest: try manifest(id: "get_runtime_catalog"),
            context: .empty
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("# Runtime Catalog"))
        XCTAssertTrue(result.output.contains("usableNow"))

        let runtimeOptions = try XCTUnwrap(result.structuredOutput?["runtimeOptions"] as? [String: Any])
        let providers = try XCTUnwrap(runtimeOptions["providers"] as? [[String: Any]])
        let openAI = try XCTUnwrap(providers.first { ($0["id"] as? String) == AxonProvider.openai.rawValue })
        let models = try XCTUnwrap(openAI["models"] as? [[String: Any]])
        let firstModel: [String: Any] = try XCTUnwrap(models.first)

        XCTAssertEqual(openAI["configuredKey"] as? Bool, false)
        XCTAssertEqual(openAI["deviceAvailable"] as? Bool, true)
        XCTAssertEqual(openAI["modelExists"] as? Bool, true)
        XCTAssertEqual(openAI["usableNow"] as? Bool, false)
        XCTAssertTrue((openAI["unavailableReason"] as? String)?.contains("Missing API key") == true)
        XCTAssertNotNil(firstModel["id"] as? String)
        XCTAssertNotNil(firstModel["configuredKey"] as? Bool)
        XCTAssertNotNil(firstModel["deviceAvailable"] as? Bool)
        XCTAssertNotNil(firstModel["modelExists"] as? Bool)
        XCTAssertNotNil(firstModel["usableNow"] as? Bool)
        XCTAssertTrue((firstModel["unavailableReason"] as? String)?.contains("Missing API key") == true)
    }

    func testGetRuntimeCatalogRespectsProviderUsableOnlyAndIncludeModels() async throws {
        AgentRuntimeCatalog.apiKeyConfiguredOverride = { provider in
            provider == .openai
        }
        AgentRuntimeCatalog.providerAvailabilityOverride = { provider in
            provider == .openai
        }

        let result = try await handler.executeV2(
            inputs: [
                "query": "{\"provider\":\"\(AxonProvider.openai.rawValue)\",\"usable_only\":true,\"include_models\":false}"
            ],
            manifest: try manifest(id: "get_runtime_catalog"),
            context: .empty
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("provider filter: `\(AxonProvider.openai.rawValue)`"))
        XCTAssertFalse(result.output.contains("- models:"))

        let runtimeOptions = try XCTUnwrap(result.structuredOutput?["runtimeOptions"] as? [String: Any])
        XCTAssertEqual(runtimeOptions["usableOnly"] as? Bool, true)
        XCTAssertEqual(runtimeOptions["includeModels"] as? Bool, false)
        let providers = try XCTUnwrap(runtimeOptions["providers"] as? [[String: Any]])
        XCTAssertEqual(providers.count, 1)
        XCTAssertTrue(providers.contains { ($0["id"] as? String) == AxonProvider.openai.rawValue })
        XCTAssertNil(providers.first?["models"])
    }

    func testGetRuntimeCatalogFailsForUnknownProvider() async throws {
        let result = try await handler.executeV2(
            inputs: ["query": "not_a_provider"],
            manifest: try manifest(id: "get_runtime_catalog"),
            context: .empty
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("Unknown provider 'not_a_provider'"))
        XCTAssertTrue(result.output.contains("Valid providers:"))
    }

    private func manifest(id: String = "get_tool_details") throws -> ToolManifest {
        let json = """
        {
          "version": "1.0.0",
          "tool": {
            "id": "\(id)",
            "name": "Discovery Test Tool",
            "description": "Discovery test tool.",
            "category": "discovery",
            "requiresApproval": false
          },
          "execution": {
            "type": "internal_handler",
            "handler": "discovery"
          }
        }
        """
        return try JSONDecoder().decode(ToolManifest.self, from: Data(json.utf8))
    }
}

@MainActor
final class MemoryHandlerTagCompositionTests: XCTestCase {
    private let handler = MemoryHandler()

    func testExplicitNonTemporalTagsArePreservedWithoutSemanticAugment() {
        let tags = handler.composeCreateMemoryTags(
            content: "This content mentions database migration and telemetry.",
            rawTags: " #Swift , ios , swift "
        )

        XCTAssertEqual(tags, ["swift", "ios"])
    }

    func testEmptyTagsGenerateSemanticTags() {
        let tags = handler.composeCreateMemoryTags(
            content: "Refactor checkout retry logic and improve telemetry dashboards for payment failures.",
            rawTags: ""
        )

        XCTAssertFalse(tags.isEmpty)
        XCTAssertLessThanOrEqual(tags.count, 4)
        XCTAssertTrue(tags.allSatisfy { !ToolInputNormalizationV2.isTemporalLikeTag($0) })
    }

    func testTemporalOnlyTagsGenerateSemanticTagsAndDropGeneratedTemporalTags() {
        let tags = handler.composeCreateMemoryTags(
            content: "Investigated race conditions in swift concurrency task cancellation for sync engine.",
            rawTags: "today, this_week, 2026"
        )

        XCTAssertFalse(tags.contains("today"))
        XCTAssertFalse(tags.contains("this_week"))
        XCTAssertFalse(tags.contains("2026"))
        XCTAssertTrue(tags.contains { !ToolInputNormalizationV2.isTemporalLikeTag($0) })
    }

    func testWeekdayTagsArePreservedAsPatternTags() {
        let tags = handler.composeCreateMemoryTags(
            content: "Monday planning has a recurring architecture review cadence.",
            rawTags: "today, Monday, 2026"
        )

        XCTAssertEqual(tags, ["monday"])
    }

    func testMemoryStorageCleanupDropsGeneratedTemporalTagsAndKeepsWeekdays() {
        let tags = Memory.storedSemanticTags(from: ["Swift", "today", "spring", "2026", "Monday", "swift"])

        XCTAssertEqual(tags, ["swift", "monday"])
    }

    func testTemporalCleanupMetadataBacksUpOriginalTags() {
        let memory = Memory(
            userId: "test",
            content: "Test memory",
            type: .egoic,
            confidence: 0.8,
            tags: ["swift", "today", "monday"]
        )

        let metadata = memory.metadataBackingUpTemporalCleanup()

        XCTAssertEqual(metadata[Memory.temporalTagCleanupVersionKey]?.stringValue, Memory.temporalTagCleanupVersion)
        XCTAssertEqual(
            metadata[Memory.temporalTagCleanupOriginalTagsKey]?.arrayValue?.compactMap(\.stringValue),
            ["swift", "today", "monday"]
        )
    }
}

@MainActor
final class HeuristicInjectionTests: XCTestCase {
    func testBuildInjectionContextUsesCognitiveHeuristicsBlock() {
        let service = HeuristicsService.shared
        let block = service.buildInjectionContext(heuristics: [
            Heuristic(
                type: .frequency,
                dimension: .narrative,
                content: "I keep returning to Swift concurrency and cancellation semantics.",
                sourceTagSample: ["swift", "concurrency"],
                confidence: 0.95
            )
        ])

        XCTAssertTrue(block.contains("## Cognitive Heuristics"))
        XCTAssertTrue(block.contains("Frequency"))
        XCTAssertTrue(block.contains("Swift concurrency"))
        XCTAssertTrue(block.contains("swift, concurrency"))
    }
}
