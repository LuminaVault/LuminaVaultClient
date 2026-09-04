// LuminaVaultClient/LuminaVaultClientTests/HermesRunsClientTests.swift
//
// Hermes Companion Phase 1 — wire format for `/v1/hermes/runs`.
//
// The SSE feed is deliberately covered at the endpoint level only:
// `URLSession.bytes(for:)` does not yield through `URLProtocol` mocks under
// XCTest (see the note atop `BaseHTTPClientSSETests`), so the frame parser is
// tested there and what is worth asserting here is the thing the parser
// cannot see — that the `?after=` cursor reaches the URL.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

final class HermesRunsClientTests: XCTestCase {
    private var base: BaseHTTPClient!
    private var client: HermesRunsHTTPClient!

    private static let runID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        base = BaseHTTPClient(session: URLSession(configuration: config))
        client = HermesRunsHTTPClient(client: base)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private static func runJSON(
        status: String = "running",
        pendingApproval: String? = nil
    ) -> String {
        """
        {
          "id": "\(runID.uuidString)",
          "hermesRunID": "run_ab12",
          "status": "\(status)",
          "prompt": "tidy the vault",
          "startedAt": "2026-09-04T09:00:00Z",
          "lastSeq": 7,
          \(pendingApproval.map { "\"pendingApproval\": \($0)," } ?? "")
          "summary": null
        }
        """
    }

