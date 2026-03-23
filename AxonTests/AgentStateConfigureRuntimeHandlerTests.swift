import XCTest
@testable import Axon

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
    }

    override func tearDown() {
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
            provider: AIProvider.anthropic.rawValue,
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
}
