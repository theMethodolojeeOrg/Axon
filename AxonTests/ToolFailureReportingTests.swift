import XCTest
@testable import Axon

final class ToolFailureReportingTests: XCTestCase {

    func testLiveToolCallToToolCallPreservesFailureMetadata() {
        let result = ToolCallResult(
            success: false,
            output: "Tool execution failed: timeout",
            duration: 0.42,
            errorMessage: "timeout"
        )

        let liveToolCall = LiveToolCall(
            id: "tool-call-1",
            name: "mac_shell",
            displayName: "Run Shell",
            icon: "terminal",
            state: .failure,
            request: ToolCallRequest(tool: "mac_shell", query: "ls -la"),
            result: result,
            startedAt: Date(timeIntervalSince1970: 10),
            completedAt: Date(timeIntervalSince1970: 11)
        )

        let persisted = liveToolCall.toToolCall()

        XCTAssertEqual(persisted.id, "tool-call-1")
        XCTAssertEqual(persisted.name, "mac_shell")
        XCTAssertEqual(persisted.result, "Tool execution failed: timeout")
        XCTAssertEqual(persisted.success, false)
        XCTAssertEqual(persisted.errorMessage, "timeout")
    }

    @MainActor
    func testFormatToolResultIncludesStructuredFailureStatus() {
        let failedResult = ToolResult(
            tool: "mac_shell",
            success: false,
            result: "Tool execution failed: sandbox denied",
            sources: nil,
            memoryOperation: nil
        )

        let formatted = ToolProxyService.shared.formatToolResult(failedResult)

        XCTAssertTrue(formatted.contains("```tool_result"))
        XCTAssertTrue(formatted.contains("\"tool\":\"mac_shell\""))
        XCTAssertTrue(formatted.contains("\"success\":false"))
        XCTAssertTrue(formatted.contains("\"error\":\"Tool execution failed: sandbox denied\""))
        XCTAssertTrue(formatted.contains("**Status:** failure"))
    }

    @MainActor
    func testFormatToolResultSuccessDoesNotInjectErrorField() {
        let successResult = ToolResult(
            tool: "list_tools",
            success: true,
            result: "Listed 3 tools.",
            sources: nil,
            memoryOperation: nil
        )

        let formatted = ToolProxyService.shared.formatToolResult(successResult)

        XCTAssertTrue(formatted.contains("```tool_result"))
        XCTAssertTrue(formatted.contains("\"success\":true"))
        XCTAssertTrue(formatted.contains("**Status:** success"))
        XCTAssertFalse(formatted.contains("\"error\":"))
    }
}
