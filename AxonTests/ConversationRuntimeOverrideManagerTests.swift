import XCTest
@testable import Axon

@MainActor
final class ConversationRuntimeOverrideManagerTests: XCTestCase {
    private let manager = ConversationRuntimeOverrideManager.shared
    private var conversationId: String!

    override func setUp() {
        super.setUp()
        conversationId = "test-runtime-overrides-\(UUID().uuidString)"
        manager.clearConversationRuntimeOverrides(conversationId: conversationId)
        manager.clearTurnLease(conversationId: conversationId)
    }

    override func tearDown() {
        manager.clearConversationRuntimeOverrides(conversationId: conversationId)
        manager.clearTurnLease(conversationId: conversationId)
        conversationId = nil
        super.tearDown()
    }

    func testPrecedenceTurnLeaseOverConversationAndGlobal() {
        var baseParams = ModelGenerationSettings()
        baseParams.temperatureEnabled = true
        baseParams.temperature = 0.7
        baseParams.topPEnabled = true
        baseParams.topP = 0.95

        manager.setConversationRuntimeOverrides(
            conversationId: conversationId,
            provider: nil,
            model: nil,
            samplingOverride: ConversationSamplingOverride(
                temperature: 0.2,
                topP: nil,
                topK: nil
            )
        )

        let leaseModel = UnifiedModelRegistry.shared.chatModels(for: .anthropic).first?.id
            ?? AIProvider.anthropic.availableModels.first?.id
            ?? "claude-sonnet-4-6"

        manager.setTurnLease(
            conversationId: conversationId,
            turns: 2,
            provider: AIProvider.anthropic.rawValue,
            model: leaseModel,
            samplingOverride: ConversationSamplingOverride(
                temperature: nil,
                topP: 0.4,
                topK: nil
            )
        )

        let resolved = manager.resolve(
            conversationId: conversationId,
            baseProvider: AIProvider.openai.rawValue,
            baseModel: "gpt-5.2",
            baseProviderDisplayName: AIProvider.openai.displayName,
            baseModelParams: baseParams
        )

        XCTAssertEqual(resolved.provider, AIProvider.anthropic.rawValue)
        XCTAssertEqual(resolved.model, leaseModel)
        XCTAssertEqual(resolved.modelParams.temperature, 0.2, accuracy: 0.0001)
        XCTAssertEqual(resolved.modelParams.topP, 0.4, accuracy: 0.0001)
        XCTAssertEqual(resolved.activeTurnLease?.remainingTurns, 2)
    }

    func testLeaseDoesNotDecrementUntilConsumed() {
        manager.setTurnLease(
            conversationId: conversationId,
            turns: 2,
            provider: AIProvider.openai.rawValue,
            model: nil,
            samplingOverride: nil
        )

        _ = manager.resolve(
            conversationId: conversationId,
            baseProvider: AIProvider.openai.rawValue,
            baseModel: "gpt-5.2",
            baseProviderDisplayName: AIProvider.openai.displayName,
            baseModelParams: ModelGenerationSettings()
        )

        XCTAssertEqual(manager.loadTurnLease(conversationId: conversationId)?.remainingTurns, 2)

        manager.consumeTurnLeaseOnSuccessfulReply(conversationId: conversationId)
        XCTAssertEqual(manager.loadTurnLease(conversationId: conversationId)?.remainingTurns, 1)
    }

    func testLeaseClearsAtZero() {
        manager.setTurnLease(
            conversationId: conversationId,
            turns: 1,
            provider: AIProvider.openai.rawValue,
            model: nil,
            samplingOverride: nil
        )

        manager.consumeTurnLeaseOnSuccessfulReply(conversationId: conversationId)
        XCTAssertNil(manager.loadTurnLease(conversationId: conversationId))
    }
}
