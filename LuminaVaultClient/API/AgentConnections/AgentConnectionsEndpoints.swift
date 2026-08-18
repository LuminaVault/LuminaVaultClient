import Foundation
import LuminaVaultShared

enum AgentConnectionsEndpoints {
    struct List: Endpoint {
        typealias Response = AgentConnectionsListResponse
        var path: String { "/v1/me/agent-connections" }
        var method: HTTPMethod { .get }
    }

    struct Preview: Endpoint {
        typealias Response = AgentConnectionSetupDTO
        let clientKind: AgentClientKind
        var path: String { "/v1/me/agent-connections/preview?clientKind=\(clientKind.rawValue)" }
        var method: HTTPMethod { .get }
    }

    struct Issue: Endpoint {
        typealias Response = AgentConnectionIssuedResponse
        let name: String
        let clientKind: AgentClientKind
        var path: String { "/v1/me/agent-connections" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? {
            AgentConnectionIssueRequest(name: name, clientKind: clientKind)
        }
    }

    struct Revoke: Endpoint {
        typealias Response = EmptyResponse
        let id: UUID
        var path: String { "/v1/me/agent-connections/\(id.uuidString)" }
        var method: HTTPMethod { .delete }
    }
}
