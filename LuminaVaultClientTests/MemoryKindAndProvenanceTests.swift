import Foundation
import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class MemoryKindAndProvenanceTests: XCTestCase {
    private func contribution(
        _ operation: MemoryContributionOperationDTO = .create,
        actor: MemoryActorKindDTO = .model,
        source: MemorySourceKindDTO = .manual,
        provider: String? = nil,
        model: String? = nil
    ) -> MemoryContributionDTO {
        MemoryContributionDTO(
            id: UUID(),
            operation: operation,
            actor: actor,
            source: source,
            model: provider.map { ModelProvenanceDTO(provider: $0, model: model ?? "") },
            sourceReference: nil,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testAnAgentSaveNamesTheClientAndTheKey() {
        let saved = contribution(provider: "mcp:claude_code", model: "work laptop")
        XCTAssertEqual(MemoryProvenanceText.describe(saved), "Saved by Claude Code (work laptop)")
        let session = contribution(provider: "mcp", model: "session")
        XCTAssertEqual(MemoryProvenanceText.describe(session), "Saved by an agent")
    }

    func testUserAndModelChangesReadAsTheWebDoes() {
        XCTAssertEqual(MemoryProvenanceText.describe(contribution(.update, actor: .user)), "Edited by you")
        XCTAssertEqual(
            MemoryProvenanceText.describe(contribution(source: .knowledgeCompile, provider: "hermes", model: "x")),
            "Saved by Lumina from your notes"
        )
        XCTAssertEqual(
            MemoryProvenanceText.describe(contribution(actor: .system, source: .legacy)),
            "Saved before sources were tracked"
        )
    }

    func testTheKindFilterIsSentAndChangingItReloads() async {
        let client = RecordingMemoryClient()
        let sut = MemoryBrowserViewModel(client: client)
        await sut.load()
        await sut.setKindFilter(.decision)
        XCTAssertEqual(client.listedKinds, [nil, .decision])
        XCTAssertEqual(sut.kindFilter, .decision)
    }

    func testSavingSendsTheKind() async {
        let client = RecordingMemoryClient()
        let sut = MemoryBrowserViewModel(client: client)
        let ok = await sut.save(id: UUID(), content: "We ship Tuesdays.", tags: [], kind: .decision)
        XCTAssertTrue(ok)
        XCTAssertEqual(client.patchedKinds, [.decision])
    }
}

private final class RecordingMemoryClient: MemoryClientProtocol, @unchecked Sendable {
    var listedKinds: [MemoryKindDTO?] = []
    var patchedKinds: [MemoryKindDTO?] = []

    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id _: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func patch(id: UUID, _ request: MemoryPatchRequest) async throws -> MemoryDTO {
        patchedKinds.append(request.kind)
        return MemoryDTO(id: id, content: request.content ?? "", tags: request.tags ?? [], kind: request.kind)
    }

    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse {
        MemoryListResponse(memories: [], limit: 50, offset: 0)
    }

    func list(
        limit _: Int,
        offset _: Int,
        healthFilter _: MemoryHealthFilter?,
        kind: MemoryKindDTO?
    ) async throws -> MemoryListResponse {
        listedKinds.append(kind)
        return MemoryListResponse(memories: [], limit: 50, offset: 0)
    }

    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse {
        throw APIError.unauthorized
    }

    func delete(id _: UUID) async throws {}
}
