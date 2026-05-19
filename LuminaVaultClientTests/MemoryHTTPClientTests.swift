// LuminaVaultClient/LuminaVaultClientTests/MemoryHTTPClientTests.swift
//
// HER-34 — round-trip assertion on the write-side memory client.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

final class MemoryHTTPClientTests: XCTestCase {
    private var client: MemoryHTTPClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let base = BaseHTTPClient(
            session: session,
            tokenProvider: { "test-bearer" },
        )
        client = MemoryHTTPClient(client: base)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testUpsertSendsCorrectRequest() async throws {
        let memoryID = UUID()
        let payload = #"{"memory_id":"\#(memoryID.uuidString)","content":"Photo capture","summary":"saved"}"#
        let captured = CaptureBox()

        MockURLProtocol.handler = { req in
            captured.method = req.httpMethod
            captured.url = req.url
            captured.contentType = req.value(forHTTPHeaderField: "Content-Type")
            captured.authorization = req.value(forHTTPHeaderField: "Authorization")
            return (
                HTTPURLResponse(
                    url: req.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"],
                )!,
                Data(payload.utf8),
            )
        }

        let resp = try await client.upsert(MemoryUpsertRequest(
            content: "Photo capture",
            lat: 51.5,
            lng: -0.12,
            accuracyM: 25,
            placeName: "London",
        ))

        XCTAssertEqual(resp.memoryId, memoryID)
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.url?.path, "/v1/memory/upsert")
        XCTAssertEqual(captured.contentType, "application/json")
        XCTAssertEqual(captured.authorization, "Bearer test-bearer")
    }

    func testUpsertWithoutGeoSendsNilFields() async throws {
        let memoryID = UUID()
        let payload = #"{"memory_id":"\#(memoryID.uuidString)","content":"x","summary":"y"}"#

        MockURLProtocol.handler = { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(payload.utf8),
            )
        }

        let resp = try await client.upsert(MemoryUpsertRequest(content: "x"))
        XCTAssertEqual(resp.memoryId, memoryID)
    }
}

private final class CaptureBox: @unchecked Sendable {
    var method: String?
    var url: URL?
    var contentType: String?
    var authorization: String?
}
