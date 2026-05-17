// LuminaVaultClient/LuminaVaultClientTests/ThinkWithLuminaViewModelTests.swift
// HER-37: state-machine + suggestion-loading contract tests for the
// "Think with Lumina" ViewModel.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class ThinkWithLuminaViewModelTests: XCTestCase {
    var queryClient: MockMemoryQueryClient!
    var suggestionsClient: MockSuggestionsClient!
    var sut: ThinkWithLuminaViewModel!

    override func setUp() async throws {
        try await super.setUp()
        queryClient = MockMemoryQueryClient()
        suggestionsClient = MockSuggestionsClient()
        sut = ThinkWithLuminaViewModel(
            queryClient: queryClient,
            suggestionsClient: suggestionsClient,
            resultLimit: 5,
        )
    }

    func testInitialPhaseIsEmpty() {
        XCTAssertEqual(sut.phase, .empty)
        XCTAssertEqual(sut.mascotState, .idle)
        XCTAssertFalse(sut.isBusy)
    }

    func testLoadSuggestionsPopulatesArray() async {
        await sut.loadSuggestions()
        XCTAssertEqual(sut.suggestions.count, 3)
        XCTAssertEqual(suggestionsClient.listCallCount, 1)
    }

    func testLoadSuggestionsFailureLeavesEmpty() async {
        suggestionsClient.listResult = .failure(APIError.networkFailure(URLError(.notConnectedToInternet)))
        await sut.loadSuggestions()
        XCTAssertTrue(sut.suggestions.isEmpty)
    }

    func testAskHappyPathAdvancesToInsight() async {
        queryClient.queryResult = .success(.stubTwoHits)
        sut.queryText = "sleep patterns"

        await sut.ask()

        if case let .insight(response, queryText) = sut.phase {
            XCTAssertEqual(response, .stubTwoHits)
            XCTAssertEqual(queryText, "sleep patterns")
        } else {
            XCTFail("expected insight phase, got \(sut.phase)")
        }
        XCTAssertEqual(queryClient.calls.count, 1)
        XCTAssertEqual(queryClient.calls.first?.text, "sleep patterns")
        XCTAssertEqual(queryClient.calls.first?.limit, 5)
    }

    func testAskWithBlankQueryIsNoop() async {
        sut.queryText = "   "
        await sut.ask()
        XCTAssertEqual(sut.phase, .empty)
        XCTAssertTrue(queryClient.calls.isEmpty)
    }

    func testAskFailureAdvancesToFailed() async {
        queryClient.queryResult = .failure(APIError.unauthorized)
        sut.queryText = "anything"
        await sut.ask()
        if case .failed = sut.phase {} else {
            XCTFail("expected failed phase, got \(sut.phase)")
        }
    }

    func testMemoSeedRequiresActiveInsight() async {
        XCTAssertNil(sut.memoSeed())
        queryClient.queryResult = .success(.stubTwoHits)
        sut.queryText = "sleep"
        await sut.ask()
        XCTAssertEqual(sut.memoSeed()?.topic, "sleep")
    }

    func testApplySuggestionSeedsQueryText() {
        sut.applySuggestion("Summarize my sleep")
        XCTAssertEqual(sut.queryText, "Summarize my sleep")
    }

    func testFollowUpSeedsQueryText() {
        sut.tapFollowUp("Go deeper")
        XCTAssertEqual(sut.queryText, "Go deeper")
    }
}
