// LuminaVaultClient/LuminaVaultClientTests/BaseHTTPClientSSETests.swift
//
// HER-269 — covers the SSE wire parser used by `BaseHTTPClient.executeStream`.
// The parser is extracted to `SSEFrameParser` (pure value-type state
// machine) because `URLSession.bytes(for:)` does not yield through
// `URLProtocol` mocks under XCTest. Manual end-to-end verification in
// the simulator covers the URLSession plumbing.
//
// Coverage:
//   - multi-event stream → one frame per blank-line boundary
//   - multi-line `data:` payloads joined with `\n`
//   - `[DONE]` sentinel terminates
//   - comment lines (`:`) and ignored fields (`event:` / `id:` / `retry:`)
//   - flush() emits trailing frame when stream ends without blank line
//   - non-2xx HTTP response throws `APIError.httpError` (BaseHTTPClient
//     short-circuits before parsing — covered by the live transport test)
import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

final class BaseHTTPClientSSETests: XCTestCase {

    private let decoder = JSONDecoder.hvDefault

    private func decode(_ data: Data) throws -> QueryStreamEvent {
        try decoder.decode(QueryStreamEvent.self, from: data)
    }

    private func run(_ lines: [String]) throws -> ([QueryStreamEvent], Bool) {
        var parser = SSEFrameParser()
        var events: [QueryStreamEvent] = []
        var hitDone = false
        for line in lines {
            switch parser.feed(line: line) {
            case .pending: continue
            case .event(let data): events.append(try decode(data))
            case .done: hitDone = true
            }
            if hitDone { break }
        }
        if !hitDone {
            if case .event(let data) = parser.flush() {
                events.append(try decode(data))
            }
        }
        return (events, hitDone)
    }

    func testYieldsOneEventPerBlankLine() throws {
        let lines = [
            #"data: {"type":"token","payload":"hi"}"#,
            "",
            #"data: {"type":"token","payload":" world"}"#,
            "",
            #"data: {"type":"done"}"#,
            "",
        ]
        let (events, done) = try run(lines)
        XCTAssertEqual(events, [.token("hi"), .token(" world"), .done])
        XCTAssertFalse(done, "typed .done case decoded as event, not as [DONE] sentinel")
    }

    func testIgnoresCommentsAndUnknownFields() throws {
        let lines = [
            ":ping",
            "",
            "event: token",
            "id: 7",
            #"data: {"type":"token","payload":"a"}"#,
            "",
            ":keepalive",
            #"data: {"type":"done"}"#,
            "",
        ]
        let (events, _) = try run(lines)
        XCTAssertEqual(events, [.token("a"), .done])
    }

    func testJoinsMultiLineDataPayload() throws {
        // Two consecutive `data:` lines are joined with `\n` per the
        // SSE spec, then JSON-decoded as a single frame.
        let lines = [
            #"data: {"type":"token","#,
            #"data: "payload":"x"}"#,
            "",
        ]
        let (events, _) = try run(lines)
        XCTAssertEqual(events, [.token("x")])
    }

    func testDoneSentinelTerminatesStream() throws {
        let lines = [
            #"data: {"type":"token","payload":"first"}"#,
            "",
            "data: [DONE]",
            "",
            #"data: {"type":"token","payload":"after"}"#,
            "",
        ]
        let (events, done) = try run(lines)
        XCTAssertEqual(events, [.token("first")])
        XCTAssertTrue(done)
    }

    func testFlushEmitsTrailingFrameWithoutBlankLine() throws {
        // Server hung up mid-frame — `flush()` salvages it.
        let lines = [
            #"data: {"type":"token","payload":"final"}"#,
            // no trailing blank line
        ]
        let (events, _) = try run(lines)
        XCTAssertEqual(events, [.token("final")])
    }

    func testCRLFCompatibleSinceLineSplitterStripsCR() throws {
        // `URLSession.bytes.lines` strips trailing `\r`. The parser
        // never sees the CR. This test pins the expectation that a
        // stripped-CR feed parses cleanly with no extra handling.
        let lines = [
            #"data: {"type":"token","payload":"crlf"}"#,
            "",
        ]
        let (events, _) = try run(lines)
        XCTAssertEqual(events, [.token("crlf")])
    }

    func testMalformedJSONThrowsAtDecodeBoundary() {
        var parser = SSEFrameParser()
        _ = parser.feed(line: "data: not-json")
        let outcome = parser.feed(line: "")
        guard case .event(let data) = outcome else {
            XCTFail("expected .event for malformed payload")
            return
        }
        XCTAssertThrowsError(try decode(data))
    }
}

// MARK: - Live transport: non-2xx short-circuit

/// Covers the response-status check in `BaseHTTPClient.executeStream`
/// before any byte iteration. This path works through `URLProtocol`
/// mocks because the failure is detected synchronously from the
/// `HTTPURLResponse`, never reading the byte stream.
final class BaseHTTPClientSSETransportTests: XCTestCase {
    var client: BaseHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        client = BaseHTTPClient(session: URLSession(configuration: config))
    }

    private struct StubStreamEndpoint: StreamingEndpoint {
        typealias Event = QueryStreamEvent
        var path: String { "/stream" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
    }

    func testNon2xxThrowsHTTPError() async {
        let body = #"{"error":"upstream_unreachable"}"#
        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test.local/stream")!,
                statusCode: 502,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"],
            )!
            return (response, body.data(using: .utf8)!)
        }

        do {
            for try await _ in client.executeStream(StubStreamEndpoint()) {
                XCTFail("should not yield on 502")
            }
            XCTFail("expected APIError.httpError")
        } catch let APIError.httpError(code, _) {
            XCTAssertEqual(code, 502)
            // Trailing body capture relies on URLSession.bytes which is
            // unreliable under URLProtocol mocks; status code is the
            // load-bearing assertion here.
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
