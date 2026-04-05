import XCTest
@testable import Axon

final class ToolTestAssertionEvaluatorTests: XCTestCase {

    func testAssertionPassesWhenAllConditionsSatisfied() {
        let spec = ToolTestAssertionSpec(
            expectSuccess: true,
            outputContains: ["Available Tools"],
            outputNotContains: ["fatal"],
            maxDurationMs: 500
        )

        let outcome = ToolTestAssertionEvaluator.evaluate(
            assertion: spec,
            success: true,
            output: "## Available Tools\nEverything good.",
            durationMs: 120
        )

        XCTAssertEqual(outcome.status, .pass)
        XCTAssertTrue(outcome.failureReasons.isEmpty)
    }

    func testAssertionFailsOnSuccessMismatch() {
        let spec = ToolTestAssertionSpec(expectSuccess: true)
        let outcome = ToolTestAssertionEvaluator.evaluate(
            assertion: spec,
            success: false,
            output: "error",
            durationMs: 10
        )

        XCTAssertEqual(outcome.status, .fail)
        XCTAssertTrue(outcome.failureReasons.contains { $0.contains("Expected success") })
    }

    func testAssertionFailsOnMissingContainsSnippet() {
        let spec = ToolTestAssertionSpec(outputContains: ["Current System State"])
        let outcome = ToolTestAssertionEvaluator.evaluate(
            assertion: spec,
            success: true,
            output: "Tool Status only",
            durationMs: 10
        )

        XCTAssertEqual(outcome.status, .fail)
        XCTAssertTrue(outcome.failureReasons.contains { $0.contains("Missing expected output snippet") })
    }

    func testAssertionFailsWhenDurationExceeded() {
        let spec = ToolTestAssertionSpec(maxDurationMs: 10)
        let outcome = ToolTestAssertionEvaluator.evaluate(
            assertion: spec,
            success: true,
            output: "ok",
            durationMs: 50
        )

        XCTAssertEqual(outcome.status, .fail)
        XCTAssertTrue(outcome.failureReasons.contains { $0.contains("exceeded max") })
    }

    func testMalformedMetadataFallsBackWithoutCrashing() {
        let code = #"{"tool":"list_tools","query":"enabled","_tooltest":"bad"}"#
        let result = ToolTestRequestParser.parse(code)

        guard case .success(let parsed) = result else {
            return XCTFail("Expected parse success with metadata warning")
        }

        XCTAssertEqual(parsed.tool, "list_tools")
        XCTAssertEqual(parsed.query, "enabled")
        XCTAssertNil(parsed.toolTestMetadata)
        XCTAssertNotNil(parsed.metadataWarning)

        let outcome = ToolTestAssertionEvaluator.evaluate(
            assertion: parsed.toolTestMetadata?.assertion,
            success: true,
            output: "ok",
            durationMs: 10
        )
        XCTAssertEqual(outcome.status, .unavailable)
    }

    func testInvalidAssertionSchemaFallsBackToUnavailable() {
        let code = #"{"tool":"list_tools","query":"enabled","_tooltest":{"run_id":"r1","case_id":"c1","assert":{"expect_success":"yes"}}}"#
        let result = ToolTestRequestParser.parse(code)

        guard case .success(let parsed) = result else {
            return XCTFail("Expected parse success with warning")
        }

        XCTAssertEqual(parsed.toolTestMetadata?.runId, "r1")
        XCTAssertEqual(parsed.toolTestMetadata?.caseId, "c1")
        XCTAssertNil(parsed.toolTestMetadata?.assertion)
        XCTAssertNotNil(parsed.metadataWarning)

        let outcome = ToolTestAssertionEvaluator.evaluate(
            assertion: parsed.toolTestMetadata?.assertion,
            success: true,
            output: "ok",
            durationMs: 10
        )
        XCTAssertEqual(outcome.status, .unavailable)
    }
}
