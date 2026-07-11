// LuminaVaultClient/LuminaVaultClient/API/Conversations/ConversationsEndpoints.swift
//
// HER-269 — server contract:
//   POST   /v1/conversations                          -> ConversationDTO
//   GET    /v1/conversations                          -> ConversationListResponse
//   GET    /v1/conversations/:id                      -> ConversationDetailResponse
//   DELETE /v1/conversations/:id                      -> 204
//   POST   /v1/conversations/:id/messages/stream      -> text/event-stream of QueryStreamEvent
//
// The stream endpoint is the only one that routes through the BYO Hermes
// gateway when a verified config exists (server-side, via
// HermesLLMStreamService / RoutedHermesLLMService). Falls back to the
// platform default model otherwise.
import Foundation

enum ConversationsEndpoints {
    private static var snakeCaseEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    struct Create: Endpoint {
        typealias Response = ConversationDTO
        let request: ConversationCreateRequest
        var path: String { "/v1/conversations" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
        var encoder: JSONEncoder { ConversationsEndpoints.snakeCaseEncoder }
    }

    struct List: Endpoint {
        typealias Response = ConversationListResponse
        var path: String { "/v1/conversations" }
        var method: HTTPMethod { .get }
    }

    struct Get: Endpoint {
        typealias Response = ConversationDetailResponse
        let id: UUID
        var path: String { "/v1/conversations/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .get }
    }

    struct Delete: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "/v1/conversations/\(id.uuidString.lowercased())" }
        var method: HTTPMethod { .delete }
    }

    struct Prepare: Endpoint {
        typealias Response = ConversationPrepareResponse
        let conversationID: UUID
        let request: ConversationPrepareRequest
        var path: String { "/v1/conversations/\(conversationID.uuidString.lowercased())/messages/prepare" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    struct Commit: Endpoint {
        typealias Response = ConversationCommitResponse
        let conversationID: UUID
        let request: ConversationCommitRequest
        var path: String { "/v1/conversations/\(conversationID.uuidString.lowercased())/messages/commit" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
    }

    /// SSE stream of `QueryStreamEvent`. Consume via
    /// `BaseHTTPClient.executeStreamWithRefresh`.
    struct StreamReply: StreamingEndpoint {
        typealias Event = QueryStreamEvent
        let conversationID: UUID
        let request: MessageStreamRequest
        var path: String { "/v1/conversations/\(conversationID.uuidString.lowercased())/messages/stream" }
        var method: HTTPMethod { .post }
        var body: (any Encodable & Sendable)? { request }
        var encoder: JSONEncoder { ConversationsEndpoints.snakeCaseEncoder }
    }
}
