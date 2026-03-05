import XCTest
@testable import Axon

final class BridgeConnectionQRParserTests: XCTestCase {
    func testParsesWSURLWithPairingToken() throws {
        let result = try BridgeConnectionQRParser.parse("ws://192.168.1.10:8082?pairingToken=abc123")

        XCTAssertEqual(result.host, "192.168.1.10")
        XCTAssertEqual(result.port, 8082)
        XCTAssertFalse(result.tlsEnabled)
        XCTAssertEqual(result.pairingToken, "abc123")
        XCTAssertEqual(result.suggestedName, "Bridge 192.168.1.10")
    }

    func testParsesWSSURL() throws {
        let result = try BridgeConnectionQRParser.parse("wss://bridge.local:9443")

        XCTAssertEqual(result.host, "bridge.local")
        XCTAssertEqual(result.port, 9443)
        XCTAssertTrue(result.tlsEnabled)
        XCTAssertNil(result.pairingToken)
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try BridgeConnectionQRParser.parse("http://bridge.local:8082")) { error in
            guard case BridgeConnectionQRParseError.unsupportedScheme = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsMissingPort() {
        XCTAssertThrowsError(try BridgeConnectionQRParser.parse("ws://bridge.local")) { error in
            guard case BridgeConnectionQRParseError.missingPort = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsZeroPort() {
        XCTAssertThrowsError(try BridgeConnectionQRParser.parse("ws://bridge.local:0")) { error in
            guard case BridgeConnectionQRParseError.invalidPort = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
