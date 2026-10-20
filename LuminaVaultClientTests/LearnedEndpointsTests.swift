// LuminaVaultClient/LuminaVaultClientTests/LearnedEndpointsTests.swift
//
// Wire shape of GET /v1/me/learned: the `since` window, and the digest
// decoding from the server's camelCase.

import Foundation
import LuminaVaultShared
import os
import XCTest

@testable import LuminaVaultClient

@MainActor
final class LearnedEndpointsTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testWithoutSinceTheServerPicksTheWindow() {
        let endpoint = LearnedEndpoints.Get(since: nil)
        XCTAssertEqual(endpoint.path, "/v1/me/learned")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertFalse(endpoint.presentsPaywallOn402)
        XCTAssertNil(endpoint.body)
    }

    func testSinceIsSentAsAnISO8601Instant() {
        // 2026-10-09T08:30:00Z
        let since = Date(timeIntervalSince1970: 1_791_534_600)
        let endpoint = LearnedEndpoints.Get(since: since)
        XCTAssertEqual(endpoint.path, "/v1/me/learned?since=2026-10-09T08:30:00Z")
    }

    func testTheDigestDecodesAndSendsSince() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = LearnedHTTPClient(client: BaseHTTPClient(session: URLSession(configuration: config)))
        let soulID = UUID()
        let memoryID = UUID()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/me/learned")
            XCTAssertEqual(request.url?.query, "since=2026-10-09T08:30:00Z")
            let payload = """
            {"since":"2026-10-09T08:30:00Z","until":"2026-10-16T08:30:00Z",
            "soulChanges":[{"id":"\(soulID.uuidString)","title":"Short answers",
            "summary":"Lead with the answer.","createdAt":"2026-10-14T09:00:00Z"}],
            "memories":[{"id":"\(memoryID.uuidString)","snippet":"Ship on Tuesdays","kind":"decision",
            "reviewState":"pending","createdAt":"2026-10-15T09:00:00Z"},
            {"id":"\(UUID().uuidString)","snippet":"x","kind":"somethingNew",
            "reviewState":"auto","createdAt":"2026-10-15T09:00:00Z"}],
            "isEmpty":false}
            """
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
            ))
            return (response, Data(payload.utf8))
        }
        let digest = try await client.learned(since: Date(timeIntervalSince1970: 1_791_534_600))
        XCTAssertEqual(digest.soulChanges.map(\.id), [soulID])
        XCTAssertEqual(digest.memories.count, 2)
        XCTAssertEqual(digest.memories[0].id, memoryID)
        XCTAssertEqual(digest.memories[0].kind, "decision")
        XCTAssertEqual(digest.memories[1].kind, "somethingNew", "an unknown kind must not fail the digest")
        XCTAssertFalse(digest.isEmpty)
    }

    func testKeepAndForgetUseTheExistingImprovementPaths() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = SelfImprovementHTTPClient(client: BaseHTTPClient(session: URLSession(configuration: config)))
        let id = UUID()
        let paths = PathLog()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            paths.append(request.url?.path ?? "")
            let state = request.url?.lastPathComponent == "approve" ? "approved" : "rejected"
            let payload = """
            {"change":{"id":"\(id.uuidString)","kind":"soul","state":"\(state)","trigger":"weekly",
            "title":"t","summary":"s","createdAt":"2026-10-14T09:00:00Z"}}
            """
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil
            ))
            return (response, Data(payload.utf8))
        }
        _ = try await client.decide(changeID: id, approve: true)
        _ = try await client.decide(changeID: id, approve: false)
        XCTAssertEqual(paths.values, [
            "/v1/me/improvement/changes/\(id.uuidString)/approve",
            "/v1/me/improvement/changes/\(id.uuidString)/reject",
        ])
    }
}

/// The paths the mock server saw, appended from URLProtocol's thread.
nonisolated private final class PathLog: Sendable {
    private let lock = OSAllocatedUnfairLock<[String]>(initialState: [])

    func append(_ path: String) {
        lock.withLock { $0.append(path) }
    }

    var values: [String] {
        lock.withLock { $0 }
    }
}