    private static func ok(_ request: URLRequest, _ json: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(json.utf8))
    }

    private static func failure(_ request: URLRequest, status: Int, code: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(#"{"error":{"message":"\#(code)"}}"#.utf8))
    }

    // MARK: - Commands

    func testStartPostsPromptAndDecodesAcceptedRun() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/hermes/runs")
            XCTAssertEqual(request.httpMethod, "POST")
            let decoded = try? JSONDecoder().decode(
                HermesRunStartRequest.self,
                from: request.bodyData() ?? Data()
            )
            XCTAssertEqual(decoded?.prompt, "tidy the vault")
            XCTAssertEqual(decoded?.sessionID, "sess-1")
            return Self.ok(request, Self.runJSON())
        }

        let run = try await client.start(
            HermesRunStartRequest(prompt: "tidy the vault", sessionID: "sess-1")
        )
        XCTAssertEqual(run.id, Self.runID)
        XCTAssertEqual(run.hermesRunID, "run_ab12")
        XCTAssertEqual(run.status, .running)
        XCTAssertEqual(run.lastSeq, 7)
    }

    func testApprovalPostsChoiceToTheRunPath() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/hermes/runs/\(Self.runID.uuidString)/approval")
            XCTAssertEqual(request.httpMethod, "POST")
            let decoded = try? JSONDecoder().decode(
                HermesRunApprovalRequest.self,
                from: request.bodyData() ?? Data()
            )
            XCTAssertEqual(decoded?.choice, .session)
            return Self.ok(request, Self.runJSON())
        }

        _ = try await client.approve(Self.runID, choice: .session)
    }

    func testStopPostsWithNoBody() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/hermes/runs/\(Self.runID.uuidString)/stop")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.bodyData())
            return Self.ok(request, Self.runJSON(status: "stopped"))
        }

        let run = try await client.stop(Self.runID)
        XCTAssertEqual(run.status, .stopped)
        XCTAssertTrue(run.status.isTerminal)
    }

    // MARK: - Queries

    func testListSendsLimitAndUnwrapsRuns() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/hermes/runs")
            XCTAssertEqual(request.url?.query, "limit=5")
            return Self.ok(request, #"{"runs":[\#(Self.runJSON())]}"#)
        }

        let runs = try await client.list(limit: 5)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.prompt, "tidy the vault")
    }

    func testGetDecodesPendingApprovalWithItsOfferedChoices() async throws {
        let approval = """
        {
          "command": "rm -rf ./build",
          "choices": ["once", "session", "deny"],
          "requestedAt": "2026-09-04T09:01:00Z"
        }
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/hermes/runs/\(Self.runID.uuidString)")
            return Self.ok(
                request,
                Self.runJSON(status: "waiting_for_approval", pendingApproval: approval)
            )
        }

        let run = try await client.get(Self.runID)
        XCTAssertEqual(run.status, .waitingForApproval)
        XCTAssertEqual(run.pendingApproval?.command, "rm -rf ./build")
        // The server offers a subset — `always` is absent here and the UI
        // must not invent it.
        XCTAssertEqual(run.pendingApproval?.choices, [.once, .session, .deny])
    }

    // MARK: - Event feed cursor

    func testEventsPathCarriesTheResumeCursor() {
        let endpoint = HermesRunsEndpoints.Events(runID: Self.runID, after: 12)
        XCTAssertEqual(
            endpoint.path,
            "/v1/hermes/runs/\(Self.runID.uuidString)/events?after=12"
        )
    }

    func testEventsPathOmitsCursorWhenNothingIsHeldYet() {
        let endpoint = HermesRunsEndpoints.Events(runID: Self.runID, after: 0)
        XCTAssertEqual(endpoint.path, "/v1/hermes/runs/\(Self.runID.uuidString)/events")
    }

    // MARK: - Error mapping

    func testUnsupportedHermesIsItsOwnFailureNotAGenericOne() async {
        MockURLProtocol.handler = { request in
            Self.failure(request, status: 501, code: "hermes_runs_unsupported")
        }

        do {
            _ = try await client.start(HermesRunStartRequest(prompt: "go"))
            XCTFail("expected a failure")
        } catch {
            let failure = HermesRunsFailure(error)
            XCTAssertEqual(failure, .unsupported)
            XCTAssertFalse(failure.isRetryable)
            XCTAssertNotNil(failure.guidance)
        }
    }

    func testExpiredRunMapsToItsOwnFailure() async {
        MockURLProtocol.handler = { request in
            Self.failure(request, status: 410, code: "hermes_run_expired")
        }

        do {
            _ = try await client.stop(Self.runID)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(HermesRunsFailure(error), .expired)
        }
    }

    func testAlreadyAnsweredApprovalMapsToConflict() async {
        MockURLProtocol.handler = { request in
            Self.failure(request, status: 409, code: "hermes_approval_not_pending")
        }

        do {
            _ = try await client.approve(Self.runID, choice: .once)
            XCTFail("expected a failure")
        } catch {
            let failure = HermesRunsFailure(error)
            XCTAssertEqual(failure, .approvalNotPending)
            XCTAssertFalse(failure.isRetryable)
        }
    }

    func testUpstreamHermesErrorMapsToUpstream() async {
        MockURLProtocol.handler = { request in
            Self.failure(request, status: 502, code: "hermes_runs_upstream_error")
        }

        do {
            _ = try await client.get(Self.runID)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(HermesRunsFailure(error), .upstream)
        }
    }

    func testEmptyPromptMapsToPromptRequired() async {
        MockURLProtocol.handler = { request in
            Self.failure(request, status: 400, code: "prompt_required")
        }

        do {
            _ = try await client.start(HermesRunStartRequest(prompt: ""))
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(HermesRunsFailure(error), .promptRequired)
        }
    }

    /// `BaseHTTPClient` converts every 429 to `.rateLimited` before the body
    /// is read, so `hermes_runs_limit` only ever reaches us via the status.
    func testRunLimitMapsThroughRateLimited() async {
        MockURLProtocol.handler = { request in
            Self.failure(request, status: 429, code: "hermes_runs_limit")
        }

        do {
            _ = try await client.start(HermesRunStartRequest(prompt: "go"))
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(HermesRunsFailure(error), .tooManyRuns)
        }
    }

    /// An unrecognised body must still land on the status-derived case
    /// rather than a bare "something went wrong".
    func testUnknownBodyFallsBackToTheStatusLine() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 501,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("not json".utf8))
        }

        do {
            _ = try await client.get(Self.runID)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(HermesRunsFailure(error), .unsupported)
        }
    }
}

private extension URLRequest {
    /// MockURLProtocol strips `httpBody` when the request becomes a body
    /// stream. Re-materialise it for assertion.
    func bodyData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
