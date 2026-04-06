import XCTest
@testable import Axon

@MainActor
final class SlashCommandToolTestTests: XCTestCase {

    func testParseToolTestDefaultSuite() {
        let command = SlashCommandParser.shared.parse("/tooltest")
        guard case .toolTest(let suite) = command else {
            return XCTFail("Expected .toolTest command")
        }
        XCTAssertNil(suite)
    }

    func testParseToolTestListSuite() {
        let command = SlashCommandParser.shared.parse("/tooltest list")
        guard case .toolTest(let suite) = command else {
            return XCTFail("Expected .toolTest command")
        }
        XCTAssertEqual(suite, "list")
    }

    func testParseToolTestNamedSuite() {
        let command = SlashCommandParser.shared.parse("/tooltest core_v2_safe")
        guard case .toolTest(let suite) = command else {
            return XCTFail("Expected .toolTest command")
        }
        XCTAssertEqual(suite, "core_v2_safe")
    }

    func testParseToolTestExtendedSuite() {
        let command = SlashCommandParser.shared.parse("/tooltest core_v2_extended")
        guard case .toolTest(let suite) = command else {
            return XCTFail("Expected .toolTest command")
        }
        XCTAssertEqual(suite, "core_v2_extended")
    }

    func testExecuteToolTestListReturnsSuiteCatalog() async {
        let result = await SlashCommandParser.shared.execute(.toolTest(suite: "list"))

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.displayText, "/tooltest list")
        XCTAssertTrue(result.resultText.contains("core_v2_safe"))
        XCTAssertTrue(result.resultText.contains("core_v2_extended"))
        XCTAssertTrue(result.resultText.contains("core_v2_discovery_hardening"))
        XCTAssertTrue(result.resultText.contains("core_v2_state_readonly"))
        XCTAssertTrue(result.resultText.contains("core_v2_agent_state_roundtrip"))
        XCTAssertTrue(result.resultText.contains("core_v2_approval_paths"))
        XCTAssertTrue(result.resultText.contains("core_v2_gemini_capabilities"))
    }

    func testExecuteToolTestUnknownSuiteFailsWithGuidance() async {
        let result = await SlashCommandParser.shared.execute(.toolTest(suite: "does_not_exist"))

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.resultText.contains("Unknown tool test suite"))
        XCTAssertTrue(result.resultText.contains("core_v2_safe"))
    }
}
