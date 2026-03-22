import XCTest
@testable import Axon

final class SSEParserTests: XCTestCase {

    func testParseDataLinePreservesDone() {
        XCTAssertEqual(SSEParser.parseDataLine("data: [DONE]"), "[DONE]")
    }

    func testParseOpenAIEventParsesProviderError() {
        let payload = #"{"error":{"type":"invalid_request_error","message":"Model not found","code":"model_not_found"}}"#
        guard let event = SSEParser.parseOpenAIEvent(payload) else {
            return XCTFail("Expected provider error event")
        }

        switch event {
        case .providerError(let type, let message, let code):
            XCTAssertEqual(type, "invalid_request_error")
            XCTAssertEqual(message, "Model not found")
            XCTAssertEqual(code, "model_not_found")
        default:
            XCTFail("Expected provider error, got \(event)")
        }
    }

    func testParseOpenAIEventParsesReasoningDelta() {
        let payload = #"{"choices":[{"delta":{"reasoning_content":"thinking token"},"finish_reason":null}]}"#
        guard let event = SSEParser.parseOpenAIEvent(payload) else {
            return XCTFail("Expected reasoning delta event")
        }

        switch event {
        case .reasoningDelta(let text):
            XCTAssertEqual(text, "thinking token")
        default:
            XCTFail("Expected reasoning delta, got \(event)")
        }
    }

    func testParseOpenAIEventParsesCompletionWithoutContent() {
        let payload = #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        guard let event = SSEParser.parseOpenAIEvent(payload) else {
            return XCTFail("Expected completion event")
        }

        switch event {
        case .completion(let finishReason):
            XCTAssertEqual(finishReason, "stop")
        default:
            XCTFail("Expected completion, got \(event)")
        }
    }

    func testParseGeminiChunkParsesSSEDataLine() {
        let payload = #"data: {"candidates":[{"content":{"parts":[{"text":"hello"}]}}]}"#
        let events = SSEParser.parseGeminiChunk(payload)
        let deltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }
        XCTAssertEqual(deltas, ["hello"])
    }

    func testParseGeminiChunkParsesJSONArrayVariant() {
        let payload = #"[{"candidates":[{"content":{"parts":[{"text":"hello"}]}}]},{"candidates":[{"finishReason":"STOP"}]}]"#
        let events = SSEParser.parseGeminiChunk(payload)

        let deltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }
        let hasFinish = events.contains { event in
            if case .finishReason("STOP") = event { return true }
            return false
        }

        XCTAssertEqual(deltas, ["hello"])
        XCTAssertTrue(hasFinish)
    }

    func testParseGeminiChunkParsesProviderError() {
        let payload = #"{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"Model not found"}}"#
        let events = SSEParser.parseGeminiChunk(payload)
        guard let first = events.first else {
            return XCTFail("Expected provider error event")
        }

        switch first {
        case .providerError(let code, let status, let message):
            XCTAssertEqual(code, 400)
            XCTAssertEqual(status, "INVALID_ARGUMENT")
            XCTAssertEqual(message, "Model not found")
        default:
            XCTFail("Expected provider error, got \(first)")
        }
    }
}
