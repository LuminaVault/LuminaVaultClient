import Foundation

protocol AgentConnectionsClientProtocol: Sendable {
    func list() async throws -> [AgentConnectionDTO]
    func preview(clientKind: AgentClientKind) async throws -> AgentConnectionSetupDTO
    func issue(
        name: String,
        clientKind: AgentClientKind,
        allowPersonalData: Bool,
        access: AgentConnectionAccess
    ) async throws -> AgentConnectionIssuedResponse
    func update(id: UUID, request: AgentConnectionUpdateRequest) async throws -> AgentConnectionDTO
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

    func issue(
        name: String,
        clientKind: AgentClientKind,
        allowPersonalData: Bool,
        access: AgentConnectionAccess
    ) async throws -> AgentConnectionIssuedResponse {
        try await client.execute(AgentConnectionsEndpoints.Issue(
            name: name,
            clientKind: clientKind,
            allowPersonalData: allowPersonalData,
            access: access
        ))
    }

    func update(id: UUID, request: AgentConnectionUpdateRequest) async throws -> AgentConnectionDTO {
        try await client.execute(AgentConnectionsEndpoints.Update(id: id, request: request))
    }

    func revoke(id: UUID) async throws {
        _ = try await client.execute(AgentConnectionsEndpoints.Revoke(id: id))
    }
}
