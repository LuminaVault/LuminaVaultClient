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

    func testANewKeyIsReadOnlyWithoutPersonalDataUnlessTheUserTurnsThemOn() async {
        let client = MockAgentConnectionsClient()
        client.issueResult = Self.sampleIssued()
        let sut = AgentConnectionsViewModel(client: client)

        sut.nameInput = "laptop"
        await sut.create()
        XCTAssertEqual(client.issueCalls.last?.2, false)
        XCTAssertEqual(client.issueCalls.last?.3, .read)

        sut.nameInput = "desktop"
        sut.allowPersonalData = true
        sut.allowWrites = true
        await sut.create()
        XCTAssertEqual(client.issueCalls.last?.2, true)
        XCTAssertEqual(client.issueCalls.last?.3, .readWrite)
        // The grants do not carry over to the next key.
        XCTAssertFalse(sut.allowPersonalData)
        XCTAssertFalse(sut.allowWrites)
    }

    func testChangingAccessSendsOnlyAccessAndReplacesTheRow() async {
        let client = MockAgentConnectionsClient()
        let original = Self.sampleIssued().connection
        let updated = AgentConnectionDTO(
            id: original.id, name: original.name, clientKind: original.clientKind,
            tokenPrefix: original.tokenPrefix, createdAt: original.createdAt,
            allowPersonalData: original.allowPersonalData, access: .readWrite
        )
        client.updateResult = updated
        let sut = AgentConnectionsViewModel(client: client)
        sut.connections = [original]

        await sut.setAccess(original, .readWrite)

        XCTAssertEqual(client.updateCalls.count, 1)
        XCTAssertEqual(client.updateCalls.first?.1.access, .readWrite)
        XCTAssertNil(client.updateCalls.first?.1.allowPersonalData)
        XCTAssertEqual(sut.connections.first?.access, .readWrite)
        XCTAssertNil(sut.errorMessage)
    }

    func testChangingPersonalDataSendsOnlyThatGrant() async {
        let client = MockAgentConnectionsClient()
        let original = Self.sampleIssued().connection
        client.updateResult = original
        let sut = AgentConnectionsViewModel(client: client)
        sut.connections = [original]

        await sut.setPersonalData(original, allowed: true)

        XCTAssertEqual(client.updateCalls.first?.1.allowPersonalData, true)
        XCTAssertNil(client.updateCalls.first?.1.access)
    }

    func testAFailedUpdateKeepsTheRowAndShowsTheError() async {
        let client = MockAgentConnectionsClient()
        let original = Self.sampleIssued().connection
        let sut = AgentConnectionsViewModel(client: client)
        sut.connections = [original]

        await sut.setAccess(original, .readWrite)

        XCTAssertEqual(sut.connections.first?.access, original.access)
        XCTAssertNotNil(sut.errorMessage)
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
    var issueCalls: [(String, AgentClientKind, Bool, AgentConnectionAccess)] = []
    var updateCalls: [(UUID, AgentConnectionUpdateRequest)] = []
    var updateResult: AgentConnectionDTO?
    var revokedIDs: [UUID] = []

    func list() async throws -> [AgentConnectionDTO] { listResult }

    func preview(clientKind: AgentClientKind) async throws -> AgentConnectionSetupDTO {
        previewResult
    }

    func issue(
        name: String,
        clientKind: AgentClientKind,
        allowPersonalData: Bool,
        access: AgentConnectionAccess
    ) async throws -> AgentConnectionIssuedResponse {
        issueCalls.append((name, clientKind, allowPersonalData, access))
        if let issueResult { return issueResult }
        throw URLError(.badServerResponse)
    }

    func update(id: UUID, request: AgentConnectionUpdateRequest) async throws -> AgentConnectionDTO {
        updateCalls.append((id, request))
        if let updateResult { return updateResult }
        throw URLError(.badServerResponse)
    }

    func revoke(id: UUID) async throws {
        revokedIDs.append(id)
    }
}
