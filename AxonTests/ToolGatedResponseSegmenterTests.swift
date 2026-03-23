import XCTest
@testable import Axon

final class ToolGatedResponseSegmenterTests: XCTestCase {

    func testSegmentWithoutToolRequestReturnsEntireVisiblePrefix() {
        let response = "Here is the final answer."
        let segment = ToolGatedResponseSegmenter.segment(response)

        XCTAssertEqual(segment.visiblePrefix, response)
        XCTAssertNil(segment.firstToolRequest)
        XCTAssertFalse(segment.awaitingFenceClose)
    }

    func testSegmentWithIncompleteToolFenceWaitsForFenceClose() {
        let response = """
        Checking now...
        ```tool_request
        {"tool":"list_tools","query":"enabled"}
        """
        let segment = ToolGatedResponseSegmenter.segment(response)

        XCTAssertEqual(segment.visiblePrefix, "Checking now...\n")
        XCTAssertNil(segment.firstToolRequest)
        XCTAssertTrue(segment.awaitingFenceClose)
    }

    func testSegmentWithCompleteToolFenceDropsTrailingTextAndParsesFirstRequest() {
        let response = """
        I will check that.
        ```tool_request
        {"tool":"list_tools","query":"enabled"}
        ```
        This text must not be surfaced.
        """
        let segment = ToolGatedResponseSegmenter.segment(response)

        XCTAssertEqual(segment.visiblePrefix, "I will check that.\n")
        XCTAssertFalse(segment.awaitingFenceClose)
        XCTAssertEqual(segment.firstToolRequest?.tool, "list_tools")
        XCTAssertEqual(segment.firstToolRequest?.query, "enabled")
    }

    func testSegmentWithMultipleToolRequestsParsesOnlyFirstRequest() {
        let response = """
        Before
        ```tool_request
        {"tool":"list_tools","query":"enabled"}
        ```
        ```tool_request
        {"tool":"get_tool_details","query":"google_search"}
        ```
        """
        let segment = ToolGatedResponseSegmenter.segment(response)

        XCTAssertEqual(segment.visiblePrefix, "Before\n")
        XCTAssertFalse(segment.awaitingFenceClose)
        XCTAssertEqual(segment.firstToolRequest?.tool, "list_tools")
        XCTAssertEqual(segment.firstToolRequest?.query, "enabled")
    }
}
