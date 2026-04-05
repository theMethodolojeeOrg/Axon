import XCTest
@testable import Axon

@MainActor
final class ToolTestSuiteServiceTests: XCTestCase {

    func testRenderCoreSuiteIncludesExpectedToolRequestBlocks() throws {
        let runId = "run-test-123"
        guard let markdown = ToolTestSuiteService.shared.renderSuiteMarkdown(
            suiteId: "core_v2_safe",
            runId: runId
        ) else {
            return XCTFail("Expected suite markdown")
        }

        let blocks = extractToolRequestBlocks(from: markdown)
        XCTAssertEqual(blocks.count, 10)

        for block in blocks {
            let data = try XCTUnwrap(block.data(using: .utf8))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNotNil(object["tool"])
            XCTAssertNotNil(object["query"])

            let metadata = try XCTUnwrap(object["_tooltest"] as? [String: Any])
            XCTAssertEqual(metadata["run_id"] as? String, runId)
            XCTAssertFalse((metadata["case_id"] as? String ?? "").isEmpty)
            XCTAssertNotNil(metadata["assert"] as? [String: Any])
        }
    }

    func testRequiredToolsForCoreSuiteAreStable() {
        let required = Set(ToolTestSuiteService.shared.requiredTools(for: "core_v2_safe"))
        let expected: Set<String> = [
            "list_tools",
            "get_tool_details",
            "query_system_state",
            "discover_ports"
        ]
        XCTAssertEqual(required, expected)
    }

    func testRenderExtendedSuiteIncludesExpectedToolRequestBlocks() throws {
        let runId = "run-ext-456"
        guard let markdown = ToolTestSuiteService.shared.renderSuiteMarkdown(
            suiteId: "cor_v2_extended",
            runId: runId
        ) else {
            return XCTFail("Expected extended suite markdown")
        }

        let blocks = extractToolRequestBlocks(from: markdown)
        XCTAssertEqual(blocks.count, 7)

        for block in blocks {
            let data = try XCTUnwrap(block.data(using: .utf8))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let metadata = try XCTUnwrap(object["_tooltest"] as? [String: Any])
            XCTAssertEqual(metadata["run_id"] as? String, runId)
            XCTAssertFalse((metadata["case_id"] as? String ?? "").isEmpty)
        }
    }

    func testRequiredToolsForExtendedSuiteAreStable() {
        let required = Set(ToolTestSuiteService.shared.requiredTools(for: "cor_v2_extended"))
        let expected: Set<String> = [
            "list_tools",
            "get_tool_details",
            "query_system_state",
            "discover_ports"
        ]
        XCTAssertEqual(required, expected)
    }

    private func extractToolRequestBlocks(from markdown: String) -> [String] {
        let pattern = "```tool_request\\s*\\n([\\s\\S]*?)\\n```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = regex.matches(in: markdown, range: nsRange)

        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: markdown) else { return nil }
            return String(markdown[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
