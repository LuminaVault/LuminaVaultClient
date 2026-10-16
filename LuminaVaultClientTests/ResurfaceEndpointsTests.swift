// LuminaVaultClient/LuminaVaultClientTests/ResurfaceEndpointsTests.swift
//
// Wire shape of the two calls behind "To revisit": the queue, and a review
// with or without an action.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class ResurfaceEndpointsTests: XCTestCase {
    private let memoryID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testResurfaceIsAPassiveGetWithALimit() {
        let endpoint = ResurfaceEndpoints.Get(limit: 3)
        XCTAssertEqual(endpoint.path, "/v1/me/resurface?limit=3")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertFalse(endpoint.presentsPaywallOn402)
    }

    func testReviewWithAnActionSendsIt() throws {
        let endpoint = MemoryEndpoints.Review(id: memoryID, action: .soon)
        XCTAssertEqual(endpoint.path, "/v1/memory/6f9619ff-8b86-d011-b42d-00c04fc964ff/review")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertFalse(endpoint.presentsPaywallOn402)
        let body = try XCTUnwrap(endpoint.body)
        let data = try endpoint.encoder.encode(AnyEncodable(body))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json, ["action": "soon"])
    }

    func testReviewWithoutAnActionSendsNoBody() {
        XCTAssertNil(MemoryEndpoints.Review(id: memoryID, action: nil).body)
    }

    func testTheQueueDecodesFromTheServersCamelCase() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = ResurfaceHTTPClient(client: BaseHTTPClient(session: URLSession(configuration: config)))
        let id = memoryID
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/me/resurface")
            XCTAssertEqual(request.url?.query, "limit=3")
            let payload = """
            {"items":[{"memoryId":"\(id.uuidString)","snippet":"Flat API","kind":"decision",
            "createdAt":"2025-10-16T09:00:00Z","reason":"onThisDay","why":"Saved a year ago today"},
            {"memoryId":"\(UUID().uuidString)","snippet":"x","createdAt":"2025-10-16T09:00:00Z",
            "reason":"somethingNew","why":"?"}]}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }
        let result = try await client.resurface(limit: 3)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].memoryId, id)
        XCTAssertEqual(result.items[0].reason, .onThisDay)
        XCTAssertEqual(result.items[0].why, "Saved a year ago today")
        XCTAssertEqual(result.items[1].reason, .unknown, "an unknown reason must not fail the queue")
    }

    func testReviewDecodesTheNextDate() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = MemoryHTTPClient(client: BaseHTTPClient(session: URLSession(configuration: config)))
        let id = memoryID
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/memory/\(id.uuidString.lowercased())/review")
            let payload = """
            {"memoryId":"\(id.uuidString)","reviewedAt":"2026-10-16T09:00:00Z","reviewCount":2,
            "nextReviewAt":"2026-10-19T09:00:00Z","resurfaceMuted":false}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }
        let result = try await client.review(id: id, action: .soon)
        XCTAssertEqual(result.reviewCount, 2)
        XCTAssertNotNil(result.nextReviewAt)
        XCTAssertEqual(result.resurfaceMuted, false)
    }
}
