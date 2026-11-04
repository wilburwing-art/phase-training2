import XCTest
@testable import PhaseTraining

/// The response paths of `CoachClient` against a stubbed URLSession: what the
/// drawer sees on success, on an HTTP error, on a dropped connection, on a
/// body it cannot decode, and from a server-sent-event stream. Coverage was
/// 2.8% (gap pass 2026-10-31, item 8): the only tested line was the daily
/// ceiling. No request leaves the machine.
final class CoachClientTransportTests: XCTestCase {

    private static let budgetKeys = ["pt_coach_gateway_requests_today", "pt_coach_gateway_requests_day"]

    override func setUpWithError() throws {
        // A build without the gateway token stops at that guard before any
        // response path runs (CI builds one without it).
        if CoachSecrets.gatewayToken.isEmpty { throw XCTSkip("no gateway token in this build") }
        Self.budgetKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        StubProtocol.reset()
    }

    override func tearDown() {
        Self.budgetKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        StubProtocol.reset()
    }

    private func client() -> CoachClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return CoachClient(session: URLSession(configuration: config))
    }

    // MARK: - send

    func test_send_decodesTextAndUsage() async throws {
        StubProtocol.respond(status: 200, body: """
        {"model":"claude-test","content":[{"type":"text","text":"Hold "},{"type":"text","text":"225."}],
         "usage":{"input_tokens":12,"output_tokens":3}}
        """)
        let r = try await client().send(userMessage: "next weight?")
        XCTAssertEqual(r.text, "Hold 225.")
        XCTAssertEqual(r.inputTokens, 12)
        XCTAssertEqual(r.outputTokens, 3)
        XCTAssertEqual(r.model, "claude-test")
        let sent = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertTrue(sent.url?.path.hasSuffix("v1/messages") ?? false)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-version"), CoachConfig.anthropicVersion)
        XCTAssertNil(sent.value(forHTTPHeaderField: "x-api-key"), "BYOK: the app never sends a key")
        XCTAssertEqual(sent.timeoutInterval, CoachConfig.requestTimeoutSeconds)
    }

    func test_send_nonSuccessStatusCarriesStatusAndBody() async {
        StubProtocol.respond(status: 529, body: #"{"error":"overloaded"}"#)
        do {
            _ = try await client().send(userMessage: "hi")
            XCTFail("expected an HTTP error")
        } catch CoachClient.CoachError.http(let status, let body) {
            XCTAssertEqual(status, 529)
            XCTAssertTrue(body.contains("overloaded"), body)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_send_droppedConnectionIsATransportError() async {
        StubProtocol.fail(URLError(.timedOut))
        do {
            _ = try await client().send(userMessage: "hi")
            XCTFail("expected a transport error")
        } catch CoachClient.CoachError.transport(let underlying) {
            XCTAssertEqual((underlying as? URLError)?.code, .timedOut)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_send_undecodableBodyIsADecodeError() async {
        StubProtocol.respond(status: 200, body: "<html>gateway page</html>")
        do {
            _ = try await client().send(userMessage: "hi")
            XCTFail("expected a decode error")
        } catch CoachClient.CoachError.decode {
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - stream

    func test_stream_yieldsTextToolCallAndStopReason() async throws {
        StubProtocol.respond(status: 200, body: [
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Moving "}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Thursday."}}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu_1","name":"propose_plan_edits"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"edits\":"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"[]}"}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#,
            "data: [DONE]",
        ].joined(separator: "\n\n"))

        var text = "", tool: (String, String, String)?, stop: String?
        for try await part in client().stream(cachedSystem: "s", perTurnContext: "c", history: [], userMessage: "u") {
            switch part {
            case .textDelta(let t): text += t
            case .toolCall(let id, let name, let input): tool = (id, name, String(decoding: input, as: UTF8.self))
            case .stopped(let reason): stop = reason
            }
        }
        XCTAssertEqual(text, "Moving Thursday.")
        XCTAssertEqual(tool?.0, "tu_1")
        XCTAssertEqual(tool?.1, "propose_plan_edits")
        XCTAssertEqual(tool?.2, #"{"edits":[]}"#, "partial JSON deltas are joined in order")
        XCTAssertEqual(stop, "max_tokens", "a cut-off reply reaches the drawer")
    }

    func test_stream_nonSuccessStatusThrowsWithStatus() async {
        StubProtocol.respond(status: 401, body: "unauthorized")
        do {
            for try await _ in client().stream(cachedSystem: "s", perTurnContext: "c", history: [], userMessage: "u") {}
            XCTFail("expected an HTTP error")
        } catch CoachClient.CoachError.http(let status, let body) {
            XCTAssertEqual(status, 401)
            XCTAssertTrue(body.contains("unauthorized"), body)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

/// Serves one canned response (or error) to every request and records the last request.
private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var error: Error?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func reset() { status = 200; body = Data(); error = nil; lastRequest = nil }
    static func respond(status: Int, body: String) { self.status = status; self.body = Data(body.utf8); error = nil }
    static func fail(_ error: Error) { self.error = error }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
