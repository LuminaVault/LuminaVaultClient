// LuminaVaultClient/LuminaVaultClientTests/MeetingBriefViewModelTests.swift
//
// The pre-meeting brief. What the client owns: the event the link named is
// the one asked for; a brief with notes shows them with the why line; one
// without is an empty state, not a failure, and drops the why that would
// only repeat it; a 404 is its own state; any other failure is retryable
// and a failed refresh keeps what is on screen. Plus the formatting of the
// time range, the people and a note's kind and date.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class MeetingBriefViewModelTests: XCTestCase {
    private struct Boom: Error {}

    private let utc = TimeZone(identifier: "UTC") ?? .gmt
    private let enUS = Locale(identifier: "en_US")

    /// ICU puts a narrow no-break space before "PM"; compare it as a space.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func makeSUT(
        _ response: MeetingBriefResponse = .fixture()
    ) -> (MeetingBriefViewModel, MockMeetingBriefClient) {
        let client = MockMeetingBriefClient(response)
        let vm = MeetingBriefViewModel(
            eventID: MeetingBriefResponse.eventID,
            client: client,
            locale: enUS,
            timeZone: utc
        )
        return (vm, client)
    }

    // MARK: - Load

    func testStartsLoading() {
        let (vm, _) = makeSUT()
        XCTAssertEqual(vm.phase, .loading)
        XCTAssertNil(vm.brief)
    }

    func testLoadsTheBriefForTheLinkedEvent() async {
        let (vm, client) = makeSUT()
        await vm.load()

        XCTAssertEqual(client.requestedEventIDs, [MeetingBriefResponse.eventID])
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertFalse(vm.isEmpty)
        XCTAssertEqual(vm.memories.map(\.id), [MeetingBriefResponse.deckMemoryID, MeetingBriefResponse.budgetMemoryID])
        XCTAssertEqual(vm.whyText, "You mentioned Ana in 2 notes")
        XCTAssertEqual(vm.brief?.event.title, "Design review")
        XCTAssertEqual(vm.locationText, "Room 4.2")
        XCTAssertEqual(vm.attendeesText, "Ana Silva, Rui, and joana@example.com")
        XCTAssertEqual(vm.timeRangeText.map(plain), "Wed, Oct 21 · 2:30 PM – 3:00 PM")
    }

    func testNoMatchingNotesIsAnEmptyStateWithoutTheWhy() async {
        let (vm, _) = makeSUT(.fixture(memories: []))
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertTrue(vm.isEmpty)
        XCTAssertTrue(vm.memories.isEmpty)
        // "Nothing in your notes matches…" would only repeat the empty state.
        XCTAssertNil(vm.whyText)
        // The meeting itself still shows.
        XCTAssertEqual(vm.brief?.event.title, "Design review")
    }

    func testAnUnknownEventIsNotFound() async {
        let (vm, client) = makeSUT()
        client.result = .failure(APIError.httpError(statusCode: 404, data: Data()))
        await vm.load()

        XCTAssertEqual(vm.phase, .notFound)
        XCTAssertNil(vm.brief)
        XCTAssertFalse(vm.isEmpty)
    }

    func testOtherFailuresCanBeRetried() async {
        let (vm, client) = makeSUT()
        client.result = .failure(APIError.httpError(statusCode: 500, data: Data()))
        await vm.load()
        XCTAssertEqual(vm.phase, .failed("Couldn't load this meeting's brief."))

        client.result = .failure(Boom())
        await vm.load()
        XCTAssertEqual(vm.phase, .failed("Couldn't load this meeting's brief."))

        client.result = .success(.fixture())
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(client.requestedEventIDs.count, 3)
    }

    func testAFailedRefreshKeepsWhatIsOnScreen() async {
        let (vm, client) = makeSUT()
        await vm.load()
        client.result = .failure(APIError.httpError(statusCode: 404, data: Data()))
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.memories.count, 2)
    }

    // MARK: - Formatting

    func testABlankLocationIsHidden() async {
        let fixture = MeetingBriefResponse.fixture()
        let event = fixture.event
        let (vm, _) = makeSUT(MeetingBriefResponse(
            event: MeetingBriefEventDTO(id: event.id, title: event.title, startsAt: event.startsAt, endsAt: event.endsAt, location: "  ", attendees: []),
            memories: fixture.memories,
            why: fixture.why
        ))
        await vm.load()

        XCTAssertNil(vm.locationText)
        XCTAssertNil(vm.attendeesText)
    }

    func testAttendeesPreferNamesAndCountTheRest() {
        let seven = (1...7).map { CalendarAttendeeDTO(name: "P\($0)", email: nil) }
        XCTAssertEqual(MeetingBriefViewModel.attendeesText(seven, locale: enUS), "P1, P2, P3, P4, P5 and 2 more")
        XCTAssertEqual(
            MeetingBriefViewModel.attendeesText([CalendarAttendeeDTO(name: " ", email: "a@example.com")], locale: enUS),
            "a@example.com"
        )
        XCTAssertNil(MeetingBriefViewModel.attendeesText([CalendarAttendeeDTO()], locale: enUS))
    }

    func testATimeRangeAcrossMidnightNamesBothDays() {
        let start = Date(timeIntervalSince1970: 1_792_623_600) // Oct 21, 23:00 UTC
        let text = MeetingBriefViewModel.timeRangeText(
            start: start, end: start.addingTimeInterval(7200), locale: enUS, timeZone: utc
        )
        XCTAssertEqual(plain(text), "Wed, Oct 21 11:00 PM – Thu, Oct 22 1:00 AM")
    }

    func testANoteShowsItsKindAndDay() async {
        let (vm, _) = makeSUT()
        await vm.load()

        XCTAssertEqual(vm.memories.map(vm.metaText(for:)), ["Preference · Oct 3", "Decision · Sep 23"])
        XCTAssertEqual(MeetingBriefViewModel.kindLabel("open_question"), "Open question")
        XCTAssertNil(MeetingBriefViewModel.kindLabel(nil))
        XCTAssertNil(MeetingBriefViewModel.kindLabel(""))
    }
}
