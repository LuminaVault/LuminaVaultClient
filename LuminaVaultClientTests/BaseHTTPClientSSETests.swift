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

    // MARK: - Byte-level framing (transport path)

    /// Drives the parser the way the real transport does — through
    /// `feed(bytes:)` — instead of hand-fed `""` lines. This is the path
    /// that was broken: the transport used `AsyncLineSequence`, which
    /// drops the blank lines that delimit SSE frames, so the parser
    /// concatenated the whole stream and failed with "Unexpected
    /// character '{' after top-level value". Feeding raw bytes preserves
    /// the delimiters.
    private func runBytes(_ wire: String) throws -> ([QueryStreamEvent], Bool) {
        var parser = SSEFrameParser()
        var events: [QueryStreamEvent] = []
        var hitDone = false
        func handle(_ outcomes: [SSEFrameParser.Outcome]) throws {
            for o in outcomes {
                switch o {
                case .pending: continue
                case .event(let data): events.append(try decode(data))
                case .done: hitDone = true
                }
            }
        }
        try handle(parser.feed(bytes: Array(wire.utf8)))
        if !hitDone { try handle(parser.finishBytes()) }
        return (events, hitDone)
    }

    func testFeedBytesYieldsFramePerBlankLine() throws {
        // Realistic wire: multiple `data:` frames separated by blank lines,
        // exactly what the server emits and what the broken `.lines`
        // transport mis-handled.
        let wire = """
        data: {"type":"token","payload":"I"}

        data: {"type":"token","payload":" am"}

        data: {"type":"token","payload":" fine"}

        data: {"type":"done"}

        """
        let (events, done) = try runBytes(wire)
        XCTAssertEqual(events, [.token("I"), .token(" am"), .token(" fine"), .done])
        XCTAssertFalse(done, "typed .done decodes as event, not [DONE] sentinel")
    }

    func testFeedBytesHandlesCRLFFrames() throws {
        let wire = "data: {\"type\":\"token\",\"payload\":\"x\"}\r\n\r\ndata: {\"type\":\"done\"}\r\n\r\n"
        let (events, _) = try runBytes(wire)
        XCTAssertEqual(events, [.token("x"), .done])
    }

    func testFeedBytesSplitAcrossArbitraryChunkBoundaries() throws {
        // The byte stream can be chunked anywhere — mid-frame, mid-blank
        // line. Framing must survive splits at every offset.
        let wire = """
        data: {"type":"token","payload":"chunk"}

        data: {"type":"token","payload":"split"}

        """
        let allBytes = Array(wire.utf8)
        for split in 1..<allBytes.count {
            var parser = SSEFrameParser()
            var events: [QueryStreamEvent] = []
            func handle(_ outcomes: [SSEFrameParser.Outcome]) throws {
                for o in outcomes {
                    if case .event(let data) = o { events.append(try decode(data)) }
                }
            }
            try handle(parser.feed(bytes: allBytes[..<split]))
            try handle(parser.feed(bytes: allBytes[split...]))
            try handle(parser.finishBytes())
            XCTAssertEqual(events, [.token("chunk"), .token("split")], "split at \(split)")
        }
    }

    func testFeedBytesFlushesTrailingFrameWithoutBlankLine() throws {
        // Server hangs up after the last frame with no trailing blank line.
        let wire = #"data: {"type":"token","payload":"last"}"#
        let (events, _) = try runBytes(wire)
        XCTAssertEqual(events, [.token("last")])
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
