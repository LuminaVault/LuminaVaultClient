import Foundation

protocol AgentConnectionsClientProtocol: Sendable {
    func list() async throws -> [AgentConnectionDTO]
    func preview(clientKind: AgentClientKind) async throws -> AgentConnectionSetupDTO
    func issue(name: String, clientKind: AgentClientKind) async throws -> AgentConnectionIssuedResponse
    func revoke(id: UUID) async throws
}

final class AgentConnectionsHTTPClient: AgentConnectionsClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func list() async throws -> [AgentConnectionDTO] {
        try await client.execute(AgentConnectionsEndpoints.List()).connections
    }

    func preview(clientKind: AgentClientKind) async throws -> AgentConnectionSetupDTO {
        try await client.execute(AgentConnectionsEndpoints.Preview(clientKind: clientKind))
    }

    func issue(name: String, clientKind: AgentClientKind) async throws -> AgentConnectionIssuedResponse {
        try await client.execute(AgentConnectionsEndpoints.Issue(name: name, clientKind: clientKind))
    }

    func revoke(id: UUID) async throws {
        _ = try await client.execute(AgentConnectionsEndpoints.Revoke(id: id))
    }
}
