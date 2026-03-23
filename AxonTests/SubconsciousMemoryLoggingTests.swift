import XCTest
@testable import Axon

final class SubconsciousMemoryLoggingTests: XCTestCase {

    func testAppSettingsRoundTripWithSubconsciousLogging() throws {
        var settings = AppSettings()
        settings.subconsciousMemoryLogging = SubconsciousMemoryLoggingSettings(
            enabled: true,
            builtInProvider: AIProvider.gemini.rawValue,
            customProviderId: nil,
            builtInModel: "gemini-2.5-pro",
            customModelId: nil,
            rollingContextPercent: 0.25,
            maxMemories: 14,
            confidenceThreshold: 0.42,
            minSalienceThreshold: 0.33,
            relevanceWeight: 0.5,
            confidenceWeight: 0.35,
            recencyWeight: 0.2,
            includeEpistemicBoundaries: true,
            showConfidence: false,
            maxToolRounds: 4
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.subconsciousMemoryLogging, settings.subconsciousMemoryLogging)
    }

    func testAppSettingsDecodeWhenSubconsciousFieldMissing() throws {
        var settings = AppSettings()
        settings.subconsciousMemoryLogging = SubconsciousMemoryLoggingSettings(
            enabled: true,
            builtInProvider: AIProvider.openai.rawValue,
            customProviderId: nil,
            builtInModel: "gpt-5.2",
            customModelId: nil,
            rollingContextPercent: 0.4,
            maxMemories: 12,
            confidenceThreshold: 0.6,
            minSalienceThreshold: 0.3,
            relevanceWeight: 0.5,
            confidenceWeight: 0.25,
            recencyWeight: 0.25,
            includeEpistemicBoundaries: false,
            showConfidence: true,
            maxToolRounds: 3
        )

        let encoded = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "subconsciousMemoryLogging")
        let legacyEncoded = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyEncoded)
        XCTAssertNil(decoded.subconsciousMemoryLogging)
        XCTAssertEqual(decoded.resolvedSubconsciousMemoryLogging, .default)
    }

    func testSyncableSettingsRoundTripForSubconsciousLogging() {
        var source = AppSettings()
        source.subconsciousMemoryLogging = SubconsciousMemoryLoggingSettings(
            enabled: true,
            builtInProvider: AIProvider.anthropic.rawValue,
            customProviderId: nil,
            builtInModel: "claude-sonnet-4-6",
            customModelId: nil,
            rollingContextPercent: 0.3,
            maxMemories: 9,
            confidenceThreshold: 0.35,
            minSalienceThreshold: 0.22,
            relevanceWeight: 0.45,
            confidenceWeight: 0.25,
            recencyWeight: 0.3,
            includeEpistemicBoundaries: true,
            showConfidence: false,
            maxToolRounds: 5
        )

        let syncable = SyncableSettings(from: source)
        var applied = AppSettings()
        syncable.apply(to: &applied)

        XCTAssertEqual(applied.subconsciousMemoryLogging, source.subconsciousMemoryLogging)
    }

    func testRollingContextBudgetMathAndClamping() {
        XCTAssertEqual(MemoryService.clampedRollingTokenBudget(percent: 0.25, contextWindow: 4_000), 1_000)
        XCTAssertEqual(MemoryService.clampedRollingTokenBudget(percent: 0.25, contextWindow: 1_000_000), 250_000)
        XCTAssertEqual(MemoryService.clampedRollingTokenBudget(percent: 2.0, contextWindow: 8_000), 8_000)
        XCTAssertEqual(MemoryService.clampedRollingTokenBudget(percent: 0.0, contextWindow: 8_000), 256)
    }

    func testThreadOverrideIgnoreFlagPersistence() {
        let manager = ConversationOverridesManager.shared
        let conversationId = "subconscious-ignore-\(UUID().uuidString)"

        defer {
            manager.deleteOverrides(for: conversationId)
        }

        XCTAssertFalse(manager.isSubconsciousLoggingDisabled(for: conversationId))
        manager.setSubconsciousLoggingDisabled(true, for: conversationId)
        XCTAssertTrue(manager.isSubconsciousLoggingDisabled(for: conversationId))

        manager.setSubconsciousLoggingDisabled(false, for: conversationId)
        XCTAssertFalse(manager.isSubconsciousLoggingDisabled(for: conversationId))
    }

    func testOnlyCreateMemoryToolRequestsAreAllowed() {
        let requests = [
            ToolRequest(tool: ToolId.createMemory.rawValue, query: "{\"memory\":\"remember this\"}"),
            ToolRequest(tool: ToolId.codeExecution.rawValue, query: "print('unsafe')")
        ]

        let filtered = MemoryService.filterSubconsciousToolRequests(requests)
        XCTAssertEqual(filtered.allowed.count, 1)
        XCTAssertEqual(filtered.allowed.first?.tool, ToolId.createMemory.rawValue)
        XCTAssertEqual(filtered.ignored.count, 1)
        XCTAssertEqual(filtered.ignored.first?.tool, ToolId.codeExecution.rawValue)
    }
}
