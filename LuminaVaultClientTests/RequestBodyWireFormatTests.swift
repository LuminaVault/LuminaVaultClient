// LuminaVaultClient/LuminaVaultClientTests/RequestBodyWireFormatTests.swift
//
// Guard against the encoder/decoder mismatch that broke chat: the server
// decodes every request body with Hummingbird's default decoder (camelCase
// keys, ISO-8601 dates, no `convertFromSnakeCase`). Any client endpoint that
// encodes with `.convertToSnakeCase` therefore either 400s on a required
// multi-word key ("Coding key `newPath` not found.") or silently drops an
// optional one (`accuracyM`, `placeName`).
//
// Each test encodes the endpoint's body with the endpoint's own encoder and
// decodes it back with the server's configuration. Add a case here for
// every endpoint whose body has a multi-word or acronym-suffixed property.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

final class RequestBodyWireFormatTests: XCTestCase {
    /// Mirrors `AppRequestContext`'s request decoder on the server.
    private static var serverDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func roundTrip<E: Endpoint, Body: Decodable>(
        _ endpoint: E,
        as _: Body.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Body {
        let body = try XCTUnwrap(endpoint.body, "endpoint has no body", file: file, line: line)
        let data = try endpoint.encoder.encode(AnyEncodable(body))
        do {
            return try Self.serverDecoder.decode(Body.self, from: data)
        } catch {
            XCTFail(
                "server-side decoder rejects \(endpoint.method.rawValue) \(endpoint.path) body: \(error)",
                file: file,
                line: line
            )
            throw error
        }
    }

    func testVaultMoveBodyKeepsNewPathCamelCase() throws {
        let decoded = try roundTrip(
            VaultEndpoints.MoveFile(from: "Inbox/draft.md", to: "Stocks/draft.md"),
            as: VaultMoveRequest.self
        )
        XCTAssertEqual(decoded.path, "Inbox/draft.md")
        XCTAssertEqual(decoded.newPath, "Stocks/draft.md")
    }

    func testMemoryUpsertBodyKeepsGeoFieldsCamelCase() throws {
        let decoded = try roundTrip(
            MemoryEndpoints.Upsert(
                request: MemoryUpsertRequest(
                    content: "Bought NVDA on the dip",
                    lat: 38.7139,
                    lng: -9.1394,
                    accuracyM: 12.5,
                    placeName: "Café A Brasileira, Lisbon"
                ),
                spaceID: nil
            ),
            as: MemoryUpsertRequest.self
        )
        XCTAssertEqual(decoded.content, "Bought NVDA on the dip")
        XCTAssertEqual(decoded.accuracyM, 12.5, "accuracyM used to be dropped on the wire as accuracy_m")
        XCTAssertEqual(decoded.placeName, "Café A Brasileira, Lisbon", "placeName used to be dropped on the wire as place_name")
    }

    func testHealthIngestBodyKeepsRecordedAtCamelCase() throws {
        let recordedAt = Date(timeIntervalSince1970: 1_789_000_000)
        let decoded = try roundTrip(
            HealthEndpoints.Ingest(events: [
                HealthEventInput(
                    type: "steps",
                    recordedAt: recordedAt,
                    valueNumeric: 8_412,
                    unit: "count",
                    source: "apple_health"
                ),
            ]),
            as: HealthIngestRequest.self
        )
        XCTAssertEqual(decoded.events.count, 1)
        XCTAssertEqual(decoded.events.first?.recordedAt, recordedAt)
        XCTAssertEqual(decoded.events.first?.valueNumeric, 8_412)
    }

    /// `StreamingEndpoint` is a separate protocol from `Endpoint`, but its
    /// body reaches the same server decoder, so it needs the same guard.
    private func roundTripStream<E: StreamingEndpoint, Body: Decodable>(
        _ endpoint: E,
        as _: Body.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Body {
        let body = try XCTUnwrap(endpoint.body, "endpoint has no body", file: file, line: line)
        let data = try endpoint.encoder.encode(AnyEncodable(body))
        do {
            return try Self.serverDecoder.decode(Body.self, from: data)
        } catch {
            XCTFail(
                "server-side decoder rejects \(endpoint.method.rawValue) \(endpoint.path) body: \(error)",
                file: file,
                line: line
            )
            throw error
        }
    }

    // MARK: - Chat agent turns (Shared 5.18.0)

    /// `agentMode` and every attachment property are multi-word, which is
    /// exactly the shape that broke chat before: encoded snake_case they
    /// either 400 on a required key or vanish silently as an optional one.
    func testStreamReplyAgentModeAndAttachmentsSurviveTheServerDecoder() throws {
        let endpoint = ConversationsEndpoints.StreamReply(
            conversationID: UUID(),
            request: MessageStreamRequest(
                content: "summarise these",
                agentMode: ChatAgentModeDTO.force,
                attachments: [
                    ChatAttachmentDTO(kind: .text, name: "notes.txt", text: "body"),
                    ChatAttachmentDTO(kind: .vaultFile, name: "plan.md", vaultPath: "notes/plan.md"),
                    ChatAttachmentDTO(kind: .link, name: "spec", url: "https://example.com"),
                ]
            )
        )
        let decoded = try roundTripStream(endpoint, as: MessageStreamRequest.self)

        XCTAssertEqual(decoded.content, "summarise these")
        XCTAssertEqual(decoded.agentMode, ChatAgentModeDTO.force)
        XCTAssertEqual(decoded.attachments?.count, 3)
        // The one that would silently vanish under a snake_case encoder.
        XCTAssertEqual(decoded.attachments?[1].vaultPath, "notes/plan.md")
        XCTAssertEqual(decoded.attachments?[2].url, "https://example.com")
    }

    /// Omitting the new fields must still decode, so a build that never sets
    /// them behaves exactly as it did before they existed.
    func testStreamReplyWithoutTheNewFieldsStillDecodes() throws {
        let endpoint = ConversationsEndpoints.StreamReply(
            conversationID: UUID(),
            request: MessageStreamRequest(content: "hello")
        )
        let decoded = try roundTripStream(endpoint, as: MessageStreamRequest.self)

        XCTAssertNil(decoded.agentMode)
        XCTAssertNil(decoded.attachments)
    }

    /// The gate that lets older builds keep working: the server withholds the
    /// run pointer from any client that has not declared this.
    func testStreamReplyDeclaresTheHermesRunCapability() {
        let endpoint = ConversationsEndpoints.StreamReply(
            conversationID: UUID(),
            request: MessageStreamRequest(content: "hello")
        )
        XCTAssertEqual(endpoint.additionalHeaders["X-LV-Client-Caps"], "chat.hermes_run")
    }
}
