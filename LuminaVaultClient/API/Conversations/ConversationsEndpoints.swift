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
//
// Wire is camelCase. The server decodes request bodies with Hummingbird's
// default decoder (no `convertFromSnakeCase`), so every endpoint here uses
// the protocol-default `JSONEncoder()`. A `.convertToSnakeCase` encoder
// used to live here: it sent `pinnedMemoryIDs` as `pinned_memory_i_ds`,
// which the server answered with 400 "Coding key `pinnedMemoryIDs` not
// found." on every new chat, and quietly dropped `multiModel` (sent as
// `multi_model`) on the stream request. `ConversationsHTTPClientTests`
// decodes each body with the server's decoder to keep it that way.
import Foundation

enum ConversationsEndpoints {
    struct Create: Endpoint {
        // Chat never slides the app-root paywall over itself. The whole
        // `/v1/conversations` group is gated on `.memoryQuery`, listing
        // included, so a 402 anywhere here would throw a modal over the Chats
        // tab. A chat failure belongs inline in the conversation, next to the
        // turn that failed, with an explicit Upgrade button the user chooses
        // to tap — see `ChatView.ErrorRow`.
        var presentsPaywallOn402: Bool { false }
        typealias Response = ConversationDTO
        let request: ConversationCreateRequest
        var path: String {
            "/v1/conversations"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    struct List: Endpoint {
        // Chat never slides the app-root paywall over itself. The whole
        // `/v1/conversations` group is gated on `.memoryQuery`, listing
        // included, so a 402 anywhere here would throw a modal over the Chats
        // tab. A chat failure belongs inline in the conversation, next to the
        // turn that failed, with an explicit Upgrade button the user chooses
        // to tap — see `ChatView.ErrorRow`.
        var presentsPaywallOn402: Bool { false }
        typealias Response = ConversationListResponse
        var path: String {
            "/v1/conversations"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct Get: Endpoint {
        // Chat never slides the app-root paywall over itself. The whole
        // `/v1/conversations` group is gated on `.memoryQuery`, listing
        // included, so a 402 anywhere here would throw a modal over the Chats
        // tab. A chat failure belongs inline in the conversation, next to the
        // turn that failed, with an explicit Upgrade button the user chooses
        // to tap — see `ChatView.ErrorRow`.
        var presentsPaywallOn402: Bool { false }
        typealias Response = ConversationDetailResponse
        let id: UUID
        var path: String {
            "/v1/conversations/\(id.uuidString.lowercased())"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct Delete: Endpoint {
        // Chat never slides the app-root paywall over itself. The whole
        // `/v1/conversations` group is gated on `.memoryQuery`, listing
        // included, so a 402 anywhere here would throw a modal over the Chats
        // tab. A chat failure belongs inline in the conversation, next to the
        // turn that failed, with an explicit Upgrade button the user chooses
        // to tap — see `ChatView.ErrorRow`.
        var presentsPaywallOn402: Bool { false }
        typealias Response = EmptyResponse
        let id: UUID
        var path: String {
            "/v1/conversations/\(id.uuidString.lowercased())"
        }

        var method: HTTPMethod {
            .delete
        }
    }

    struct Prepare: Endpoint {
        // Chat never slides the app-root paywall over itself. The whole
        // `/v1/conversations` group is gated on `.memoryQuery`, listing
        // included, so a 402 anywhere here would throw a modal over the Chats
        // tab. A chat failure belongs inline in the conversation, next to the
        // turn that failed, with an explicit Upgrade button the user chooses
        // to tap — see `ChatView.ErrorRow`.
        var presentsPaywallOn402: Bool { false }
        typealias Response = ConversationPrepareResponse
        let conversationID: UUID
        let request: ConversationPrepareRequest
        var path: String {
            "/v1/conversations/\(conversationID.uuidString.lowercased())/messages/prepare"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    struct Commit: Endpoint {
        // Chat never slides the app-root paywall over itself. The whole
        // `/v1/conversations` group is gated on `.memoryQuery`, listing
        // included, so a 402 anywhere here would throw a modal over the Chats
        // tab. A chat failure belongs inline in the conversation, next to the
        // turn that failed, with an explicit Upgrade button the user chooses
        // to tap — see `ChatView.ErrorRow`.
        var presentsPaywallOn402: Bool { false }
        typealias Response = ConversationCommitResponse
        let conversationID: UUID
        let request: ConversationCommitRequest
        var path: String {
            "/v1/conversations/\(conversationID.uuidString.lowercased())/messages/commit"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    struct CancelPreparedExecution: Endpoint {
        // Chat never slides the app-root paywall over itself. The whole
        // `/v1/conversations` group is gated on `.memoryQuery`, listing
        // included, so a 402 anywhere here would throw a modal over the Chats
        // tab. A chat failure belongs inline in the conversation, next to the
        // turn that failed, with an explicit Upgrade button the user chooses
        // to tap — see `ChatView.ErrorRow`.
        var presentsPaywallOn402: Bool { false }
        typealias Response = EmptyResponse
        let conversationID: UUID
        let executionID: UUID
        var path: String {
            "/v1/conversations/\(conversationID.uuidString.lowercased())/local-executions/\(executionID.uuidString.lowercased())"
        }

        var method: HTTPMethod {
            .delete
        }
    }

    /// SSE stream of `QueryStreamEvent`. Consume via
    /// `BaseHTTPClient.executeStreamWithRefresh`.
    struct StreamReply: StreamingEndpoint {
        // Chat never slides the app-root paywall over itself. The whole
        // `/v1/conversations` group is gated on `.memoryQuery`, listing
        // included, so a 402 anywhere here would throw a modal over the Chats
        // tab. A chat failure belongs inline in the conversation, next to the
        // turn that failed, with an explicit Upgrade button the user chooses
        // to tap — see `ChatView.ErrorRow`.
        var presentsPaywallOn402: Bool { false }
        typealias Event = QueryStreamEvent
        let conversationID: UUID
        let request: MessageStreamRequest
        var path: String {
            "/v1/conversations/\(conversationID.uuidString.lowercased())/messages/stream"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable & Sendable)? {
            request
        }
    }
}
