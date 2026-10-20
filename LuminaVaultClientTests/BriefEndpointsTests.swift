// LuminaVaultClient/LuminaVaultClientTests/BriefEndpointsTests.swift
//
// Wire shape of the brief and commitments endpoints: paths, methods and
// bodies, and the server's camelCase JSON decoding into the shared DTOs —
// including `{"brief": null}` and kinds this build does not know.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class BriefEndpointsTests: XCTestCase {
    private func makeHTTPClient() -> BaseHTTPClient {
        addTeardownBlock { MockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return BaseHTTPClient(session: URLSession(configuration: config))
    }

    private func respond(_ status: Int, _ body: String, check: @escaping @Sendable (URLRequest) -> Void = { _ in }) {
        MockURLProtocol.handler = { request in
            check(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil
            ))
            return (response, Data(body.utf8))
        }
    }

    // MARK: - Brief

    func testTodayIsTheServersDefault() async {
        let endpoint = BriefEndpoints.Get(date: nil)
        XCTAssertEqual(endpoint.path, "/v1/me/brief")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertFalse(endpoint.presentsPaywallOn402)
        XCTAssertEqual(BriefEndpoints.Get(date: "2026-10-20").path, "/v1/me/brief?date=2026-10-20")
    }

    func testFeedbackPostsTheActionToTheCard() async throws {
        let briefID = try XCTUnwrap(UUID(uuidString: "0B000000-0000-4000-8000-000000000001"))
        let endpoint = BriefEndpoints.Feedback(briefID: briefID, cardID: "weather-2", action: .down)
        XCTAssertEqual(endpoint.path, "/v1/me/brief/0b000000-0000-4000-8000-000000000001/cards/weather-2/feedback")
        XCTAssertEqual(endpoint.method, .post)
        let body = try JSONEncoder().encode(AnyEncodable(try XCTUnwrap(endpoint.body)))
        XCTAssertEqual(String(bytes: body, encoding: .utf8), #"{"action":"down"}"#)
        XCTAssertEqual(
            BriefEndpoints.Feedback(briefID: briefID, cardID: "a/b?c", action: .up).path,
            "/v1/me/brief/0b000000-0000-4000-8000-000000000001/cards/a%2Fb%3Fc/feedback",
            "a card id cannot break out of its path segment"
        )
    }

    func testABriefDecodesWithUnknownKindsKept() async throws {
        let client = BriefHTTPClient(client: makeHTTPClient())
        let id = UUID()
        let memoryID = UUID()
        respond(200, """
        {"brief":{"id":"\(id.uuidString)","date":"2026-10-20","endNote":"That's it for today.",
        "createdAt":"2026-10-20T07:00:00Z","cards":[
        {"id":"openLoops","kind":"openLoops","title":"Open loops","body":"- Send Ana the deck",
        "why":"Things you said you'd do","refs":[{"kind":"commitment","id":"\(UUID().uuidString)"}]},
        {"id":"toRevisit","kind":"toRevisit","title":"To revisit","body":"Ship on Tuesdays",
        "refs":[{"kind":"memory","id":"\(memoryID.uuidString)"},{"kind":"somethingNew","id":"x"}]},
        {"id":"horoscope","kind":"horoscope","title":"Stars","body":"…","refs":[]}]}}
        """) { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/me/brief")
            XCTAssertNil(request.url?.query)
        }
        let response = try await client.brief(date: nil)
        let brief = try XCTUnwrap(response.brief)
        XCTAssertEqual(brief.id, id)
        XCTAssertEqual(brief.cards.map(\.kind), [.openLoops, .toRevisit, .unknown])
        XCTAssertNil(brief.cards[1].why)
        XCTAssertEqual(brief.cards[1].refs.map(\.kind), [.memory, .unknown])
        XCTAssertEqual(brief.endNote, "That's it for today.")
    }

    func testNoBriefIsNullNotAnError() async throws {
        let client = BriefHTTPClient(client: makeHTTPClient())
        respond(200, #"{"brief":null}"#)
        let response = try await client.brief(date: "2026-10-19")
        XCTAssertNil(response.brief)
    }

    func testFeedbackAcceptsAnEmpty204() async throws {
        let client = BriefHTTPClient(client: makeHTTPClient())
        respond(204, "") { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.path.hasSuffix("/cards/openLoops/feedback") == true)
        }
        try await client.feedback(briefID: UUID(), cardID: "openLoops", action: .dismiss)
    }

    // MARK: - Commitments

    func testCommitmentsListAndPatchPaths() async throws {
        XCTAssertEqual(CommitmentsEndpoints.List(state: .open).path, "/v1/me/commitments?state=open")
        XCTAssertEqual(CommitmentsEndpoints.List(state: .all).path, "/v1/me/commitments?state=all")
        let id = try XCTUnwrap(UUID(uuidString: "0A000000-0000-4000-8000-000000000001"))
        let update = CommitmentsEndpoints.Update(id: id, state: .dropped)
        XCTAssertEqual(update.path, "/v1/me/commitments/0a000000-0000-4000-8000-000000000001")
        XCTAssertEqual(update.method, .patch)
        let body = try JSONEncoder().encode(AnyEncodable(try XCTUnwrap(update.body)))
        XCTAssertEqual(String(bytes: body, encoding: .utf8), #"{"state":"dropped"}"#)
    }

    func testCommitmentsDecode() async throws {
        let client = CommitmentsHTTPClient(client: makeHTTPClient())
        let id = UUID()
        respond(200, """
        {"items":[{"id":"\(id.uuidString)","text":"Send Ana the deck","dueAt":"2026-10-22T12:00:00Z",
        "state":"open","surfacedCount":2,"createdAt":"2026-10-15T09:00:00Z"},
        {"id":"\(UUID().uuidString)","text":"x","state":"snoozed","surfacedCount":0,
        "createdAt":"2026-10-15T09:00:00Z"}]}
        """) { request in
            XCTAssertEqual(request.url?.query, "state=open")
        }
        let items = try await client.commitments(state: .open).items
        XCTAssertEqual(items.first?.id, id)
        XCTAssertEqual(items.first?.surfacedCount, 2)
        XCTAssertNotNil(items.first?.dueAt)
        XCTAssertEqual(items.map(\.state), [.open, .unknown])
    }

    func testAConflictingReopenThrowsA409() async throws {
        let client = CommitmentsHTTPClient(client: makeHTTPClient())
        respond(409, #"{"error":true,"reason":"duplicate"}"#)
        do {
            _ = try await client.update(id: UUID(), state: .open)
            XCTFail("expected a 409")
        } catch let APIError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 409)
            XCTAssertEqual(CommitmentCopy.failureMessage(for: APIError.httpError(statusCode: statusCode, data: Data())), CommitmentCopy.alreadyOpen)
        }
    }
}
