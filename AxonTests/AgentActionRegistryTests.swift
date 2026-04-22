import XCTest
@testable import Axon

@MainActor
final class AgentActionRegistryTests: XCTestCase {

    func testDiscoverActionsIncludesCoreSet() {
        let registry = AgentActionRegistry.shared
        let actions = registry.discoverActions()
        let ids = Set(actions.map(\.id))

        XCTAssertTrue(ids.contains("open_chat"))
        XCTAssertTrue(ids.contains("new_chat"))
        XCTAssertTrue(ids.contains("send_message"))
        XCTAssertTrue(ids.contains("toggle_bridge"))
    }

    func testDiscoverActionsFiltersByView() {
        let registry = AgentActionRegistry.shared
        let actions = registry.discoverActions(view: "settings")

        XCTAssertFalse(actions.isEmpty)
        XCTAssertTrue(actions.contains(where: { $0.id == "open_settings" }))
    }

    func testDiscoverActionsUnknownPlatformReturnsEmpty() {
        let registry = AgentActionRegistry.shared
        let actions = registry.discoverActions(platform: "linux")
        XCTAssertTrue(actions.isEmpty)
    }

    func testRiskMetadataMarksSensitiveActions() {
        let registry = AgentActionRegistry.shared
        let actions = registry.discoverActions()

        guard let send = actions.first(where: { $0.id == "send_message" }) else {
            return XCTFail("Missing send_message descriptor")
        }
        XCTAssertEqual(send.riskLevel, .medium)
        XCTAssertEqual(send.requiresApproval, true)

        guard let toggle = actions.first(where: { $0.id == "toggle_bridge" }) else {
            return XCTFail("Missing toggle_bridge descriptor")
        }
        XCTAssertEqual(toggle.riskLevel, .high)
        XCTAssertEqual(toggle.requiresApproval, true)
    }

    func testInvokeUnknownActionFailsDeterministically() async {
        let registry = AgentActionRegistry.shared
        let result = await registry.invokeAction(id: "not_real_action")

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorCode, "unknown_action")
    }

    func testAnyCodableRoundTripHelpers() {
        let source: [String: Any] = [
            "flag": true,
            "count": 7,
            "nested": ["title": "Axon"]
        ]

        let encoded = AgentActionRegistry.dictionaryToAnyCodable(source)
        XCTAssertEqual(encoded["flag"], .bool(true))
        XCTAssertEqual(encoded["count"], .int(7))

        if let nested = encoded["nested"] {
            let foundation = AgentActionRegistry.foundationValue(from: nested)
            let dictionary = foundation as? [String: Any]
            XCTAssertEqual(dictionary?["title"] as? String, "Axon")
        } else {
            XCTFail("Expected nested value")
        }
    }
}

final class BridgeProtocolAxonMethodTests: XCTestCase {
    func testBridgeMethodIncludesAxonControlMethods() {
        XCTAssertEqual(BridgeMethod(rawValue: "axon/discoverActions"), .axonDiscoverActions)
        XCTAssertEqual(BridgeMethod(rawValue: "axon/invokeAction"), .axonInvokeAction)
        XCTAssertEqual(BridgeMethod(rawValue: "axon/getState"), .axonGetState)
    }

    func testAxonInvokeActionParamsDecode() throws {
        let json = """
        {
          "id": "send_message",
          "params": {
            "message": "hello"
          },
          "context": {
            "source": "bridge",
            "sessionId": "s1",
            "actor": "tester",
            "view": "chat"
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AxonInvokeActionParams.self, from: data)

        XCTAssertEqual(decoded.id, "send_message")
        XCTAssertEqual(decoded.params?["message"], .string("hello"))
        XCTAssertEqual(decoded.context?.source, "bridge")
        XCTAssertEqual(decoded.context?.sessionId, "s1")
        XCTAssertEqual(decoded.context?.actor, "tester")
        XCTAssertEqual(decoded.context?.view, "chat")
    }
}
