// LuminaVaultClient/LuminaVaultClient/API/Chat/ChatHTTPClient.swift
//
// HER-107 — protocol + concrete client for the non-streaming chat
// endpoint. Paired with `ConversationsHTTPClient.streamReply(...)` as
// the two transports the ChatViewModel toggles between.
import Foundation

protocol ChatClientProtocol: Sendable {
    /// POST /v1/chat/completions — single-turn chat (no memory retrieval).
    /// Routes through the user's BYO Hermes gateway if configured.
    func complete(_ request: ChatRequest) async throws -> ChatResponse
}

final class ChatHTTPClient: ChatClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        try await client.execute(ChatEndpoints.Completions(request: request))
    }
}
