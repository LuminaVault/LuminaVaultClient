// LuminaVaultClient/LuminaVaultClientTests/PeriodRecapPlayerModelTests.swift
//
// The year / month in review player: which cards play, how time moves them
// on, what a hold and a tap do, and the one follow-up ask for a themes card
// still being written. Time moves only through `tick`, so nothing waits.

import Foundation
import LuminaVaultShared
import SwiftUI
import XCTest

@testable import LuminaVaultClient

@MainActor
final class PeriodRecapPlayerModelTests: XCTestCase {
    private struct Boom: Error {}

    private func makeSUT(
        _ results: [Result<PeriodRecapResponse, Error>],
        request: PeriodRecapRequest = .month(3, of: 2026)
    ) -> (PeriodRecapPlayerModel, MockPeriodRecapClient, MockTelemetry) {
        let client = MockPeriodRecapClient(results)
        let telemetry = MockTelemetry()
        let sut = PeriodRecapPlayerModel(
            client: client,
            request: request,
            telemetry: telemetry,
            sleep: { _ in }
        )
        return (sut, client, telemetry)
    }

    func testLoadAsksForThePeriodAndStartsOnTheIntro() async {
        let (sut, client, telemetry) = makeSUT([.success(.fixture())])
        await sut.load()
        XCTAssertEqual(client.requests, [.month(3, of: 2026)])
        XCTAssertEqual(client.requests.first?.queryPath, "/v1/me/recap/period?period=month&year=2026&month=3")
        XCTAssertEqual(sut.cards.count, 11)
        XCTAssertEqual(sut.current, .intro)
        XCTAssertEqual(telemetry.eventNames.prefix(2), ["recap_card_viewed", "recap_opened"])
    }

    func testAYearRequestSendsNoMonth() {
        XCTAssertEqual(PeriodRecapRequest.year(2026).queryPath, "/v1/me/recap/period?period=year&year=2026")
    }

    func testTimeMovesTheDeckAndTheSummaryWaits() async {
        let (sut, _, telemetry) = makeSUT([.success(.fixture(order: [.intro, .themes, .summary]))])
        await sut.load()
        sut.tick(4.9)
        XCTAssertEqual(sut.current, .intro)
        XCTAssertEqual(sut.progress, 0.98, accuracy: 0.001)
        sut.tick(0.2)
        XCTAssertEqual(sut.current, .themes)
        sut.tick(6.9)
        XCTAssertEqual(sut.current, .themes, "the themes card plays for seven seconds")
        sut.tick(0.2)
        XCTAssertEqual(sut.current, .summary)
        sut.tick(10)
        XCTAssertEqual(sut.current, .summary)
        XCTAssertTrue(sut.isFinished)
        XCTAssertEqual(telemetry.eventNames.filter { $0 == "recap_completed" }.count, 1)
    }

    func testAHoldStopsTimeAndTapsMoveByHand() async {
        let (sut, _, _) = makeSUT([.success(.fixture())])
        await sut.load()
        sut.setPaused(true)
        sut.tick(30)
        XCTAssertEqual(sut.current, .intro)
        sut.setPaused(false)
        sut.next()
        sut.next()
        XCTAssertEqual(sut.current, .peak)
        XCTAssertEqual(sut.segmentProgress(0), 1)
        XCTAssertEqual(sut.segmentProgress(5), 0)
        sut.previous()
        XCTAssertEqual(sut.current, .captures)
        sut.previous()
        sut.previous()
        XCTAssertEqual(sut.current, .intro, "back on the first card stays there")
        XCTAssertEqual(sut.elapsed, 0)
    }

    func testReplayStartsOver() async {
        let (sut, _, _) = makeSUT([.success(.fixture(order: [.intro, .summary]))])
        await sut.load()
        sut.next()
        sut.next()
        XCTAssertTrue(sut.isFinished)
        sut.restart()
        XCTAssertFalse(sut.isFinished)
        XCTAssertEqual(sut.current, .intro)
    }

    func testUnknownAndMissingCardsAreSkipped() async {
        var recap = PeriodRecapResponse.fixture(order: [.intro, .unknown, .captures, .summary])
        recap = PeriodRecapResponse(
            period: recap.period, year: recap.year, month: recap.month, start: recap.start, end: recap.end,
            timezone: recap.timezone, isComplete: true, available: true,
            order: [.intro, .unknown, .captures, .peak, .summary],
            captures: recap.captures, shareText: "", generatedAt: Date()
        )
        XCTAssertEqual(PeriodRecapDeck.cards(for: recap), [.intro, .captures, .summary])
    }

