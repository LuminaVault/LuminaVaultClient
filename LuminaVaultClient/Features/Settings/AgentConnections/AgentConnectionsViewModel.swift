import Foundation

@Observable
@MainActor
final class AgentConnectionsViewModel {
    var connections: [AgentConnectionDTO] = []
    var preview: AgentConnectionSetupDTO?
    var issued: AgentConnectionIssuedResponse?
    var nameInput = ""
    var selectedKind: AgentClientKind = .claudeCode
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
            let issued = try await client.issue(name: name, clientKind: selectedKind)
            self.issued = issued
            nameInput = ""
            connections = try await client.list()
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
