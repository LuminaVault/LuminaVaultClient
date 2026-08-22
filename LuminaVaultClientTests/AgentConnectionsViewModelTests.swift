@testable import LuminaVaultClient
import Foundation
import XCTest

@MainActor
final class AgentConnectionsViewModelTests: XCTestCase {
    func testCreateRequiresAName() async {
        let client = MockAgentConnectionsClient()
        let sut = AgentConnectionsViewModel(client: client)
        sut.nameInput = "   "
        await sut.create()
        XCTAssertTrue(client.issueCalls.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testCreateStoresTheIssuedTokenOnceAndReloadsTheList() async {
        let client = MockAgentConnectionsClient()
        let issued = Self.sampleIssued()
        client.issueResult = issued
        client.listResult = [issued.connection]
        let sut = AgentConnectionsViewModel(client: client)
        sut.nameInput = "laptop"
        sut.selectedKind = .claudeCode
        await sut.create()
        XCTAssertEqual(client.issueCalls.count, 1)
        XCTAssertEqual(sut.issued?.token, issued.token)
        XCTAssertEqual(sut.connections.map(\.id), [issued.connection.id])
        XCTAssertTrue(sut.nameInput.isEmpty)
    }

    func testRevokeDropsTheRowAndClearsAMatchingIssuedToken() async {
        let client = MockAgentConnectionsClient()
        let issued = Self.sampleIssued()
        client.listResult = [issued.connection]
        let sut = AgentConnectionsViewModel(client: client)
        sut.issued = issued
        sut.connections = [issued.connection]
        client.listResult = []
        await sut.revoke(issued.connection)
        XCTAssertEqual(client.revokedIDs, [issued.connection.id])
        XCTAssertNil(sut.issued)
        XCTAssertTrue(sut.connections.isEmpty)
    }

    private static func sampleIssued() -> AgentConnectionIssuedResponse {
        let connection = AgentConnectionDTO(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "laptop",
            clientKind: .claudeCode,
            tokenPrefix: "lv_abcd1234",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let setup = AgentConnectionSetupDTO(
            kind: .claudeCode,
            url: "https://api.example.com/v1/mcp",
            token: "lv_SECRET",
            configLabel: "one command",
            configLang: "bash",
            config: "claude mcp add",
            prompt: "Add an MCP server"
        )
        return AgentConnectionIssuedResponse(connection: connection, token: "lv_SECRET", setup: setup)
    }
}

final class MockAgentConnectionsClient: AgentConnectionsClientProtocol, @unchecked Sendable {
    var listResult: [AgentConnectionDTO] = []
    var previewResult = AgentConnectionSetupDTO(
        kind: .claudeCode,
        url: "https://api.example.com/v1/mcp",
        token: "PASTE_YOUR_KEY_HERE__create_one_below",
        configLabel: "one command",
        configLang: "bash",
        config: "claude mcp add",
        prompt: "preview"
    )
    var issueResult: AgentConnectionIssuedResponse?
    var issueCalls: [(String, AgentClientKind)] = []
    var revokedIDs: [UUID] = []

    func list() async throws -> [AgentConnectionDTO] { listResult }

    func preview(clientKind: AgentClientKind) async throws -> AgentConnectionSetupDTO {
        previewResult
    }

    func issue(name: String, clientKind: AgentClientKind) async throws -> AgentConnectionIssuedResponse {
        issueCalls.append((name, clientKind))
        if let issueResult { return issueResult }
        throw URLError(.badServerResponse)
    }

    func revoke(id: UUID) async throws {
        revokedIDs.append(id)
    }
}
