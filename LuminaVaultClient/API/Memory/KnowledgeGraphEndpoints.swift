import Foundation
import LuminaVaultShared

nonisolated enum KnowledgeGraphEndpoints {
    nonisolated struct Reason: Endpoint {
        typealias Response = ReasoningQueryResponse
        let request: ReasoningQueryRequest
        var path: String {
            "/v1/knowledge/reason"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    nonisolated struct ReasonStream: StreamingEndpoint {
        typealias Event = ReasoningStreamEventDTO
        let request: ReasoningQueryRequest
        var path: String {
            "/v1/knowledge/reason/stream"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable & Sendable)? {
            request
        }
    }

    nonisolated struct Explain: Endpoint {
        typealias Response = ConnectionExplanationResponse
        let request: ConnectionExplanationRequest
        var path: String {
            "/v1/knowledge/connections/explain"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }

    nonisolated struct Review: Endpoint {
        typealias Response = KnowledgeEdgeDTO
        let edgeID: UUID
        let action: KnowledgeReviewAction
        let request: InferenceReviewRequest
        var path: String {
            "/v1/knowledge/edges/\(edgeID.uuidString.lowercased())/\(action.rawValue)"
        }

        var method: HTTPMethod {
            .post
        }

        var body: (any Encodable)? {
            request
        }
    }
}
