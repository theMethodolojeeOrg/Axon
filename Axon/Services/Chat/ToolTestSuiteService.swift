//
//  ToolTestSuiteService.swift
//  Axon
//
//  Chat-driven ToolsV2 test suites and assertion utilities.
//

import Foundation

// MARK: - Assertion Models

struct ToolTestAssertionSpec: Codable, Equatable, Sendable {
    var expectSuccess: Bool?
    var outputContains: [String]
    var outputNotContains: [String]
    var maxDurationMs: Int?

    init(
        expectSuccess: Bool? = nil,
        outputContains: [String] = [],
        outputNotContains: [String] = [],
        maxDurationMs: Int? = nil
    ) {
        self.expectSuccess = expectSuccess
        self.outputContains = outputContains
        self.outputNotContains = outputNotContains
        self.maxDurationMs = maxDurationMs
    }

    var isEmpty: Bool {
        expectSuccess == nil &&
        outputContains.isEmpty &&
        outputNotContains.isEmpty &&
        maxDurationMs == nil
    }

    private enum CodingKeys: String, CodingKey {
        case expectSuccess = "expect_success"
        case outputContains = "output_contains"
        case outputNotContains = "output_not_contains"
        case maxDurationMs = "max_duration_ms"
    }
}

struct ToolTestMetadata: Equatable, Sendable {
    let runId: String
    let caseId: String
    let assertion: ToolTestAssertionSpec?
}

struct ParsedToolRequestWithMetadata: Equatable, Sendable {
    let tool: String
    let query: String
    let toolTestMetadata: ToolTestMetadata?
    let metadataWarning: String?
}

enum ToolRequestParseResult: Equatable, Sendable {
    case success(ParsedToolRequestWithMetadata)
    case failure(String)
}

enum ToolTestAssertionStatus: String, Equatable, Sendable {
    case unavailable
    case pass
    case fail
}

struct ToolTestAssertionOutcome: Equatable, Sendable {
    let status: ToolTestAssertionStatus
    let failureReasons: [String]
    let notes: [String]

    static let unavailable = ToolTestAssertionOutcome(
        status: .unavailable,
        failureReasons: [],
        notes: ["No test assertions were provided for this tool request."]
    )
}

// MARK: - Assertion Evaluation

enum ToolTestAssertionEvaluator {
    static func evaluate(
        assertion: ToolTestAssertionSpec?,
        success: Bool,
        output: String,
        durationMs: Int?
    ) -> ToolTestAssertionOutcome {
        guard let assertion else {
            return .unavailable
        }
        guard !assertion.isEmpty else {
            return .unavailable
        }

        var failures: [String] = []
        var notes: [String] = []

        if let expectSuccess = assertion.expectSuccess, expectSuccess != success {
            failures.append("Expected success=\(expectSuccess), got success=\(success).")
        }

        for expectedSnippet in assertion.outputContains where !output.contains(expectedSnippet) {
            failures.append("Missing expected output snippet: \"\(expectedSnippet)\".")
        }

        for bannedSnippet in assertion.outputNotContains where output.contains(bannedSnippet) {
            failures.append("Found forbidden output snippet: \"\(bannedSnippet)\".")
        }

        if let maxDurationMs = assertion.maxDurationMs {
            if let durationMs {
                if durationMs > maxDurationMs {
                    failures.append("Duration \(durationMs)ms exceeded max \(maxDurationMs)ms.")
                }
            } else {
                notes.append("Duration unavailable; skipped max_duration_ms check.")
            }
        }

        if failures.isEmpty {
            return ToolTestAssertionOutcome(status: .pass, failureReasons: [], notes: notes)
        }

        return ToolTestAssertionOutcome(status: .fail, failureReasons: failures, notes: notes)
    }
}

// MARK: - Tool Request Parsing With Optional Metadata

enum ToolTestRequestParser {
    static func parse(_ code: String) -> ToolRequestParseResult {
        guard let data = code.data(using: .utf8) else {
            return .failure("Invalid UTF-8 encoding")
        }

        let rootAny: Any
        do {
            rootAny = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .failure("JSON parse error: \(error.localizedDescription)")
        }

        guard let root = rootAny as? [String: Any] else {
            return .failure("Not a valid JSON object")
        }

        guard let tool = root["tool"] as? String, !tool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing 'tool' field in JSON")
        }

        let query: String
        if let queryValue = root["query"] as? String {
            query = queryValue
        } else {
            query = ""
        }

        let metadataParse = parseToolTestMetadata(from: root["_tooltest"])

