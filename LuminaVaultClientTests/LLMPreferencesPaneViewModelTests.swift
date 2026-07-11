// LuminaVaultClient/LuminaVaultClientTests/LLMPreferencesPaneViewModelTests.swift
//
// HER-300 ticket 5 — verifies the Settings → Intelligence view model
// correctly loads / dirties / saves the LLM brain `mode`, and that the
// managed-mode Save path always PUTs the canonical OpenRouter/Qwen
// pair regardless of whatever the BYOK editor is still holding in
// memory.

import XCTest
import LuminaVaultShared
@testable import LuminaVaultClient

@MainActor
final class LLMPreferencesPaneViewModelTests: XCTestCase {

    // MARK: Test doubles

    private final class MockLLMPreferencesClient: LLMPreferencesClientProtocol {
        var stubbedGet: LLMPreferencesGetResponse = LLMPreferencesGetResponse(
            mode: .managed,
            primaryProvider: .openRouter,
            primaryModel: "qwen/qwen-2.5-72b-instruct",
            fallbackChain: []
        )
        var stubbedPutResponse: LLMPreferencesGetResponse?
        var putError: Error?
        private(set) var putCalls: [LLMPreferencesPutRequest] = []

        func get() async throws -> LLMPreferencesGetResponse { stubbedGet }

        func put(_ body: LLMPreferencesPutRequest) async throws -> LLMPreferencesGetResponse {
            putCalls.append(body)
            if let putError { throw putError }
            return stubbedPutResponse ?? stubbedGet
        }
    }

    private final class MockProvidersClient: ProvidersClientProtocol {
        func list() async throws -> ProviderCredentialsListResponse {
            ProviderCredentialsListResponse(providers: [])
        }

        func upsert(_ provider: ProviderID, _ body: ProviderCredentialPutRequest) async throws -> ProviderCredentialDTO {
            ProviderCredentialDTO(provider: provider, kind: body.kind, hasCredential: true, baseUrl: body.baseUrl, label: body.label)
        }

        func delete(_ provider: ProviderID) async throws {}

        func test(_ provider: ProviderID) async throws -> ProviderTestResponse {
            ProviderTestResponse(verifiedAt: Date(), model: nil)
        }

        func models(_ provider: ProviderID) async throws -> ProviderModelsResponse {
            ProviderModelsResponse(provider: provider, models: [], fetchedLive: false)
        }

        func listPool(_ provider: ProviderID) async throws -> ProviderPoolListResponse {
            ProviderPoolListResponse(provider: provider, keys: [])
        }

        func addPool(_ provider: ProviderID, _ body: ProviderPoolAddRequest) async throws -> ProviderPoolKeyDTO {
            ProviderPoolKeyDTO(id: UUID(), label: body.label, createdAt: Date())
        }

        func deletePool(_ provider: ProviderID, keyID: UUID) async throws {}
    }

    // MARK: Fixtures

    private var client: MockLLMPreferencesClient!
    private var providersClient: MockProvidersClient!

    override func setUp() async throws {
        try await super.setUp()
        client = MockLLMPreferencesClient()
        providersClient = MockProvidersClient()
    }

    private func makeSUT() -> LLMPreferencesPaneViewModel {
        LLMPreferencesPaneViewModel(client: client, providersClient: providersClient)
    }

    // MARK: Loading

    func testLoadingManagedResponsePopulatesModeAndDefaults() async {
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .managed,
            primaryProvider: .openRouter,
            primaryModel: "qwen/qwen-2.5-72b-instruct",
            fallbackChain: []
        )
        let sut = makeSUT()
        await sut.load()

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertEqual(sut.mode, .managed)
        XCTAssertEqual(sut.primaryProvider, .openRouter)
        XCTAssertEqual(sut.primaryModel, "qwen/qwen-2.5-72b-instruct")
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
            primaryModel: "qwen/qwen-2.5-72b-instruct",
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

    // MARK: Save — canonical managed payload

    func testSaveWithManagedModePinsCanonicalDefaults() async {
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
        let put = client.putCalls.first!
        XCTAssertEqual(put.mode, .managed)
        XCTAssertEqual(
            put.primaryProvider,
            LLMPreferencesPaneViewModel.managedDefaultProvider,
            "Managed save must pin the canonical OpenRouter provider."
        )
        XCTAssertEqual(
            put.primaryModel,
            LLMPreferencesPaneViewModel.managedDefaultModel,
            "Managed save must pin the canonical Qwen2.5-72B model."
        )
        XCTAssertTrue(
            put.fallbackChain.isEmpty,
            "Managed save must clear the fallback chain — the managed router doesn't consult it."
        )
    }

    func testSaveWithBYOKModePutsUserEditedFields() async {
        client.stubbedGet = LLMPreferencesGetResponse(
            mode: .managed,
            primaryProvider: .openRouter,
            primaryModel: "qwen/qwen-2.5-72b-instruct",
            fallbackChain: []
        )
        let sut = makeSUT()
        await sut.load()

        sut.mode = .byok
        sut.primaryProvider = .anthropic
        sut.primaryModel = "claude-3-5-sonnet-latest"
        sut.fallbackChain = [ModelRouteDTO(provider: .openai, model: "gpt-4o")]
        sut.markDirty()
        await sut.save()

        XCTAssertEqual(client.putCalls.count, 1)
        let put = client.putCalls.first!
        XCTAssertEqual(put.mode, .byok)
        XCTAssertEqual(put.primaryProvider, .anthropic)
        XCTAssertEqual(put.primaryModel, "claude-3-5-sonnet-latest")
        XCTAssertEqual(put.fallbackChain.count, 1)
        XCTAssertEqual(put.fallbackChain.first?.provider, .openai)
        XCTAssertEqual(put.fallbackChain.first?.model, "gpt-4o")
    }
}
