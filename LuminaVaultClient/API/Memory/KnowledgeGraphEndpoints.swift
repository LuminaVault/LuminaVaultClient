import Foundation
import LuminaVaultShared

nonisolated enum KnowledgeGraphEndpoints {
    nonisolated struct Graph: Endpoint {
        typealias Response = KnowledgeGraphResponse
        let limit: Int
        let minimumConfidence: Double
        var path: String {
            "/v1/knowledge/graph?limit=\(limit)&minimumConfidence=\(minimumConfidence)"
        }

        var method: HTTPMethod {
            .get
        }

        // The Brain tab loads this on appear. A 402 here must not slide the
        // app-root paywall over whatever the user was looking at — that is
        // what made opening Brain "show an empty sheet". The view model
        // renders the failure in its own error state instead.
        var presentsPaywallOn402: Bool { false }
    }

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
