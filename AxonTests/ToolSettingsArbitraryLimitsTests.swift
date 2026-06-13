import XCTest
@testable import Axon

final class ToolSettingsArbitraryLimitsTests: XCTestCase {

    func testLargeToolLimitValuesPersistWithoutUpperCap() throws {
        var settings = ToolSettings()
        settings.maxToolCallsPerTurn = 250
        settings.toolTimeout = 3_600

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ToolSettings.self, from: data)

        XCTAssertEqual(decoded.maxToolCallsPerTurn, 250)
        XCTAssertEqual(decoded.toolTimeout, 3_600)
    }

    func testEffectiveValuesOnlyApplyLowerBound() {
        var settings = ToolSettings()

        settings.maxToolCallsPerTurn = 0
        settings.toolTimeout = -30
        XCTAssertEqual(settings.effectiveMaxToolCallsPerTurn, 1)
        XCTAssertEqual(settings.effectiveToolTimeoutSeconds, 1)

        settings.maxToolCallsPerTurn = 250
        settings.toolTimeout = 3_600
        XCTAssertEqual(settings.effectiveMaxToolCallsPerTurn, 250)
        XCTAssertEqual(settings.effectiveToolTimeoutSeconds, 3_600)
    }

    @MainActor
    func testToolPromptIncludesLargeMaxToolCallValue() {
        let prompt = ToolProxyService.shared.generateMinimalToolSystemPrompt(
            enabledTools: [.googleSearch],
            maxToolCalls: 250
        )

        XCTAssertTrue(prompt.contains("up to 250 tool calls"))
    }

    @MainActor
    func testToolPromptCoercesInvalidMaxToolCallValue() {
        let prompt = ToolProxyService.shared.generateMinimalToolSystemPrompt(
            enabledTools: [.googleSearch],
            maxToolCalls: 0
        )

        XCTAssertTrue(prompt.contains("up to 1 tool call"))
    }

    func testPipelineContextStoresArbitraryTimeout() {
        let context = PipelineExecutionContext(requestTimeoutSeconds: 3_600)

        XCTAssertEqual(context.requestTimeoutSeconds, 3_600)
    }
}