        return .success(
            ParsedToolRequestWithMetadata(
                tool: tool,
                query: query,
                toolTestMetadata: metadataParse.metadata,
                metadataWarning: metadataParse.warning
            )
        )
    }

    private static func parseToolTestMetadata(from value: Any?) -> (metadata: ToolTestMetadata?, warning: String?) {
        guard let value else {
            return (nil, nil)
        }

        guard let dict = value as? [String: Any] else {
            return (nil, "Ignored _tooltest metadata: expected an object.")
        }

        guard let runId = dict["run_id"] as? String, !runId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (nil, "Ignored _tooltest metadata: missing run_id.")
        }

        guard let caseId = dict["case_id"] as? String, !caseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (nil, "Ignored _tooltest metadata: missing case_id.")
        }

        let assertionResult = parseAssertion(from: dict["assert"])

        return (
            ToolTestMetadata(
                runId: runId,
                caseId: caseId,
                assertion: assertionResult.assertion
            ),
            assertionResult.warning
        )
    }

    private static func parseAssertion(from value: Any?) -> (assertion: ToolTestAssertionSpec?, warning: String?) {
        guard let value else {
            return (nil, nil)
        }

        guard let dict = value as? [String: Any] else {
            return (nil, "Ignored _tooltest.assert: expected an object.")
        }

        do {
            var spec = ToolTestAssertionSpec()

            if let expectSuccess = dict["expect_success"] {
                guard let boolValue = expectSuccess as? Bool else {
                    throw ParseWarning.invalidAssertionField("expect_success must be a boolean.")
                }
                spec.expectSuccess = boolValue
            }

            if let outputContains = dict["output_contains"] {
                spec.outputContains = try parseStringList(outputContains, fieldName: "output_contains")
            }

            if let outputNotContains = dict["output_not_contains"] {
                spec.outputNotContains = try parseStringList(outputNotContains, fieldName: "output_not_contains")
            }

            if let maxDurationMs = dict["max_duration_ms"] {
                guard let duration = maxDurationMs as? Int else {
                    throw ParseWarning.invalidAssertionField("max_duration_ms must be an integer.")
                }
                spec.maxDurationMs = duration
            }

            if spec.isEmpty {
                return (nil, "Ignored _tooltest.assert: no recognized assertion fields found.")
            }

            return (spec, nil)
        } catch let warning as ParseWarning {
            return (nil, "Ignored _tooltest.assert: \(warning.message)")
        } catch {
            return (nil, "Ignored _tooltest.assert due to parse error.")
        }
    }

    private static func parseStringList(_ value: Any, fieldName: String) throws -> [String] {
        if let stringValue = value as? String {
            return [stringValue]
        }

        if let arrayValue = value as? [Any] {
            var output: [String] = []
            for item in arrayValue {
                guard let stringItem = item as? String else {
                    throw ParseWarning.invalidAssertionField("\(fieldName) must be a string or array of strings.")
                }
                output.append(stringItem)
            }
            return output
        }

        throw ParseWarning.invalidAssertionField("\(fieldName) must be a string or array of strings.")
    }

    private enum ParseWarning: Error {
        case invalidAssertionField(String)

        var message: String {
            switch self {
            case .invalidAssertionField(let text): return text
            }
        }
    }
}

// MARK: - Tool Suite Definitions

struct ToolTestSuiteSummary: Equatable, Sendable {
    let id: String
    let name: String
    let description: String
}

@MainActor
final class ToolTestSuiteService {
    static let shared = ToolTestSuiteService()

    static let defaultSuiteId = "core_v2_safe"

    private struct ToolTestCaseDefinition: Equatable {
        let id: String
        let tool: String
        let query: String
        let assertion: ToolTestAssertionSpec
    }

    private struct ToolTestSuiteDefinition: Equatable {
        let id: String
        let name: String
        let description: String
        let cases: [ToolTestCaseDefinition]
    }

