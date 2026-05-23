// LuminaVaultClient/LuminaVaultClient/API/Chat/ChatEndpoints.swift
//
// HER-107 — non-streaming chat. Hits LuminaVaultServer's BYO-Hermes-aware
// `POST /v1/chat/completions` (LLMController.swift). When the user has a
// verified Hermes Gateway config, the server forwards the request to
// their stored baseUrl + Authorization. Otherwise it routes through the
// platform's default LLM provider.
//
// Distinct from `ConversationsEndpoints.StreamReply`, which is
// memory-grounded and streams `QueryStreamEvent` over SSE. This one is
// "Hermes-thinks-fresh" — no memory retrieval, no streaming, single
// JSON response.
import Foundation

enum ChatEndpoints {
    private static var snakeCaseEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    struct Completions: Endpoint {
        typealias Response = ChatResponse
        let request: ChatRequest
        var path: String { "/v1/chat/completions" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
        var encoder: JSONEncoder { ChatEndpoints.snakeCaseEncoder }
    }
}
