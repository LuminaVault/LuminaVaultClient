// LuminaVaultClient/LuminaVaultClient/API/Conversations/ConversationsHTTPClient.swift
//
// HER-269 — concrete client for the Conversations endpoints. Stream
// reply uses `executeStreamWithRefresh` so a 401 on connect drives a
// single token refresh + retry. Mid-stream 401s propagate to the
// caller (cannot be transparently retried — bytes already delivered).
import Foundation

protocol ConversationsClientProtocol: Sendable {
    func create(_ request: ConversationCreateRequest) async throws -> ConversationDTO
    func list() async throws -> ConversationListResponse
    func get(_ id: UUID) async throws -> ConversationDetailResponse
    func delete(_ id: UUID) async throws
    func streamReply(
        conversationID: UUID,
        request: MessageStreamRequest,
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error>
}

final class ConversationsHTTPClient: ConversationsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func create(_ request: ConversationCreateRequest) async throws -> ConversationDTO {
        try await client.execute(ConversationsEndpoints.Create(request: request))
    }

    func list() async throws -> ConversationListResponse {
        try await client.execute(ConversationsEndpoints.List())
    }

    func get(_ id: UUID) async throws -> ConversationDetailResponse {
        try await client.execute(ConversationsEndpoints.Get(id: id))
    }

    func delete(_ id: UUID) async throws {
        _ = try await client.execute(ConversationsEndpoints.Delete(id: id))
    }

    func streamReply(
        conversationID: UUID,
        request: MessageStreamRequest,
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error> {
        client.executeStreamWithRefresh(
            ConversationsEndpoints.StreamReply(
                conversationID: conversationID,
                request: request,
            ),
        )
    }
}
