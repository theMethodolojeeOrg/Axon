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
            suiteId: "core_v2_extended",
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
        let required = Set(ToolTestSuiteService.shared.requiredTools(for: "core_v2_extended"))
        let expected: Set<String> = [
            "list_tools",
            "get_tool_details",
            "query_system_state",
            "discover_ports"
        ]
        XCTAssertEqual(required, expected)
    }

    func testLegacyExtendedAliasStillResolves() {
        XCTAssertTrue(ToolTestSuiteService.shared.hasSuite("cor_v2_extended"))
        XCTAssertEqual(
            ToolTestSuiteService.shared.canonicalSuiteId(for: "cor_v2_extended"),
            "core_v2_extended"
        )
    }

    func testRenderDiscoveryHardeningSuiteIncludesExpectedToolRequestBlocks() throws {
        let runId = "run-discovery-789"
        guard let markdown = ToolTestSuiteService.shared.renderSuiteMarkdown(
            suiteId: "core_v2_discovery_hardening",
            runId: runId
        ) else {
            return XCTFail("Expected discovery hardening suite markdown")
        }

        let blocks = extractToolRequestBlocks(from: markdown)
        XCTAssertEqual(blocks.count, 7)
        assertRunMetadata(blocks: blocks, runId: runId)
    }

    func testRequiredToolsForDiscoveryHardeningSuiteAreStable() {
        let required = Set(ToolTestSuiteService.shared.requiredTools(for: "core_v2_discovery_hardening"))
        let expected: Set<String> = [
            "list_tools",
            "get_tool_details",
            "discover_ports"
        ]
        XCTAssertEqual(required, expected)
    }

    func testRenderStateReadonlySuiteIncludesExpectedToolRequestBlocks() throws {
        let runId = "run-state-101"
        guard let markdown = ToolTestSuiteService.shared.renderSuiteMarkdown(
            suiteId: "core_v2_state_readonly",
            runId: runId
        ) else {
            return XCTFail("Expected state readonly suite markdown")
        }

        let blocks = extractToolRequestBlocks(from: markdown)
        XCTAssertEqual(blocks.count, 7)
        assertRunMetadata(blocks: blocks, runId: runId)
    }

    func testRequiredToolsForStateReadonlySuiteAreStable() {
        let required = Set(ToolTestSuiteService.shared.requiredTools(for: "core_v2_state_readonly"))
        let expected: Set<String> = [
            "query_system_state",
            "temporal_status",
            "query_job_status",
            "query_device_presence",
            "query_covenant"
        ]
        XCTAssertEqual(required, expected)
    }

    func testRenderAgentStateRoundtripSuiteIncludesExpectedToolRequestBlocks() throws {
        let runId = "run-agent-202"
        guard let markdown = ToolTestSuiteService.shared.renderSuiteMarkdown(
            suiteId: "core_v2_agent_state_roundtrip",
            runId: runId
        ) else {
            return XCTFail("Expected agent state roundtrip suite markdown")
        }

        let blocks = extractToolRequestBlocks(from: markdown)
        XCTAssertEqual(blocks.count, 6)
        assertRunMetadata(blocks: blocks, runId: runId)
    }

    func testRequiredToolsForAgentStateRoundtripSuiteAreStable() {
        let required = Set(ToolTestSuiteService.shared.requiredTools(for: "core_v2_agent_state_roundtrip"))
        let expected: Set<String> = [
            "agent_state_append",
            "agent_state_query",
            "agent_state_clear",
            "persistence_disable"
        ]
        XCTAssertEqual(required, expected)
    }

    func testRenderApprovalPathsSuiteIncludesExpectedToolRequestBlocks() throws {
        let runId = "run-approval-303"
        guard let markdown = ToolTestSuiteService.shared.renderSuiteMarkdown(
            suiteId: "core_v2_approval_paths",
            runId: runId
        ) else {
            return XCTFail("Expected approval paths suite markdown")
        }

        let blocks = extractToolRequestBlocks(from: markdown)
        XCTAssertEqual(blocks.count, 4)
        assertRunMetadata(blocks: blocks, runId: runId)
    }

    func testRequiredToolsForApprovalPathsSuiteAreStable() {
        let required = Set(ToolTestSuiteService.shared.requiredTools(for: "core_v2_approval_paths"))
        let expected: Set<String> = [
            "spawn_scout",
            "spawn_mechanic",
            "spawn_designer",
            "terminate_job"
        ]
        XCTAssertEqual(required, expected)
    }

    func testRenderGeminiCapabilitiesSuiteIncludesExpectedToolRequestBlocks() throws {
        let runId = "run-gemini-404"
        guard let markdown = ToolTestSuiteService.shared.renderSuiteMarkdown(
            suiteId: "core_v2_gemini_capabilities",
            runId: runId
        ) else {
            return XCTFail("Expected gemini capabilities suite markdown")
        }

        let blocks = extractToolRequestBlocks(from: markdown)
        XCTAssertEqual(blocks.count, 6)
        assertRunMetadata(blocks: blocks, runId: runId)
    }

    func testRequiredToolsForGeminiCapabilitiesSuiteAreStable() {
        let required = Set(ToolTestSuiteService.shared.requiredTools(for: "core_v2_gemini_capabilities"))
        let expected: Set<String> = [
            "gemini_audio_understanding",
            "gemini_speech_to_text",
            "gemini_video_understanding",
            "gemini_url_context",
            "gemini_google_maps",
            "gemini_google_search"
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

    private func assertRunMetadata(blocks: [String], runId: String) {
        for block in blocks {
            let data = try? XCTUnwrap(block.data(using: .utf8))
            guard let data else {
                XCTFail("Expected utf8 data")
                continue
            }
            let object = try? XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            guard let object else {
                XCTFail("Expected JSON object")
                continue
            }
            let metadata = try? XCTUnwrap(object["_tooltest"] as? [String: Any])
            guard let metadata else {
                XCTFail("Expected _tooltest metadata")
                continue
            }
            XCTAssertEqual(metadata["run_id"] as? String, runId)
            XCTAssertFalse((metadata["case_id"] as? String ?? "").isEmpty)
        }
    }
}
