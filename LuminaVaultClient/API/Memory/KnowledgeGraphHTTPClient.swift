import Foundation
import LuminaVaultShared

final class KnowledgeGraphHTTPClient: KnowledgeGraphClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) {
        self.client = client
    }

    func fetchGraph(limit: Int, minimumConfidence: Double) async throws -> KnowledgeGraphResponse {
        try await client.execute(KnowledgeGraphEndpoints.Graph(limit: limit, minimumConfidence: minimumConfidence))
    }

    func reason(query: String, maxDepth: Int, limit: Int) async throws -> ReasoningQueryResponse {
        try await client.execute(KnowledgeGraphEndpoints.Reason(
            request: ReasoningQueryRequest(query: query, maxDepth: maxDepth, limit: limit)
        ))
    }

    func reasonStream(
        query: String,
        maxDepth: Int,
        limit: Int
    ) -> AsyncThrowingStream<ReasoningStreamEventDTO, any Error> {
        client.executeStreamWithRefresh(KnowledgeGraphEndpoints.ReasonStream(
            request: ReasoningQueryRequest(query: query, maxDepth: maxDepth, limit: limit)
        ))
    }

    func explain(from: UUID, to: UUID, maxDepth: Int) async throws -> ConnectionExplanationResponse {
        try await client.execute(KnowledgeGraphEndpoints.Explain(
            request: ConnectionExplanationRequest(fromNodeID: from, toNodeID: to, maxDepth: maxDepth)
        ))
    }

    func review(edgeID: UUID, action: KnowledgeReviewAction, note: String?) async throws -> KnowledgeEdgeDTO {
        try await client.execute(KnowledgeGraphEndpoints.Review(
            edgeID: edgeID,
            action: action,
            request: InferenceReviewRequest(note: note)
        ))
    }
}
