// LuminaVaultClient/LuminaVaultClient/API/Chat/ChatEndpoints.swift
//
// HER-107 — non-streaming chat. Hits LuminaVaultServer's BYO-Hermes-aware
// `POST /v1/llm/chat` (LLMController.swift). When the user has a
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
        // Chat never slides the app-root paywall over itself. The whole
        // `/v1/conversations` group is gated on `.memoryQuery`, listing
        // included, so a 402 anywhere here would throw a modal over the Chats
        // tab. A chat failure belongs inline in the conversation, next to the
        // turn that failed, with an explicit Upgrade button the user chooses
        // to tap — see `ChatView.ErrorRow`.
        var presentsPaywallOn402: Bool { false }
        typealias Response = ChatResponse
        let request: ChatRequest
        // `/v1/chat` registers only `GET /v1/chat/inbox`; the completions
        // handler lives on the `/v1/llm` group. Posting to
        // `/v1/chat/completions` 404'd with an empty body, which the client
        // could only render as "Server error (404)." in Cloud chat mode.
        var path: String { "/v1/llm/chat" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { request }
        var encoder: JSONEncoder { ChatEndpoints.snakeCaseEncoder }
    }
}
