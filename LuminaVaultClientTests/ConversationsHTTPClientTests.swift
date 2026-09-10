// LuminaVaultClient/LuminaVaultClientTests/ConversationsHTTPClientTests.swift
//
// Wire format for `/v1/conversations`.
//
// The server decodes request bodies with Hummingbird's default decoder —
// camelCase keys, no snake conversion (`AppRequestContext` does not override
// `requestDecoder`). Every body asserted here is therefore decoded back with
// a plain `JSONDecoder()`: if that fails, the server would 400 with
// "Coding key `X` not found." — which is exactly how `pinnedMemoryIDs`
// (encoded as `pinned_memory_i_ds`) broke chat in TestFlight.
//
// The SSE path cannot be driven through `URLProtocol` (see the note atop
// `BaseHTTPClientSSETests`), so `StreamReply` is asserted at the endpoint
// level: encode its body with its own encoder, decode with the server's.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

final class ConversationsHTTPClientTests: XCTestCase {
    private var base: BaseHTTPClient!
    private var client: ConversationsHTTPClient!

    private static let conversationID = UUID(uuidString: "6B29FC40-CA47-1067-B31D-00DD010662DA")!
    private static let memoryID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!
    private static let spaceID = UUID(uuidString: "16FD2706-8BAF-433B-82EB-8C7FADA847DA")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        base = BaseHTTPClient(session: URLSession(configuration: config))
        client = ConversationsHTTPClient(client: base)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    /// What the server actually decodes with: no key strategy, ISO-8601 dates.
    private static var serverDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static func conversationJSON() -> String {
        """
        {
          "id": "\(conversationID.uuidString)",
          "title": "New conversation",
          "spaceId": "\(spaceID.uuidString)",
          "createdAt": "2026-09-10T16:05:00Z",
          "updatedAt": "2026-09-10T16:05:00Z",
          "pinnedMemoryIDs": ["\(memoryID.uuidString)"],
          "routeOverride": { "provider": "openai", "model": "gpt-4o-mini" }
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

    // MARK: - Create

    func testCreateBodyDecodesWithServerDefaultDecoder() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/conversations")
            XCTAssertEqual(request.httpMethod, "POST")
            do {
                let decoded = try Self.serverDecoder.decode(
                    ConversationCreateRequest.self,
                    from: request.bodyData() ?? Data()
                )
                XCTAssertEqual(decoded.title, "Stocks")
                XCTAssertEqual(decoded.spaceId, Self.spaceID)
                XCTAssertEqual(decoded.pinnedMemoryIDs, [Self.memoryID])
                XCTAssertEqual(decoded.routeOverride?.provider, .openai)
                XCTAssertEqual(decoded.routeOverride?.model, "gpt-4o-mini")
            } catch {
                XCTFail("server-side decoder rejects the create body: \(error)")
            }
            return Self.ok(request, Self.conversationJSON())
        }

        let dto = try await client.create(
            ConversationCreateRequest(
                title: "Stocks",
                spaceId: Self.spaceID,
                pinnedMemoryIDs: [Self.memoryID],
                routeOverride: RouterModelRouteDTO(provider: .openai, model: "gpt-4o-mini")
            )
        )
        XCTAssertEqual(dto.id, Self.conversationID)
        XCTAssertEqual(dto.pinnedMemoryIDs, [Self.memoryID])
    }

    // MARK: - StreamReply

    func testStreamReplyBodyCarriesMultiModelInCamelCase() throws {
        let endpoint = ConversationsEndpoints.StreamReply(
            conversationID: Self.conversationID,
            request: MessageStreamRequest(
                content: "What patterns do I have in my Stocks space lately?",
                multiModel: ChatMultiModelOptionsDTO(enabled: true, strategy: .debate)
            )
        )
        let body = try XCTUnwrap(endpoint.body)
        let data = try endpoint.encoder.encode(AnyEncodable(body))

        let decoded = try Self.serverDecoder.decode(MessageStreamRequest.self, from: data)
        XCTAssertEqual(decoded.content, "What patterns do I have in my Stocks space lately?")
        XCTAssertEqual(decoded.multiModel?.enabled, true, "multiModel must survive the wire — the Multi-Model toggle is inert otherwise")
        XCTAssertEqual(decoded.multiModel?.strategy, .debate)
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
        return data
    }
}
