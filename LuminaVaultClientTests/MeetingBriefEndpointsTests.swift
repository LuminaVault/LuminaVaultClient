// LuminaVaultClient/LuminaVaultClientTests/MeetingBriefEndpointsTests.swift
//
// Wire shape of the pre-meeting brief: the path the push's event id becomes,
// the server's camelCase JSON and RFC 3339 dates decoding into the shared
// DTOs (a note without a kind included), and a 404 surfacing as one.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class MeetingBriefEndpointsTests: XCTestCase {
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

    func testThePathIsTheEventsBrief() {
        let endpoint = MeetingBriefEndpoints.Get(eventID: MeetingBriefResponse.eventID)
        XCTAssertEqual(endpoint.path, "/v1/calendar/events/0d000000-0000-4000-8000-000000000001/brief")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertNil(endpoint.body)
        XCTAssertFalse(endpoint.presentsPaywallOn402)
    }

    func testTheBriefDecodes() async throws {
        let client = MeetingBriefHTTPClient(client: makeHTTPClient())
        let eventID = MeetingBriefResponse.eventID
        let memoryID = UUID()
        respond(200, """
        {"event":{"id":"\(eventID.uuidString.lowercased())","title":"Design review",
        "startsAt":"2026-10-21T14:30:00Z","endsAt":"2026-10-21T15:00:00Z","location":"Room 4.2",
        "attendees":[{"name":"Ana Silva","email":"ana@example.com"},{"email":"joana@example.com"},{"name":"Rui"}]},
        "memories":[{"id":"\(memoryID.uuidString)","snippet":"Ana wants retention first.","kind":"preference",
        "createdAt":"2026-10-03T12:00:00Z","similarity":0.81},
        {"id":"\(UUID().uuidString)","snippet":"No kind on this one.","createdAt":"2026-09-23T12:00:00Z","similarity":0.6}],
        "why":"You mentioned Ana in 2 notes"}
        """) { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/calendar/events/0d000000-0000-4000-8000-000000000001/brief")
        }

        let brief = try await client.brief(eventID: eventID)

        XCTAssertEqual(brief.event.id, eventID)
        XCTAssertEqual(brief.event.startsAt, Date(timeIntervalSince1970: 1_792_593_000))
        XCTAssertEqual(brief.event.endsAt, Date(timeIntervalSince1970: 1_792_594_800))
        XCTAssertEqual(brief.event.attendees, [
            CalendarAttendeeDTO(name: "Ana Silva", email: "ana@example.com"),
            CalendarAttendeeDTO(name: nil, email: "joana@example.com"),
            CalendarAttendeeDTO(name: "Rui", email: nil),
        ])
        XCTAssertEqual(brief.memories.map(\.id).first, memoryID)
        XCTAssertEqual(brief.memories.map(\.kind), ["preference", nil])
        XCTAssertEqual(brief.memories.first?.similarity, 0.81)
        XCTAssertEqual(brief.why, "You mentioned Ana in 2 notes")
    }

    func testAnEmptyBriefDecodes() async throws {
        let client = MeetingBriefHTTPClient(client: makeHTTPClient())
        respond(200, """
        {"event":{"id":"\(UUID().uuidString)","title":"1:1","startsAt":"2026-10-21T09:00:00Z",
        "endsAt":"2026-10-21T09:30:00Z","attendees":[]},"memories":[],
        "why":"Nothing in your notes matches this meeting yet"}
        """)
        let brief = try await client.brief(eventID: UUID())
        XCTAssertNil(brief.event.location)
        XCTAssertTrue(brief.memories.isEmpty)
    }

    func testAnUnknownEventIsA404() async {
        let client = MeetingBriefHTTPClient(client: makeHTTPClient())
        respond(404, #"{"error":{"code":"not_found","message":"No such event"}}"#)
        do {
            _ = try await client.brief(eventID: UUID())
            XCTFail("expected a 404")
        } catch let APIError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 404)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
