import Foundation

@Observable
@MainActor
final class AgentConnectionsViewModel {
    var connections: [AgentConnectionDTO] = []
    var preview: AgentConnectionSetupDTO?
    var issued: AgentConnectionIssuedResponse?
    var nameInput = ""
    var selectedKind: AgentClientKind = .claudeCode
    /// Grants for the next key. Both start off: a new key can search and read
    /// the vault and nothing more until the user says otherwise.
    var allowPersonalData = false
    var allowWrites = false
    var isLoading = false
    var isWorking = false
    var errorMessage: String?

    private let client: any AgentConnectionsClientProtocol

    init(client: any AgentConnectionsClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let list = client.list()
            async let preview = client.preview(clientKind: selectedKind)
            connections = try await list
            self.preview = try await preview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectKind(_ kind: AgentClientKind) async {
        selectedKind = kind
        do {
            preview = try await client.preview(clientKind: kind)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create() async {
        let name = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Give this connection a name, so you know which one to revoke later."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let issued = try await client.issue(
                name: name,
                clientKind: selectedKind,
                allowPersonalData: allowPersonalData,
                access: allowWrites ? .readWrite : .read
            )
            self.issued = issued
            nameInput = ""
            allowPersonalData = false
            allowWrites = false
            connections = try await client.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPersonalData(_ connection: AgentConnectionDTO, allowed: Bool) async {
        await update(connection, AgentConnectionUpdateRequest(allowPersonalData: allowed))
    }

    func setAccess(_ connection: AgentConnectionDTO, _ access: AgentConnectionAccess) async {
        await update(connection, AgentConnectionUpdateRequest(access: access))
    }

    private func update(_ connection: AgentConnectionDTO, _ request: AgentConnectionUpdateRequest) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await client.update(id: connection.id, request: request)
            connections = connections.map { $0.id == updated.id ? updated : $0 }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissIssued() {
        issued = nil
    }

    func revoke(_ connection: AgentConnectionDTO) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await client.revoke(id: connection.id)
            if issued?.connection.id == connection.id {
                issued = nil
            }
            connections = try await client.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
