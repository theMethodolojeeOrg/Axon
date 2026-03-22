import XCTest
@testable import Axon

final class StreamingResponseHandlerTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(StreamingURLProtocolStub.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(StreamingURLProtocolStub.self)
        super.tearDown()
    }

    override func tearDown() {
        StreamingURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testOpenAICompatibleReasoningOnlyStreamCompletes() async {
        let body = """
        data: {"choices":[{"delta":{"reasoning_content":"thinking token"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """

        StreamingURLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }

        let handler = StreamingResponseHandler()
        let config = StreamingResponseHandler.StreamingConfig(
            provider: "openai-compatible",
            apiKey: "test-key",
            model: "grok-4-fast-reasoning",
            baseUrl: "https://mock.example/v1"
        )
        let stream = handler.stream(
            config: config,
            messages: [Message(conversationId: "c1", role: .user, content: "hello")]
        )

        let events = await collectEvents(from: stream)
        let reasoning = events.compactMap { event -> String? in
            if case .reasoningDelta(let text) = event { return text }
            return nil
        }
        let completions = events.compactMap { event -> StreamingCompletion? in
            if case .completion(let completion) = event { return completion }
            return nil
        }
        let textDeltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }

        XCTAssertEqual(reasoning.joined(), "thinking token")
        XCTAssertEqual(textDeltas.count, 0)
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.reasoning, "thinking token")
    }

    func testOpenAICompatibleStreamEmbeddedErrorSurfacesAsStreamingErrorEvent() async {
        let body = """
        data: {"error":{"type":"invalid_request_error","message":"Model not found","code":"model_not_found"}}

        """

        StreamingURLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }

        let handler = StreamingResponseHandler()
        let config = StreamingResponseHandler.StreamingConfig(
            provider: "openai-compatible",
            apiKey: "test-key",
            model: "unknown-model",
            baseUrl: "https://mock.example/v1"
        )
        let stream = handler.stream(
            config: config,
            messages: [Message(conversationId: "c1", role: .user, content: "hello")]
        )

        let events = await collectEvents(from: stream)
        let errors = events.compactMap { event -> String? in
            if case .error(let error) = event { return error.localizedDescription }
            return nil
        }
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].lowercased().contains("model not found"))
    }

    func testGeminiJSONArrayStreamCompletesWithContent() async {
        let body = """
        [{"candidates":[{"content":{"parts":[{"text":"hello"}]}}]},{"candidates":[{"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":2,"candidatesTokenCount":1,"totalTokenCount":3}}]
        """

        StreamingURLProtocolStub.handler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains(":streamGenerateContent") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let handler = StreamingResponseHandler()
        let config = StreamingResponseHandler.StreamingConfig(
            provider: "gemini",
            apiKey: "test-key",
            model: "gemini-2.5-pro"
        )
        let stream = handler.stream(
            config: config,
            messages: [Message(conversationId: "c1", role: .user, content: "hello")]
        )

        let events = await collectEvents(from: stream)
        let text = events.compactMap { event -> String? in
            if case .textDelta(let delta) = event { return delta }
            return nil
        }.joined()
        let completions = events.compactMap { event -> StreamingCompletion? in
            if case .completion(let completion) = event { return completion }
            return nil
        }

        XCTAssertEqual(text, "hello")
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.fullContent, "hello")
    }

    func testGeminiStreamEmbeddedErrorSurfacesAsStreamingErrorEvent() async {
        let body = """
        data: {"error":{"code":400,"status":"INVALID_ARGUMENT","message":"Model not found"}}

        """

        StreamingURLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, Data(body.utf8))
        }

        let handler = StreamingResponseHandler()
        let config = StreamingResponseHandler.StreamingConfig(
            provider: "gemini",
            apiKey: "test-key",
            model: "unknown-model"
        )
        let stream = handler.stream(
            config: config,
            messages: [Message(conversationId: "c1", role: .user, content: "hello")]
        )

        let events = await collectEvents(from: stream)
        let errors = events.compactMap { event -> String? in
            if case .error(let error) = event { return error.localizedDescription }
            return nil
        }

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].lowercased().contains("model not found"))
    }

    private func collectEvents(from stream: AsyncThrowingStream<StreamingEvent, Error>) async -> [StreamingEvent] {
        var events: [StreamingEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch {
            XCTFail("Unexpected thrown error: \(error)")
        }
        return events
    }
}

private final class StreamingURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
