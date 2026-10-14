import Foundation
import LuminaVaultShared

nonisolated enum AgentConnectionsEndpoints {
    nonisolated struct List: Endpoint {
        typealias Response = AgentConnectionsListResponse
        var path: String { "/v1/me/agent-connections" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct Preview: Endpoint {
        typealias Response = AgentConnectionSetupDTO
        let clientKind: AgentClientKind
        var path: String { "/v1/me/agent-connections/preview?clientKind=\(clientKind.rawValue)" }
        var method: HTTPMethod { .get }
    }

    nonisolated struct Issue: Endpoint {
        typealias Response = AgentConnectionIssuedResponse
        let name: String
        let clientKind: AgentClientKind
        let allowPersonalData: Bool
        let access: AgentConnectionAccess
        var path: String { "/v1/me/agent-connections" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? {
            AgentConnectionIssueRequest(
                name: name,
                clientKind: clientKind,
                allowPersonalData: allowPersonalData,
                access: access
            )
        }
    }

    /// Changes one grant; the field left `nil` is not sent and stays as it is.
    nonisolated struct Update: Endpoint {
        typealias Response = AgentConnectionDTO
        let id: UUID
        let request: AgentConnectionUpdateRequest
        var path: String { "/v1/me/agent-connections/\(id.uuidString)" }
        var method: HTTPMethod { .patch }
        var body: (any Encodable)? { request }
    }

    nonisolated struct Revoke: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "/v1/me/agent-connections/\(id.uuidString)" }
        var method: HTTPMethod { .delete }
    }
}
