// LuminaVaultClient/LuminaVaultClientTests/RecapViewModelTests.swift
//
// The recap sheet's arithmetic and its range switch. The server counts; what
// the client owns is asking for the right window, not refetching what it
// already has, and saying the delta the right way round.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class RecapViewModelTests: XCTestCase {
    private struct Boom: Error {}

    private func makeSUT(
        week: MeRecapResponse? = .fixture(range: .week),
        month: MeRecapResponse? = .fixture(range: .month, start: "2026-09-16"),
        initial: MeRecapResponse? = nil
    ) -> (RecapViewModel, MockRecapClient) {
        let client = MockRecapClient()
        if let week { client.results[.week] = .success(week) }
        if let month { client.results[.month] = .success(month) }
        return (RecapViewModel(client: client, initial: initial), client)
    }

    func testLoadAsksForTheWeek() async {
        let (sut, client) = makeSUT()
        await sut.load()
        XCTAssertEqual(client.requestedRanges, [.week])
        XCTAssertEqual(sut.recap?.range, .week)
        XCTAssertEqual(sut.title, "Last 7 days")
    }

    func testSwitchingRangeLoadsThatRangeAndClearsTheSelection() async {
        let (sut, client) = makeSUT()
        await sut.load()
        sut.selectedDate = Date()

        await sut.select(range: .month)

        XCTAssertEqual(client.requestedRanges, [.week, .month])
        XCTAssertEqual(sut.range, .month)
        XCTAssertEqual(sut.recap?.range, .month)
        XCTAssertEqual(sut.title, "Last 30 days")
        XCTAssertNil(sut.selectedDate, "a day selected in one range means nothing in the other")
    }

    func testSwitchingBackUsesTheRangeAlreadyLoaded() async {
        let (sut, client) = makeSUT()
        await sut.load()
        await sut.select(range: .month)
        await sut.select(range: .week)
        XCTAssertEqual(client.requestedRanges, [.week, .month], "the week was already in hand")
        XCTAssertEqual(sut.recap?.range, .week)
    }

    func testTheStripsWeekOpensTheSheetWithoutAFetch() async {
        let (sut, client) = makeSUT(initial: .fixture(range: .week))
        XCTAssertNotNil(sut.recap, "numbers on open, not a spinner")
        await sut.load()
        XCTAssertTrue(client.requestedRanges.isEmpty)
    }

    func testReloadAlwaysAsks() async {
        let (sut, client) = makeSUT(initial: .fixture(range: .week))
        await sut.reload()
        XCTAssertEqual(client.requestedRanges, [.week])
    }

    func testAFailedLoadSaysSo() async {
        let client = MockRecapClient()
        client.results[.week] = .failure(Boom())
        let sut = RecapViewModel(client: client)
        await sut.load()
        XCTAssertEqual(sut.state, .failed("Couldn't load your recap."))
    }

    func testDeltasCompareWithThePreviousWindow() async {
        let recap = MeRecapResponse.fixture(
            totals: RecapTotalsDTO(captures: 12, learned: 4, asked: 2, reviewed: 3),
            previous: RecapTotalsDTO(captures: 9, learned: 4, asked: 5, reviewed: 0)
        )
        let (sut, _) = makeSUT(week: recap)
        await sut.load()

        XCTAssertEqual(sut.delta(for: .captures), 3)
        XCTAssertEqual(sut.delta(for: .learned), 0)
        XCTAssertEqual(sut.delta(for: .asked), -3)
        XCTAssertEqual(sut.deltaText(for: .captures), "+3 vs last week")
        XCTAssertEqual(sut.deltaText(for: .learned), "same as last week")
        XCTAssertEqual(sut.deltaText(for: .asked), "\u{2212}3 vs last week")
        XCTAssertEqual(sut.deltaText(for: .reviewed), "+3 vs last week")
    }

    func testMonthDeltasNameTheirWindow() async {
        let (sut, _) = makeSUT()
        await sut.select(range: .month)
        XCTAssertEqual(sut.deltaText(for: .captures), "+12 vs the previous 30 days")
    }

    func testTheDateRangeIsReadInTheRecapsTimezone() async throws {
        let (sut, _) = makeSUT()
        await sut.load()
        let text = RecapDates.rangeText(for: try XCTUnwrap(sut.recap), locale: Locale(identifier: "en_US"))
        XCTAssertEqual(text, "Oct 9 – Oct 15")
    }

    func testSelectingADayFindsItsBreakdown() async throws {
        let (sut, _) = makeSUT()
        await sut.load()
        let days = sut.chartDays
        XCTAssertEqual(days.count, 7)
        let target = try XCTUnwrap(days.last)
        // A drag lands anywhere inside the bar, not on the day's noon.
        sut.selectedDate = target.date.addingTimeInterval(3 * 3600)
        XCTAssertEqual(sut.selectedDay?.day.date, "2026-10-15")
    }

    func testOnlyMemoryHighlightsOpenAMemory() async {
        let memoryID = UUID()
        func highlight(_ kind: RecapHighlightKind, _ ref: String) -> RecapHighlightDTO {
            RecapHighlightDTO(kind: kind, refId: ref, title: "t", date: .now)
        }
        XCTAssertEqual(RecapViewModel.memoryID(for: highlight(.decision, memoryID.uuidString)), memoryID)
        XCTAssertEqual(RecapViewModel.memoryID(for: highlight(.preference, memoryID.uuidString)), memoryID)
        XCTAssertEqual(RecapViewModel.memoryID(for: highlight(.mostRevisited, memoryID.uuidString)), memoryID)
        XCTAssertNil(RecapViewModel.memoryID(for: highlight(.achievement, "first-capture")))
        XCTAssertNil(RecapViewModel.memoryID(for: highlight(.unknown, memoryID.uuidString)))
        XCTAssertNil(RecapViewModel.memoryID(for: highlight(.decision, "not-a-uuid")))
    }

    /// The contract is camelCase and the client's decoder converts from
    /// snake case. Keys with no underscore pass through untouched, so the
    /// shared DTO decodes as the server writes it.
    func testTheRecapDecodesThroughTheAppDecoder() throws {
        let json = """
        {"range":"7d","start":"2026-10-09","end":"2026-10-15","timezone":"Europe/Lisbon",
         "totals":{"captures":12,"learned":4,"asked":6,"reviewed":3,"activeDays":5,"streakDays":3},
         "previousTotals":{"captures":9,"learned":4,"asked":2,"reviewed":1,"activeDays":4,"streakDays":1},
         "daily":[{"date":"2026-10-15","captures":2,"learned":1,"asked":0,"reviewed":0}],
         "kinds":{"preference":1,"decision":2,"fact":3,"note":0},
         "highlights":[{"kind":"mostRevisited","refId":"7C0E0B53-9A51-4F43-9B0C-2C1E6B0E0001","title":"Ship on Tuesdays","date":"2026-10-14T09:00:00Z"},
                       {"kind":"somethingNew","refId":"x","title":"y","date":"2026-10-14T09:00:00Z"}],
         "shareText":"My week: 12 captures"}
        """
        let recap = try JSONDecoder.hvDefault.decode(MeRecapResponse.self, from: Data(json.utf8))
        XCTAssertEqual(recap.previousTotals.captures, 9)
        XCTAssertEqual(recap.totals.streakDays, 3)
        XCTAssertEqual(recap.highlights.first?.kind, .mostRevisited)
        XCTAssertEqual(recap.highlights.first?.refId, "7C0E0B53-9A51-4F43-9B0C-2C1E6B0E0001")
        XCTAssertEqual(recap.highlights.last?.kind, .unknown, "a newer highlight kind must not break the sheet")
    }

    func testRelatedDecodesThroughTheAppDecoder() throws {
        let json = """
        {"memoryId":"7C0E0B53-9A51-4F43-9B0C-2C1E6B0E0001","items":[
          {"id":"7C0E0B53-9A51-4F43-9B0C-2C1E6B0E0002","snippet":"Dentist","kind":"fact",
           "createdAt":"2026-10-14T09:00:00Z","spaceId":null,"similarity":0.81}]}
        """
        let related = try JSONDecoder.hvDefault.decode(MemoryRelatedResponse.self, from: Data(json.utf8))
        XCTAssertEqual(related.items.count, 1)
        XCTAssertEqual(related.items.first?.kind, .fact)
        XCTAssertEqual(related.items.first?.similarity, 0.81)
    }
}
