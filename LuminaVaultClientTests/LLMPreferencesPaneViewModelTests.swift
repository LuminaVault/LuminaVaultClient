// LuminaVaultClient/LuminaVaultClientTests/LLMPreferencesPaneViewModelTests.swift
//
// HER-300 ticket 5 — verifies the Settings → Intelligence view model
// correctly loads / dirties / saves the LLM brain `mode`, and that the
// managed-mode Save path leaves provider/model policy to the backend.

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class LLMPreferencesPaneViewModelTests: XCTestCase {
    // MARK: Test doubles

    private final class MockLLMPreferencesClient: LLMPreferencesClientProtocol {
        var stubbedGet: LLMPreferencesGetResponse = .init(
            mode: .managed,
            primaryProvider: .openRouter,
            primaryModel: "deepseek/deepseek-v4-flash",
            fallbackChain: []
        )
        var stubbedPutResponse: LLMPreferencesGetResponse?
        var putError: Error?
        private(set) var putCalls: [LLMPreferencesPutRequest] = []

        func get() async throws -> LLMPreferencesGetResponse {
            stubbedGet
        }

        func put(_ body: LLMPreferencesPutRequest) async throws -> LLMPreferencesGetResponse {
            putCalls.append(body)
            if let putError {
                throw putError
            }
            return stubbedPutResponse ?? stubbedGet
        }
    }

    private final class MockProvidersClient: ProvidersClientProtocol {
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

    /// Records router writes. An actor, because the protocol is `Sendable`.
    private actor MockRouterClient: RouterClientProtocol {
        let current: RouterProfileDTO
        private(set) var updates: [RouterProfileWriteRequest] = []

        init(current: RouterProfileDTO) {
            self.current = current
        }

        func profiles() async throws -> RouterProfilesResponse {
            RouterProfilesResponse(profiles: [current], defaultProfileID: current.id)
        }

        func catalog() async throws -> RouterCatalogResponse {
            throw URLError(.unsupportedURL)
        }

        func dashboard() async throws -> RouterDashboardResponse {
            throw URLError(.unsupportedURL)
        }

        func updateProfile(id _: UUID, request: RouterProfileWriteRequest) async throws -> RouterProfileDTO {
            updates.append(request)
            return current
        }

        func bindings() async throws -> RouterBindingsResponse {
            throw URLError(.unsupportedURL)
        }

        func bind(scope: RouterBindingScope, scopeID: String, profileID: UUID) async throws -> RouterBindingDTO {
            RouterBindingDTO(id: UUID(), scope: scope, scopeID: scopeID, profileID: profileID)
        }

        func unbind(scope _: RouterBindingScope, scopeID _: String) async throws {}
    }

    private static let managedLabel = "LuminaVault Brain · Auto"

    // MARK: Fixtures

    private var client: MockLLMPreferencesClient!

    override func setUp() async throws {
        try await super.setUp()
        client = MockLLMPreferencesClient()
    }

    private func makeSUT() -> LLMPreferencesPaneViewModel {
        LLMPreferencesPaneViewModel(client: client, providersClient: MockProvidersClient())
    }

    // MARK: Loading

    func testLoadingManagedResponsePopulatesModeAndDefaults() async {
        // Under managed the server sends the brain label, not a model id.
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .managed,
            primaryProvider: .openRouter,
            primaryModel: Self.managedLabel,
            fallbackChain: []
        )
        let sut = makeSUT()
        await sut.load()

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertEqual(sut.mode, .managed)
        XCTAssertEqual(sut.primaryProvider, .openRouter)
        // The label is never held as the model; a switch to BYOK would send
        // it back as one.
        XCTAssertNotEqual(sut.primaryModel, Self.managedLabel)
        XCTAssertTrue(sut.fallbackChain.isEmpty)
        XCTAssertFalse(sut.hasUnsavedChanges)
    }

    func testLoadingBYOKResponsePopulatesMode() async {
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .byok,
            primaryProvider: .anthropic,
            primaryModel: "claude-3-5-sonnet-latest",
            fallbackChain: [ModelRouteDTO(provider: .openai, model: "gpt-4o")]
        )
        let sut = makeSUT()
        await sut.load()

        XCTAssertEqual(sut.mode, .byok)
        XCTAssertEqual(sut.primaryProvider, .anthropic)
        XCTAssertEqual(sut.primaryModel, "claude-3-5-sonnet-latest")
        XCTAssertEqual(sut.fallbackChain.count, 1)
        XCTAssertFalse(sut.hasUnsavedChanges)
    }

    // MARK: Dirty tracking

    func testTogglingModeFlipsDirty() async {
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .managed,
            primaryProvider: .openRouter,
            primaryModel: "deepseek/deepseek-v4-flash",
            fallbackChain: []
        )
        let sut = makeSUT()
        await sut.load()
        XCTAssertFalse(sut.hasUnsavedChanges)

        sut.mode = .byok
        sut.markDirty()
        XCTAssertTrue(sut.hasUnsavedChanges)

        // Toggling back to the loaded state clears dirty.
        sut.mode = .managed
        sut.markDirty()
        XCTAssertFalse(sut.hasUnsavedChanges)
    }

    func testCanSaveRequiresDirtyAndForBYOKNonEmptyModel() async {
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .byok,
            primaryProvider: .anthropic,
            primaryModel: "claude-3-5-sonnet-latest",
            fallbackChain: []
        )
        let sut = makeSUT()
        await sut.load()

        // Loaded → not dirty → not saveable.
        XCTAssertFalse(sut.canSave)

        // BYOK with empty model → still not saveable even when dirty.
        sut.primaryModel = ""
        sut.markDirty()
        XCTAssertTrue(sut.hasUnsavedChanges)
        XCTAssertFalse(sut.canSave)

        // Restore + flip to managed → saveable on managed regardless of
        // the BYOK model field.
        sut.primaryModel = ""
        sut.mode = .managed
        sut.markDirty()
        XCTAssertTrue(sut.hasUnsavedChanges)
        XCTAssertTrue(sut.canSave)
    }

    // MARK: Save — backend-owned managed payload

    func testSaveWithManagedModeOmitsBackendOwnedRoute() async throws {
        // Start in BYOK with a custom config so we can confirm the
        // managed save path overrides the in-memory BYOK editor state.
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .byok,
            primaryProvider: .anthropic,
            primaryModel: "claude-3-5-sonnet-latest",
            fallbackChain: [ModelRouteDTO(provider: .openai, model: "gpt-4o")]
        )
        let sut = makeSUT()
        await sut.load()

        // User switches to managed without clearing the BYOK fields.
        sut.mode = .managed
        sut.markDirty()
        await sut.save()

        XCTAssertEqual(client.putCalls.count, 1)
        let put = try XCTUnwrap(client.putCalls.first)
        XCTAssertEqual(put.mode, .managed)
        XCTAssertEqual(put.primaryProvider, .custom, "Managed save must not carry provider policy.")
        XCTAssertEqual(put.primaryModel, "", "Managed save must not carry model policy.")
        XCTAssertTrue(
            put.fallbackChain.isEmpty,
            "Managed save must clear the fallback chain — the managed router doesn't consult it."
        )
    }

    func testSaveWithBYOKModePutsUserEditedFields() async throws {
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .managed,
            primaryProvider: .openRouter,
            primaryModel: "deepseek/deepseek-v4-flash",
            fallbackChain: []
        )
        let sut = makeSUT()
        await sut.load()

        sut.mode = .byok
        sut.primaryProvider = .anthropic
        sut.primaryModel = "claude-3-5-sonnet-latest"
        sut.fallbackChain = [FallbackRouteUIModel(provider: .openai, model: "gpt-4o")]
        sut.markDirty()
        await sut.save()

        XCTAssertEqual(client.putCalls.count, 1)
        let put = try XCTUnwrap(client.putCalls.first)
        XCTAssertEqual(put.mode, .byok)
        XCTAssertEqual(put.primaryProvider, .anthropic)
        XCTAssertEqual(put.primaryModel, "claude-3-5-sonnet-latest")
        XCTAssertEqual(put.fallbackChain.count, 1)
        XCTAssertEqual(put.fallbackChain.first?.provider, .openai)
        XCTAssertEqual(put.fallbackChain.first?.model, "gpt-4o")
    }

    // MARK: The managed label is not a model

    func testSwitchingFromManagedToBYOKNeverSavesTheLabel() async throws {
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .managed,
            primaryProvider: .custom,
            primaryModel: Self.managedLabel,
            fallbackChain: []
        )
        let sut = makeSUT()
        await sut.load()

        sut.selectMode(.byok)
        await sut.save()

        XCTAssertNotEqual(client.putCalls.last?.primaryModel, Self.managedLabel)
    }

    // MARK: Router save after a preferences save

    /// The preferences PUT bumps the default profile's revision on the server
    /// and, on a switch to BYOK, replaces its routes. Saving the router profile
    /// with what was read before answered 409, and sent back the managed
    /// placeholder routes it had been shown.
    func testRouterSaveUsesTheProfileAsItIsAfterThePreferencesSave() async throws {
        let id = UUID()
        let stale = RouterProfileDTO(
            id: id,
            name: "Default",
            mode: .managed,
            defaultAction: RouterActionDTO(routes: [RouterModelRouteDTO(provider: .openRouter, model: "auto")]),
            revision: 1
        )
        let realRoute = RouterModelRouteDTO(provider: .anthropic, model: "claude-opus-4-7")
        let fresh = RouterProfileDTO(
            id: id,
            name: "Default",
            mode: .byok,
            defaultAction: RouterActionDTO(routes: [realRoute]),
            revision: 2
        )
        let router = MockRouterClient(current: fresh)
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .byok,
            primaryProvider: .anthropic,
            primaryModel: "claude-opus-4-7",
            fallbackChain: []
        )
        let sut = LLMPreferencesPaneViewModel(client: client, providersClient: MockProvidersClient(), routerClient: router)
        await sut.load()
        // What the pane held before the save.
        sut.routerProfiles = [stale]
        sut.selectedRouterProfileID = id
        sut.updateQualityWeight(60)

        await sut.save()

        let updates = await router.updates
        let update = try XCTUnwrap(updates.last)
        XCTAssertEqual(update.expectedRevision, 2)
        XCTAssertEqual(update.defaultAction.routes, [realRoute])
        XCTAssertNotEqual(sut.state, .failed("Couldn't load preferences."))
    }
}
