// LuminaVaultClient/LuminaVaultClientTests/HomeGlanceViewModelTests.swift
//
// Home's glance strip asks three endpoints for three numbers. The contract
// worth testing is that they settle independently — one dead endpoint must
// not blank the other two tiles — and that the recommendation row picks the
// one thing most worth doing next.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class HomeGlanceViewModelTests: XCTestCase {
    private struct Boom: Error {}

    private func makeSUT(
        memoriesToday: Int = 3,
        streakDays: Int = 4,
        toRevisit: Int = 0,
        pendingFiles: Int = 0,
        summaryFails: Bool = false,
        todayFails: Bool = false,
        pendingFails: Bool = false
    ) -> HomeGlanceViewModel {
        let summaryClient = MockHomeSummaryClient()
        if summaryFails {
            summaryClient.result = .failure(Boom())
        } else {
            summaryClient.result = .success(
                HomeSummaryResponse(
                    skillsCount: 0, jobsCount: 0, remindersCount: 0,
                    todosCount: 0, projectsCount: 0, insightsCount: 0,
                    memoriesToday: memoriesToday,
                    streakDays: streakDays
                )
            )
        }

        let dailyReviewClient = MockDailyReviewClient(memories: toRevisit)
        if todayFails { dailyReviewClient.result = .failure(Boom()) }

        let kbClient = MockKBCompileClient()
        kbClient.pendingResult = pendingFails
            ? .failure(Boom())
            : .success(KBCompilePendingResponse(pendingFiles: pendingFiles))

        return HomeGlanceViewModel(
            homeClient: summaryClient,
            dailyReviewClient: dailyReviewClient,
            pendingClient: kbClient
        )
    }

    // `async` on purpose: a *synchronous* test method in this `@MainActor`
    // case crashes the XCTest runner on Xcode 26.2 ("pointer being freed was
    // not allocated") before the body runs. Nothing to do with the subject.
    func testStartsLoading() async {
        let sut = makeSUT()
        XCTAssertNil(sut.memoriesToday.value)
        XCTAssertNil(sut.streakDays.value)
        XCTAssertNil(sut.toRevisit.value)
        XCTAssertFalse(sut.allFailed)
    }

    func testLoadFillsEveryTile() async {
        let sut = makeSUT(memoriesToday: 7, streakDays: 12, toRevisit: 2)
        await sut.load()
        XCTAssertEqual(sut.memoriesToday.value, 7)
        XCTAssertEqual(sut.streakDays.value, 12)
        XCTAssertEqual(sut.toRevisit.value, 2)
        XCTAssertFalse(sut.allFailed)
    }

    func testAFailingSummaryLeavesTheOtherTilesLoaded() async {
        let sut = makeSUT(toRevisit: 5, summaryFails: true)
        await sut.load()
        XCTAssertTrue(sut.memoriesToday.isFailed)
        XCTAssertTrue(sut.streakDays.isFailed)
        XCTAssertEqual(sut.toRevisit.value, 5)
        XCTAssertFalse(sut.allFailed)
    }

    func testAFailingDailyReviewLeavesTheSummaryTilesLoaded() async {
        let sut = makeSUT(memoriesToday: 1, streakDays: 2, todayFails: true)
        await sut.load()
        XCTAssertEqual(sut.memoriesToday.value, 1)
        XCTAssertEqual(sut.streakDays.value, 2)
        XCTAssertTrue(sut.toRevisit.isFailed)
        XCTAssertFalse(sut.allFailed)
    }

    func testAllFailedWhenEveryCallFails() async {
        let sut = makeSUT(summaryFails: true, todayFails: true, pendingFails: true)
        await sut.load()
        XCTAssertTrue(sut.allFailed)
        XCTAssertNil(sut.recommendation)
    }

    func testNoRecommendationWithNothingToDo() async {
        let sut = makeSUT(toRevisit: 0, pendingFiles: 0)
        await sut.load()
        XCTAssertNil(sut.recommendation)
    }

    func testPendingCapturesOutrankTheDailyReview() async {
        let sut = makeSUT(toRevisit: 9, pendingFiles: 4)
        await sut.load()
        XCTAssertEqual(sut.recommendation, .syncAndLearn(4))
    }

    func testDailyReviewWhenThereIsNothingToCompile() async {
        let sut = makeSUT(toRevisit: 9, pendingFiles: 0)
        await sut.load()
        XCTAssertEqual(sut.recommendation, .dailyReview(9))
    }

    func testAFailingPendingProbeDoesNotHideTheDailyReview() async {
        let sut = makeSUT(toRevisit: 3, pendingFails: true)
        await sut.load()
        XCTAssertEqual(sut.recommendation, .dailyReview(3))
    }

    func testSummaryIsAskedForToday() async {
        let summaryClient = MockHomeSummaryClient()
        let sut = HomeGlanceViewModel(
            homeClient: summaryClient,
            dailyReviewClient: MockDailyReviewClient(),
            pendingClient: MockKBCompileClient()
        )
        await sut.load()
        XCTAssertEqual(summaryClient.lastPeriod, .today)
    }
}
