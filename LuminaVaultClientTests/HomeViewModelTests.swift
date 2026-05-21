// LuminaVaultClient/LuminaVaultClientTests/HomeViewModelTests.swift
// HER-244 — contract tests for HomeViewModel. Covers initial loading
// state, happy-path settle for each card, per-card failure isolation,
// online/offline reachability, and the compile delegation path.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class HomeViewModelTests: XCTestCase {
    private var statsClient: MockDashboardStatsClient!
    private var tasksClient: MockTasksClient!
    private var insightsClient: MockInsightsClient!
    private var healthClient: MockHealthClient!
    private var compileClient: MockKBCompileClient!
    private var compileVM: SyncAndLearnViewModel!
    private var sut: HomeViewModel!

    override func setUp() async throws {
        try await super.setUp()
        statsClient = MockDashboardStatsClient()
        tasksClient = MockTasksClient()
        insightsClient = MockInsightsClient()
        healthClient = MockHealthClient()
        compileClient = MockKBCompileClient()
        compileVM = SyncAndLearnViewModel(client: compileClient)
        sut = HomeViewModel(
            statsClient: statsClient,
            tasksClient: tasksClient,
            insightsClient: insightsClient,
            healthClient: healthClient,
            compileViewModel: compileVM,
            displayName: "Fernando"
        )
    }

    func testInitialStateIsLoading() {
        if case .loading = sut.stats {} else { XCTFail("stats not loading") }
        if case .loading = sut.tasks {} else { XCTFail("tasks not loading") }
        if case .loading = sut.insights {} else { XCTFail("insights not loading") }
        XCTAssertTrue(sut.isOnline)
        XCTAssertEqual(sut.displayName, "Fernando")
    }

    func testRefreshHappyPathSettlesAllCards() async {
        statsClient.result = .success(.stub(today: 7, total: 99))
        tasksClient.result = .success(TaskListResponse(tasks: [.stub()]))
        insightsClient.result = .success(InsightListResponse(insights: [.stub(headline: "Pattern A")]))
        healthClient.online = true

        await sut.refresh()

        XCTAssertEqual(sut.stats.value?.memoriesToday, 7)
        XCTAssertEqual(sut.stats.value?.memoriesTotal, 99)
        XCTAssertEqual(sut.tasks.value?.count, 1)
        XCTAssertEqual(sut.insights.value?.first?.headline, "Pattern A")
        XCTAssertTrue(sut.isOnline)
    }

    func testTasksFailureIsIsolated() async {
        statsClient.result = .success(.empty)
        tasksClient.result = .failure(APIError.networkFailure(URLError(.timedOut)))
        insightsClient.result = .success(InsightListResponse(insights: []))

        await sut.refresh()

        if case .failed = sut.tasks {} else { XCTFail("tasks should be failed") }
        // Other cards should remain loaded — failure is per-card, not global.
        if case .loaded = sut.stats {} else { XCTFail("stats should be loaded") }
        if case .loaded = sut.insights {} else { XCTFail("insights should be loaded") }
    }

    func testInsightsEmptyStateRendersAsLoadedEmpty() async {
        insightsClient.result = .success(InsightListResponse(insights: []))
        statsClient.result = .success(.empty)
        await sut.refresh()
        switch sut.insights {
        case .loaded(let list): XCTAssertTrue(list.isEmpty)
        default: XCTFail("expected loaded empty")
        }
    }

    func testHealthOfflineFlipsIsOnline() async {
        healthClient.online = false
        await sut.refresh()
        XCTAssertFalse(sut.isOnline)
    }

    func testTasksRequestsLimitFive() async {
        await sut.refresh()
        XCTAssertEqual(tasksClient.lastLimit, 5)
    }

    func testInsightsRequestsLimitThree() async {
        await sut.refresh()
        XCTAssertEqual(insightsClient.lastLimit, 3)
    }

    func testTriggerCompileDelegatesAndReloadsStats() async {
        compileClient.compileResult = .success(.init(memoriesIngested: 3, memoriesUpdated: 0, durationMs: 100))
        statsClient.result = .success(.stub(today: 1))

        await sut.triggerCompile()

        XCTAssertEqual(compileClient.compileCallCount, 1)
        // Stats reloaded once during triggerCompile.
        XCTAssertGreaterThanOrEqual(statsClient.callCount, 1)
    }
}
