// LuminaVaultClient/LuminaVaultClientTests/MemoryHTTPClientTests.swift
//
// HER-34 — round-trip assertion on the write-side memory client.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared
import Synchronization

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

    func testGetFetchesMemoryByID() async throws {
        let memoryID = UUID()
        let payload = #"""
        {
          "id": "\#(memoryID.uuidString)",
          "content": "linked memory body",
          "tags": ["memo", "source"],
          "created_at": "2026-05-23T10:00:00Z",
          "review_state": "approved"
        }
        """#
        let captured = CaptureBox()

        MockURLProtocol.handler = { req in
            captured.method = req.httpMethod
            captured.url = req.url
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

        let memory = try await client.get(id: memoryID)

        XCTAssertEqual(memory.id, memoryID)
        XCTAssertEqual(memory.content, "linked memory body")
        XCTAssertEqual(memory.tags, ["memo", "source"])
        XCTAssertEqual(captured.method, "GET")
        XCTAssertEqual(captured.url?.path, "/v1/memory/\(memoryID.uuidString.lowercased())")
        XCTAssertEqual(captured.authorization, "Bearer test-bearer")
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

    /// The Brain graph spans every vault: opening a memory names its own
    /// vault, which replaces the active vault's header for that one request.
    func testGetWithVaultOverridesTheActiveVault() async throws {
        let active = UUID(), own = UUID(), memoryID = UUID()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = MemoryHTTPClient(client: BaseHTTPClient(
            session: URLSession(configuration: config),
            tokenProvider: { "test-bearer" },
            vaultProvider: { active }
        ))
        let seen = VaultHeaderBox()
        MockURLProtocol.handler = { req in
            seen.append(req.value(forHTTPHeaderField: "X-Vault-ID"))
            let body = #"{"id":"\#(memoryID.uuidString)","content":"x","tags":[],"review_state":"approved"}"#
            guard let url = req.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else { throw URLError(.badServerResponse) }
            return (response, Data(body.utf8))
        }

        _ = try await client.get(id: memoryID, vaultID: own)
        _ = try await client.get(id: memoryID, vaultID: nil)

        XCTAssertEqual(seen.values, [own.uuidString, active.uuidString])
    }
}

private nonisolated final class VaultHeaderBox: Sendable {
    private let lock = Mutex<[String?]>([])
    func append(_ value: String?) { lock.withLock { $0.append(value) } }
    var values: [String?] { lock.withLock { $0 } }
}

private final class CaptureBox: @unchecked Sendable {
    var method: String?
    var url: URL?
    var contentType: String?
    var authorization: String?
}
