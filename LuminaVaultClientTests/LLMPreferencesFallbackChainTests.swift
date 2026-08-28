// LuminaVaultClient/LuminaVaultClientTests/LLMPreferencesFallbackChainTests.swift
//
// Stage 8 — the fallback chain used to be rendered with
// `ForEach(Array(chain.enumerated()), id: \.offset)` carrying *both*
// `.onDelete` and `.onMove`, and edited through an index-keyed setter. Under
// that scheme a reorder silently re-points every pending edit at whatever
// route slid into the index, so an edit could land on the wrong step of the
// chain that decides where the user's prompts and money go.
//
// These tests pin the property that replaces it: a row's identity, and every
// mutation keyed to that identity, survives reorder and delete. There is no
// snapshot coverage for this screen, so these tests are the only thing
// standing in for eyes on it.

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class LLMPreferencesFallbackChainTests: XCTestCase {
    // MARK: Test doubles

    private final class StubClient: LLMPreferencesClientProtocol {
        var stubbedGet: LLMPreferencesGetResponse = .init(
            mode: .byok,
            primaryProvider: .anthropic,
            primaryModel: "claude-3-5-sonnet-latest",
            fallbackChain: []
        )
        private(set) var putCalls: [LLMPreferencesPutRequest] = []

        func get() async throws -> LLMPreferencesGetResponse { stubbedGet }

        func put(_ body: LLMPreferencesPutRequest) async throws -> LLMPreferencesGetResponse {
            putCalls.append(body)
            return LLMPreferencesGetResponse(
                mode: body.mode,
                primaryProvider: body.primaryProvider,
                primaryModel: body.primaryModel,
                fallbackChain: body.fallbackChain
            )
        }
    }

    private final class StubProvidersClient: ProvidersClientProtocol {
        func list() async throws -> ProviderCredentialsListResponse {
            ProviderCredentialsListResponse(providers: [])
        }

        func upsert(_: ProviderID, _: ProviderCredentialPutRequest) async throws -> ProviderCredentialDTO {
            throw URLError(.unsupportedURL)
        }

        func delete(_: ProviderID) async throws {}

        func test(_: ProviderID) async throws -> ProviderTestResponse {
            throw URLError(.unsupportedURL)
        }

        func models(_ provider: ProviderID) async throws -> ProviderModelsResponse {
            ProviderModelsResponse(provider: provider, models: [], fetchedLive: false)
        }

        func listPool(_ provider: ProviderID) async throws -> ProviderPoolListResponse {
            ProviderPoolListResponse(provider: provider, keys: [])
        }

        func addPool(_: ProviderID, _: ProviderPoolAddRequest) async throws -> ProviderPoolKeyDTO {
            throw URLError(.unsupportedURL)
        }

        func deletePool(_: ProviderID, keyID _: UUID) async throws {}
    }

    // MARK: Fixtures

    /// Anthropic/openai/openRouter, in that order, as the loaded chain.
    private static let alpha = ModelRouteDTO(provider: .anthropic, model: "alpha")
    private static let bravo = ModelRouteDTO(provider: .openai, model: "bravo")
    private static let charlie = ModelRouteDTO(provider: .openRouter, model: "charlie")

    private var client: StubClient!

    override func setUp() async throws {
        try await super.setUp()
        client = StubClient()
    }

    private func makeLoadedSUT(
        chain: [ModelRouteDTO] = [alpha, bravo, charlie]
    ) async -> LLMPreferencesPaneViewModel {
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .byok,
            primaryProvider: .anthropic,
            primaryModel: "claude-3-5-sonnet-latest",
            fallbackChain: chain
        )
        let sut = LLMPreferencesPaneViewModel(client: client, providersClient: StubProvidersClient())
        await sut.load()
        return sut
    }

    private func models(_ sut: LLMPreferencesPaneViewModel) -> [String] {
        sut.fallbackChain.map(\.model)
    }

    // MARK: Identity

    func testLoadedRowsCarryDistinctIdentities() async {
        let sut = await makeLoadedSUT()
        let ids = sut.fallbackChain.map(\.id)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3)
    }

    /// A chain may legitimately repeat the same route. Content-derived ids
    /// would collide here; UUIDs do not.
    func testByteIdenticalRoutesStillGetDistinctIdentities() async {
        let sut = await makeLoadedSUT(chain: [Self.alpha, Self.alpha, Self.alpha])
        XCTAssertEqual(Set(sut.fallbackChain.map(\.id)).count, 3)
        XCTAssertEqual(models(sut), ["alpha", "alpha", "alpha"])
    }

    func testMovePreservesRowIdentities() async {
        let sut = await makeLoadedSUT()
        let before = sut.fallbackChain

        sut.moveFallback(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(models(sut), ["bravo", "charlie", "alpha"])
        XCTAssertEqual(sut.fallbackChain.map(\.id), [before[1].id, before[2].id, before[0].id])
    }

    // MARK: Reorder → edit

    /// The headline regression: move the first row to the end, then edit it.
    /// Under offset identity the edit landed on whatever route inherited
    /// index 0 (`bravo`); keyed on identity it lands on `alpha`.
    func testEditAfterReorderWritesToTheMovedRowNotTheOldIndex() async {
        let sut = await makeLoadedSUT()
        let alphaID = sut.fallbackChain[0].id

        sut.moveFallback(from: IndexSet(integer: 0), to: 3)
        sut.updateFallback(id: alphaID, model: "alpha-edited")

        XCTAssertEqual(models(sut), ["bravo", "charlie", "alpha-edited"])
    }

    func testProviderChangeAfterReorderWritesToTheMovedRow() async {
        let sut = await makeLoadedSUT()
        let charlieID = sut.fallbackChain[2].id

        // Pull the last row to the front, then repoint its provider.
        sut.moveFallback(from: IndexSet(integer: 2), to: 0)
        sut.updateFallback(id: charlieID, provider: .gemini)

        XCTAssertEqual(models(sut), ["charlie", "alpha", "bravo"])
        XCTAssertEqual(sut.fallbackChain.map(\.provider), [.gemini, .anthropic, .openai])
    }

    /// A reorder that stays entirely inside the array still has to re-point
    /// edits: `bravo` and `charlie` swap, and each keeps its own id.
    func testEditAfterAdjacentSwapTargetsTheCorrectRow() async {
        let sut = await makeLoadedSUT()
        let bravoID = sut.fallbackChain[1].id
        let charlieID = sut.fallbackChain[2].id

        sut.moveFallback(from: IndexSet(integer: 2), to: 1)
        sut.updateFallback(id: bravoID, model: "bravo-edited")
        sut.updateFallback(id: charlieID, model: "charlie-edited")

        XCTAssertEqual(models(sut), ["alpha", "charlie-edited", "bravo-edited"])
    }

    // MARK: Reorder → delete

    func testDeleteAfterReorderRemovesTheRowAtTheRenderedOffset() async {
        let sut = await makeLoadedSUT()

        sut.moveFallback(from: IndexSet(integer: 0), to: 3)
        // `.onDelete` hands back offsets into the *rendered* order, which is
        // `fallbackChain` itself — so offset 2 must be `alpha`, not `charlie`.
        sut.removeFallback(at: IndexSet(integer: 2))

        XCTAssertEqual(models(sut), ["bravo", "charlie"])
    }

    func testEditAfterDeleteWritesToTheSurvivingRow() async {
        let sut = await makeLoadedSUT()
        let charlieID = sut.fallbackChain[2].id

        // Deleting the middle row shifts `charlie` from index 2 to index 1.
        sut.removeFallback(at: IndexSet(integer: 1))
        sut.updateFallback(id: charlieID, model: "charlie-edited")

        XCTAssertEqual(models(sut), ["alpha", "charlie-edited"])
    }

    func testEditingADeletedRowIsANoOp() async {
        let sut = await makeLoadedSUT()
        let bravoID = sut.fallbackChain[1].id

        sut.removeFallback(at: IndexSet(integer: 1))
        sut.updateFallback(id: bravoID, model: "resurrected")

        XCTAssertEqual(models(sut), ["alpha", "charlie"])
    }

    func testEditingAnUnknownIdentityIsANoOp() async {
        let sut = await makeLoadedSUT()
        sut.updateFallback(id: UUID(), model: "ghost")
        XCTAssertEqual(models(sut), ["alpha", "bravo", "charlie"])
    }

    // MARK: Added rows

    func testAddedRowGetsAnIdentityDistinctFromLoadedRows() async {
        let sut = await makeLoadedSUT()
        sut.addFallback()
        sut.addFallback()

        XCTAssertEqual(sut.fallbackChain.count, 5)
        XCTAssertEqual(Set(sut.fallbackChain.map(\.id)).count, 5)

        // Two freshly-added rows are both `(openRouter, "")` — editing one
        // must not touch the other.
        let firstAddedID = sut.fallbackChain[3].id
        sut.updateFallback(id: firstAddedID, model: "typed-into-row-four")
        XCTAssertEqual(models(sut), ["alpha", "bravo", "charlie", "typed-into-row-four", ""])
    }

    // MARK: Dirty tracking + persistence

    func testReorderMarksDirtyAndRestoringOrderClearsIt() async {
        let sut = await makeLoadedSUT()
        XCTAssertFalse(sut.hasUnsavedChanges)

        sut.moveFallback(from: IndexSet(integer: 0), to: 3)
        XCTAssertTrue(sut.hasUnsavedChanges, "Reordering the chain changes what the server will run.")

        sut.moveFallback(from: IndexSet(integer: 2), to: 0)
        XCTAssertFalse(sut.hasUnsavedChanges, "Restoring the loaded order is not an unsaved change.")
    }

    func testEditMarksDirtyEvenThoughIdentitiesAreLocal() async {
        let sut = await makeLoadedSUT()
        sut.updateFallback(id: sut.fallbackChain[0].id, model: "alpha-edited")
        XCTAssertTrue(sut.hasUnsavedChanges)
    }

    func testSaveSerializesTheEditedChainInRenderedOrder() async throws {
        let sut = await makeLoadedSUT()
        let alphaID = sut.fallbackChain[0].id

        sut.moveFallback(from: IndexSet(integer: 0), to: 3)
        sut.updateFallback(id: alphaID, provider: .nvidia, model: "alpha-edited")
        await sut.save()

        let put = try XCTUnwrap(client.putCalls.first)
        XCTAssertEqual(put.fallbackChain.map(\.model), ["bravo", "charlie", "alpha-edited"])
        XCTAssertEqual(put.fallbackChain.map(\.provider), [.openai, .openRouter, .nvidia])
    }

    /// Applying a server response re-mints identities. That is intended — the
    /// chain is replaced wholesale — and it must leave the editor clean.
    func testSaveRebuildsRowsFromTheServerResponseAndClearsDirty() async {
        let sut = await makeLoadedSUT()
        let idsBefore = Set(sut.fallbackChain.map(\.id))

        sut.updateFallback(id: sut.fallbackChain[0].id, model: "alpha-edited")
        await sut.save()

        XCTAssertEqual(models(sut), ["alpha-edited", "bravo", "charlie"])
        XCTAssertFalse(sut.hasUnsavedChanges)
        XCTAssertTrue(
            Set(sut.fallbackChain.map(\.id)).isDisjoint(with: idsBefore),
            "A server snapshot replaces the chain, so rows are new rows."
        )
    }
}
