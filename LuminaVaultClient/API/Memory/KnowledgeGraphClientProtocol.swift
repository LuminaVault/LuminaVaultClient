import Foundation
import LuminaVaultShared

protocol KnowledgeGraphClientProtocol: Sendable {
    func fetchGraph(limit: Int, minimumConfidence: Double) async throws -> KnowledgeGraphResponse
    func reason(query: String, maxDepth: Int, limit: Int) async throws -> ReasoningQueryResponse
    func explain(from: UUID, to: UUID, maxDepth: Int) async throws -> ConnectionExplanationResponse
    func review(edgeID: UUID, action: KnowledgeReviewAction, note: String?) async throws -> KnowledgeEdgeDTO
}

enum KnowledgeReviewAction: String, Sendable {
    case confirm
    case dismiss
}