    func testAnUnavailableRecapSaysWhyAndPlaysNothing() async {
        let (sut, _, telemetry) = makeSUT([.success(.fixture(available: false, reason: .notEnoughActivity))])
        await sut.load()
        guard case let .unavailable(recap) = sut.state else { return XCTFail("expected unavailable") }
        XCTAssertTrue(sut.cards.isEmpty)
        XCTAssertTrue(PeriodRecapDeck.unavailableText(recap).hasPrefix("Not enough happened this month"))
        XCTAssertFalse(telemetry.eventNames.contains("recap_opened"))
    }

    func testAFailedLoadSaysSo() async {
        let (sut, _, _) = makeSUT([.failure(Boom())])
        await sut.load()
        XCTAssertEqual(sut.state, .failed("Couldn't load your recap."))
    }

    func testAPendingThemesCardIsAskedForOnceMoreAndOnlyThemesChange() async {
        let (sut, client, _) = makeSUT([
            .success(.fixture(themes: .pending)),
            .success(.fixture(themes: .ready)),
        ])
        await sut.load()
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(sut.recap?.themes?.status, .ready)
        XCTAssertEqual(PeriodRecapDeck.themes(sut.recap!).sentence, "You spent March building after dark.")
        XCTAssertEqual(sut.current, .intro, "the deck keeps its place")
    }

    func testAThemesRefetchThatFailsKeepsTheFallback() async {
        let (sut, _, _) = makeSUT([.success(.fixture(themes: .pending)), .failure(Boom())])
        await sut.load()
        XCTAssertEqual(sut.recap?.themes?.status, .pending)
        XCTAssertEqual(PeriodRecapDeck.themes(sut.recap!).sentence, "A month of swift and side_project.")
    }

    func testSharingIsRecorded() async {
        let (sut, _, telemetry) = makeSUT([.success(.fixture())])
        await sut.load()
        sut.recordShare()
        XCTAssertEqual(telemetry.events.last, .init(name: "recap_shared", properties: ["period": "month"]))
    }
}

final class PeriodRecapDeckTests: XCTestCase {
    func testWords() {
        XCTAssertEqual(PeriodRecapDeck.periodName(period: .year, year: 2026, month: nil), "2026")
        XCTAssertEqual(PeriodRecapDeck.periodName(period: .month, year: 2026, month: 3), "March 2026")
        XCTAssertEqual(PeriodRecapDeck.bucketName("2026-03"), "March")
        XCTAssertEqual(PeriodRecapDeck.bucketName("2026-03-14"), "14 March")
        XCTAssertEqual(PeriodRecapDeck.weekdayName(6), "Saturday")
        XCTAssertEqual(PeriodRecapDeck.hourLabel(0), "12am")
        XCTAssertEqual(PeriodRecapDeck.hourLabel(12), "12pm")
        XCTAssertEqual(PeriodRecapDeck.hourLabel(23), "11pm")
        XCTAssertEqual(PeriodRecapDeck.persona(.nightOwl).title, "Night owl")
        XCTAssertEqual(PeriodRecapDeck.persona(.unknown).title, "All-day thinker")
    }

    func testDeltas() {
        XCTAssertEqual(PeriodRecapDeck.delta(52, previous: 40), "+30%")
        XCTAssertEqual(PeriodRecapDeck.delta(30, previous: 40), "\u{2212}25%")
        XCTAssertEqual(PeriodRecapDeck.delta(40, previous: 40), "Same as before")
        XCTAssertNil(PeriodRecapDeck.delta(40, previous: 0))
    }

    func testBarsAreScaledToTheTallest() {
        XCTAssertEqual(PeriodRecapDeck.normalised([0, 2, 4]), [0, 0.5, 1])
        XCTAssertEqual(PeriodRecapDeck.normalised([0, 0]), [0, 0])
    }

    /// The share image carries numbers only.
    func testShareStatsHoldNoTagsTitlesOrThemes() {
        let recap = PeriodRecapResponse.fixture()
        let stats = PeriodRecapDeck.shareStats(recap)
        XCTAssertEqual(stats.first?.value, "52")
        XCTAssertEqual(stats.map(\.label), ["memories", "questions asked", "day streak", "active days", "agent runs", "badges"])
        let text = stats.map { "\($0.value) \($0.label)" }.joined(separator: " ")
        for secret in ["swift", "side_project", "Work", "daily-brief", "Night owl builder", "First week"] {
            XCTAssertFalse(text.contains(secret), "\(secret) leaked into the share card")
        }
    }

    @MainActor
    func testTheShareCardRendersAt1080By1920() throws {
        let image = try XCTUnwrap(PeriodRecapShareCard.render(.fixture(), palette: LVTheme.cyanGold.palette(for: .dark)))
        XCTAssertEqual(image.size.width * image.scale, 1080, accuracy: 1)
        XCTAssertEqual(image.size.height * image.scale, 1920, accuracy: 1)
    }
}
