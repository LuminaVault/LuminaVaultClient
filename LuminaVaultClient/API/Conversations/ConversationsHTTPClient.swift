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
    func prepare(conversationID: UUID, request: ConversationPrepareRequest) async throws -> ConversationPrepareResponse
    func commit(conversationID: UUID, request: ConversationCommitRequest) async throws -> ConversationCommitResponse
    func streamReply(
        conversationID: UUID,
        request: MessageStreamRequest,
    ) -> AsyncThrowingStream<QueryStreamEvent, any Error>
}

extension ConversationsClientProtocol {
    func prepare(conversationID _: UUID, request _: ConversationPrepareRequest) async throws -> ConversationPrepareResponse {
        throw APIError.decodingFailed(LocalConversationClientError.unsupported)
    }

    func commit(conversationID _: UUID, request _: ConversationCommitRequest) async throws -> ConversationCommitResponse {
        throw APIError.decodingFailed(LocalConversationClientError.unsupported)
    }
}

private enum LocalConversationClientError: Error { case unsupported }

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

    func prepare(conversationID: UUID, request: ConversationPrepareRequest) async throws -> ConversationPrepareResponse {
        try await client.execute(ConversationsEndpoints.Prepare(conversationID: conversationID, request: request))
    }

    func commit(conversationID: UUID, request: ConversationCommitRequest) async throws -> ConversationCommitResponse {
        try await client.execute(ConversationsEndpoints.Commit(conversationID: conversationID, request: request))
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
