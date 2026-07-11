import Foundation
import LuminaVaultShared

enum KnowledgeGraphEndpoints {
    struct Graph: Endpoint {
        typealias Response = KnowledgeGraphResponse
        let limit: Int
        let minimumConfidence: Double
        var path: String {
            "/v1/knowledge/graph?limit=\(limit)&minimumConfidence=\(minimumConfidence)"
        }

        var method: HTTPMethod {
            .get
        }
    }

    struct Reason: Endpoint {
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

    struct Explain: Endpoint {
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

    struct Review: Endpoint {
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