    private let suites: [ToolTestSuiteDefinition] = [
        ToolTestSuiteDefinition(
            id: "core_v2_safe",
            name: "Core V2 Safe",
            description: "Deterministic, internal/read-focused ToolsV2 smoke suite.",
            cases: [
                ToolTestCaseDefinition(
                    id: "list_tools_enabled",
                    tool: "list_tools",
                    query: "enabled",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Available Tools"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "get_tool_details_list_tools",
                    tool: "get_tool_details",
                    query: "list_tools",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["ID:", "list_tools"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "list_tools_all",
                    tool: "list_tools",
                    query: "all",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Available Tools"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "get_tool_details_query_system_state",
                    tool: "get_tool_details",
                    query: "query_system_state",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["ID:", "query_system_state"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "query_system_state_tools",
                    tool: "query_system_state",
                    query: "tools",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Tool Status"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "query_system_state_current",
                    tool: "query_system_state",
                    query: "current",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Current System State"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "query_system_state_providers",
                    tool: "query_system_state",
                    query: "providers",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Available Providers"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "query_system_state_permissions",
                    tool: "query_system_state",
                    query: "permissions",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Permissions"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "query_system_state_all",
                    tool: "query_system_state",
                    query: "all",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Full System State", "Configuration", "Tools"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "discover_ports_all",
                    tool: "discover_ports",
                    query: "all",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        maxDurationMs: 15000
                    )
                )
            ]
        ),
        ToolTestSuiteDefinition(
            id: "cor_v2_extended",
            name: "Core V2 Extended",
            description: "Expanded read-only coverage with additional and negative-path assertions.",
            cases: [
                ToolTestCaseDefinition(
                    id: "list_tools_enabled_extended",
                    tool: "list_tools",
                    query: "enabled",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Available Tools"],
                        outputNotContains: ["No tools found"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "get_tool_details_discover_ports",
                    tool: "get_tool_details",
                    query: "discover_ports",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["ID:", "discover_ports"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "get_tool_details_unknown_tool",
                    tool: "get_tool_details",
                    query: "__tooltest_missing_tool__",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: false,
                        outputContains: ["Tool not found"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "query_system_state_all_extended",
                    tool: "query_system_state",
                    query: "all",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Full System State", "Configuration", "Tools"],
                        outputNotContains: ["Unknown system state tool"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "query_system_state_permissions_extended",
                    tool: "query_system_state",
                    query: "permissions",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Permissions"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "query_system_state_fallback_current",
                    tool: "query_system_state",
                    query: "__invalid_scope__",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputContains: ["Current System State"],
                        maxDurationMs: 15000
                    )
                ),
                ToolTestCaseDefinition(
                    id: "discover_ports_all_extended",
                    tool: "discover_ports",
                    query: "all",
                    assertion: ToolTestAssertionSpec(
                        expectSuccess: true,
                        outputNotContains: ["execution failed", "fatal"],
                        maxDurationMs: 15000
                    )
                )
            ]
        )
    ]

    private init() {}

    func availableSuites() -> [ToolTestSuiteSummary] {
        suites.map {
            ToolTestSuiteSummary(id: $0.id, name: $0.name, description: $0.description)
        }
    }

    func hasSuite(_ suiteId: String) -> Bool {
        suites.contains(where: { $0.id == suiteId })
    }

    func requiredTools(for suiteId: String) -> [String] {
        guard let suite = suites.first(where: { $0.id == suiteId }) else {
            return []
        }
        return Array(Set(suite.cases.map(\.tool))).sorted()
    }

    func renderSuiteListMarkdown() -> String {
        let rows = availableSuites()
            .map { "- `\($0.id)` — \($0.description)" }
            .joined(separator: "\n")

        return """
        ## Tool Test Suites

        \(rows)

        Run a suite with:
        - `/tooltest` (defaults to `\(Self.defaultSuiteId)`)
        - `/tooltest <suite_id>`
        """
    }

    func renderSuiteMarkdown(suiteId: String, runId: String = UUID().uuidString) -> String? {
        guard let suite = suites.first(where: { $0.id == suiteId }) else {
            return nil
        }

        var sections: [String] = []
        sections.append("## Tool Test Run: \(suite.name)")
        sections.append("")
        sections.append("**Suite ID:** `\(suite.id)`")
        sections.append("**Run ID:** `\(runId)`")
        sections.append("")
        sections.append("Apply each tool request below to execute and validate assertions inline.")
        sections.append("")

        for testCase in suite.cases {
            sections.append("### Case: `\(testCase.id)`")
            sections.append("```tool_request")
            sections.append(renderToolRequestJSON(for: testCase, runId: runId))
            sections.append("```")
            sections.append("")
        }

        return sections.joined(separator: "\n")
    }

    private func renderToolRequestJSON(for testCase: ToolTestCaseDefinition, runId: String) -> String {
        var root: [String: Any] = [
            "tool": testCase.tool,
            "query": testCase.query
        ]

        var assertionDict: [String: Any] = [:]
        if let expectSuccess = testCase.assertion.expectSuccess {
            assertionDict["expect_success"] = expectSuccess
        }
        if !testCase.assertion.outputContains.isEmpty {
            assertionDict["output_contains"] = testCase.assertion.outputContains
        }
        if !testCase.assertion.outputNotContains.isEmpty {
            assertionDict["output_not_contains"] = testCase.assertion.outputNotContains
        }
        if let maxDuration = testCase.assertion.maxDurationMs {
            assertionDict["max_duration_ms"] = maxDuration
        }

        root["_tooltest"] = [
            "run_id": runId,
            "case_id": testCase.id,
            "assert": assertionDict
        ]

        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"tool\":\"\(testCase.tool)\",\"query\":\"\(testCase.query)\"}"
        }

        return json
    }
}
