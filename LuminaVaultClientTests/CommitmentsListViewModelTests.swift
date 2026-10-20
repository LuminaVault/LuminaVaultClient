// LuminaVaultClient/LuminaVaultClientTests/CommitmentsListViewModelTests.swift
//
// "Open loops", the full list. Open by default; a segment is a read of that
// state; Done / Drop / Reopen are a PATCH that moves the row out of the
// segment at once and back, with an inline error, on failure — a 409 on
// Reopen in words a person can act on.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class CommitmentsListViewModelTests: XCTestCase {
    private struct Boom: Error {}

    private static let doneOne = CommitmentDTO.fixture(
        text: "Book the dentist",
        state: .done,
        doneAt: Date(timeIntervalSince1970: 1_792_324_800)
    )

    private func makeSUT() -> (CommitmentsListViewModel, MockCommitmentsClient) {
        let client = MockCommitmentsClient()
        client.results[.done] = .success(CommitmentsResponse(items: [Self.doneOne]))
        return (CommitmentsListViewModel(client: client), client)
    }

    func testOpenIsTheDefault() async {
        let (vm, client) = makeSUT()
        await vm.select(vm.segment)
        XCTAssertEqual(vm.segment, .open)
        XCTAssertEqual(client.requestedStates, [.open])
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.items.map(\.id), CommitmentDTO.openFixtures.map(\.id))
    }

    func testASegmentIsAReadOfThatState() async {
        let (vm, client) = makeSUT()
        await vm.load()
        await vm.select(.done)
        XCTAssertEqual(client.requestedStates, [.open, .done])
        XCTAssertEqual(vm.items.map(\.id), [Self.doneOne.id])
        await vm.select(.dropped)
        XCTAssertEqual(client.requestedStates.last, .dropped)
        XCTAssertTrue(vm.isEmpty)
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testAFailedFirstLoadFails() async {
        let (vm, client) = makeSUT()
        client.results[.open] = .failure(Boom())
        await vm.load()
        guard case .failed = vm.phase else { return XCTFail("expected .failed, got \(vm.phase)") }
    }

    func testDoneAndDropPatchTheStateAndLeaveTheOpenList() async throws {
        let (vm, client) = makeSUT()
        await vm.load()
        await vm.markDone(try XCTUnwrap(vm.items.first))
        await vm.drop(try XCTUnwrap(vm.items.last))
        XCTAssertEqual(client.updateCalls.map(\.state), [.done, .dropped])
        XCTAssertEqual(client.updateCalls.map(\.id), [CommitmentDTO.sendDeckID, CommitmentDTO.renewID])
        XCTAssertEqual(vm.items.map(\.id), [CommitmentDTO.callMomID])
    }

    func testReopenPatchesItOpen() async throws {
        let (vm, client) = makeSUT()
        await vm.select(.done)
        await vm.reopen(Self.doneOne)
        XCTAssertEqual(client.updateCalls.first?.state, .open)
        XCTAssertTrue(vm.isEmpty)
    }

    func testAReopenThatWouldDuplicateAnOpenLoopComesBackAndSaysWhy() async {
        let (vm, client) = makeSUT()
        await vm.select(.done)
        client.updateError = APIError.httpError(statusCode: 409, data: Data())
        await vm.reopen(Self.doneOne)
        XCTAssertEqual(vm.items.map(\.id), [Self.doneOne.id], "still closed, back where it was")
        XCTAssertEqual(vm.errorMessage(for: Self.doneOne.id), CommitmentCopy.alreadyOpen)
    }

    func testAnyOtherFailurePutsTheRowBackWithTheGenericError() async throws {
        let (vm, client) = makeSUT()
        await vm.load()
        client.updateError = Boom()
        let middle = vm.items[1]
        await vm.markDone(middle)
        XCTAssertEqual(vm.items.map(\.id), CommitmentDTO.openFixtures.map(\.id))
        XCTAssertEqual(vm.errorMessage(for: middle.id), CommitmentCopy.saveFailed)
        XCTAssertNil(vm.errorMessage(for: CommitmentDTO.sendDeckID))
    }

    func testAMissingCommitmentSaysItIsGone() async {
        XCTAssertEqual(
            CommitmentCopy.failureMessage(for: APIError.httpError(statusCode: 404, data: Data())),
            CommitmentCopy.gone
        )
    }

    func testDueTextReadsADueDayAsACalendarDay() async throws {
        var lisbon = Calendar(identifier: .gregorian)
        lisbon.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Lisbon"))
        let en = Locale(identifier: "en_US")
        let now = CommitmentDTO.fixtureNow // Tue Oct 20, 12:00 UTC
        XCTAssertEqual(CommitmentCopy.dueText(now, now: now, calendar: lisbon, locale: en).text, "Due today")
        XCTAssertEqual(
            CommitmentCopy.dueText(now.addingTimeInterval(86_400), now: now, calendar: lisbon, locale: en).text,
            "Due tomorrow"
        )
        let overdue = CommitmentCopy.dueText(now.addingTimeInterval(-2 * 86_400), now: now, calendar: lisbon, locale: en)
        XCTAssertTrue(overdue.isOverdue)
        XCTAssertEqual(overdue.text, "Overdue · Oct 18")

        // A date-only due day (12:00 UTC) seen from Honolulu is still that day.
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))
        let honoluluMorning = Date(timeIntervalSince1970: 1_792_526_400) // Oct 20, 10:00 HST
        XCTAssertEqual(CommitmentCopy.dueText(now, now: honoluluMorning, calendar: honolulu, locale: en).text, "Due today")
    }
}
