// LuminaVaultClient/LuminaVaultClientTests/BaseHTTPClientFailureReportingTests.swift
//
// A failed request used to leave one `.debug` log line (method, path, status)
// and nothing else: the server's message, the coding path of a decode
// failure, and the fact that anything failed at all never left the device.
// `BaseHTTPClient.onRequestFailure` is the single seam the app wires to
// Sentry/PostHog; these tests pin what it receives.

import XCTest
@testable import LuminaVaultClient

final class BaseHTTPClientFailureReportingTests: XCTestCase {
    private var sink: FailureSink!
    private var client: BaseHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let sink = FailureSink()
        self.sink = sink
        client = BaseHTTPClient(
            session: URLSession(configuration: config),
            onRequestFailure: { failure in await sink.record(failure) }
        )
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private struct CreateEndpoint: Endpoint {
        struct Response: Decodable { let id: String }
        var path: String { "/v1/conversations" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { ["title": "x"] }
    }

    private static func response(_ request: URLRequest, status: Int, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, Data(body.utf8))
    }

    func test400ReportsMethodPathStatusAndServerMessage() async throws {
        MockURLProtocol.handler = { request in
            Self.response(
                request,
                status: 400,
                body: #"{"error":{"message":"Coding key `pinnedMemoryIDs` not found."}}"#
            )
        }

        do {
            _ = try await client.execute(CreateEndpoint())
            XCTFail("expected APIError.httpError")
        } catch APIError.httpError(let status, _) {
            XCTAssertEqual(status, 400)
        }

        let failures = await sink.failures
        XCTAssertEqual(failures, [
            APIRequestFailure(
                kind: .httpStatus,
                method: "POST",
                path: "/v1/conversations",
                statusCode: 400,
                detail: "Coding key `pinnedMemoryIDs` not found."
            ),
        ])
    }

    func testDecodeFailureReportsTheMissingKeyAndExplainsItToTheUser() async throws {
        MockURLProtocol.handler = { request in
            Self.response(request, status: 200, body: #"{"identifier":"abc"}"#)
        }

        var thrown: APIError?
        do {
            _ = try await client.execute(CreateEndpoint())
            XCTFail("expected APIError.decodingFailed")
        } catch let error as APIError {
            thrown = error
        }

        guard case .decodingFailed = thrown else {
            return XCTFail("expected .decodingFailed, got \(String(describing: thrown))")
        }
        XCTAssertEqual(
            thrown?.userFacingMessage,
            "Unexpected server response (missing `id`).",
            "the coding path used to be discarded and every decode failure read the same"
        )

        let failures = await sink.failures
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.kind, .decoding)
        XCTAssertEqual(failures.first?.method, "POST")
        XCTAssertEqual(failures.first?.path, "/v1/conversations")
        XCTAssertEqual(failures.first?.statusCode, 200)
        XCTAssertEqual(failures.first?.detail, "missing `id`")
    }

    func testSuccessReportsNothing() async throws {
        MockURLProtocol.handler = { request in
            Self.response(request, status: 200, body: #"{"id":"abc"}"#)
        }

        let result = try await client.execute(CreateEndpoint())
        XCTAssertEqual(result.id, "abc")
        let failures = await sink.failures
        XCTAssertTrue(failures.isEmpty)
    }
}

private actor FailureSink {
    private(set) var failures: [APIRequestFailure] = []
    func record(_ failure: APIRequestFailure) {
        failures.append(failure)
    }
}
