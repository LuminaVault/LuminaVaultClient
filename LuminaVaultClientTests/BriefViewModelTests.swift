// LuminaVaultClient/LuminaVaultClientTests/BriefViewModelTests.swift
//
// The daily brief. What the client owns: the brief loads into cards in the
// server's order, a day without one is an empty state rather than a failure;
// 👍 / 👎 / dismiss post the right feedback, optimistically, and roll back
// with an inline error when the server says no; the Open loops card's
// commitments come from the open list, matched to its refs, and Done / Drop
// are a PATCH that takes one off the card and puts it back on failure.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class BriefViewModelTests: XCTestCase {
    private struct Boom: Error {}

    private func makeSUT(
        brief: BriefDTO? = .fixture(),
        loadFails: Bool = false
    ) -> (BriefViewModel, MockBriefClient, MockCommitmentsClient) {
        let client = MockBriefClient(brief)
        if loadFails { client.result = .failure(Boom()) }
        let commitments = MockCommitmentsClient()
        let vm = BriefViewModel(
            client: client,
            commitmentsClient: commitments,
            now: { CommitmentDTO.fixtureNow },
            locale: Locale(identifier: "en_US")
        )
        return (vm, client, commitments)
    }

    private func card(_ id: String, in vm: BriefViewModel) throws -> BriefCardDTO {
        try XCTUnwrap(vm.cards.first { $0.id == id })
    }

    // MARK: - Load

    func testLoadKeepsTheServersOrderAndAsksForToday() async {
        let (vm, client, _) = makeSUT()
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.cards.map(\.id), ["today", "openLoops", "toRevisit", "weather"])
        XCTAssertEqual(vm.count, 4)
        XCTAssertFalse(vm.isEmpty)
        XCTAssertEqual(client.requestedDates, [nil], "today in the user's timezone is the server's call")
        XCTAssertEqual(vm.brief?.endNote, "That's it for today.")
        XCTAssertEqual(vm.dateText, "Tuesday, October 20")
    }

    func testNoBriefIsLoadedAndEmpty() async {
        let (vm, _, commitments) = makeSUT(brief: nil)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertTrue(vm.isEmpty)
        XCTAssertEqual(vm.count, 0)
        XCTAssertTrue(commitments.requestedStates.isEmpty, "no cards, no loops to read")
    }

    func testAFailedFirstLoadFails() async {
        let (vm, _, _) = makeSUT(loadFails: true)
        await vm.load()
        guard case .failed = vm.phase else { return XCTFail("expected .failed, got \(vm.phase)") }
    }

    func testAFailedRefreshKeepsWhatIsOnScreen() async {
        let (vm, client, _) = makeSUT()
        await vm.load()
        client.result = .failure(Boom())
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.count, 4)
    }

    func testTheOpenLoopsCardShowsItsOpenCommitmentsInTheCardsOrder() async throws {
        let (vm, _, commitments) = makeSUT()
        await vm.load()
        XCTAssertEqual(commitments.requestedStates, [.open])
        let loops = try XCTUnwrap(vm.commitments(for: try card("openLoops", in: vm)))
        XCTAssertEqual(loops.map(\.id), [CommitmentDTO.sendDeckID, CommitmentDTO.callMomID, CommitmentDTO.renewID])
        XCTAssertEqual(vm.commitments(for: try card("weather", in: vm))?.count, 0, "no refs, no loops")
    }

    func testACommitmentNoLongerOpenIsLeftOffTheCard() async throws {
        let (vm, _, commitments) = makeSUT()
        commitments.results[.open] = .success(CommitmentsResponse(items: [CommitmentDTO.openFixtures[2]]))
        await vm.load()
        let loops = try XCTUnwrap(vm.commitments(for: try card("openLoops", in: vm)))
        XCTAssertEqual(loops.map(\.id), [CommitmentDTO.renewID])
    }

    func testWhenTheLoopsCannotBeReadTheCardFallsBackToItsBody() async throws {
        let (vm, _, commitments) = makeSUT()
        commitments.results[.open] = .failure(Boom())
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertNil(vm.commitments(for: try card("openLoops", in: vm)))
    }

    func testHomesPassiveLoadLeavesTheCommitmentsAlone() async {
        let (vm, _, commitments) = makeSUT()
        await vm.load(includeCommitments: false)
        XCTAssertEqual(vm.count, 4)
        XCTAssertTrue(commitments.requestedStates.isEmpty)
    }

    func testRefsSayWhatACardCanOpen() async throws {
        let (vm, _, _) = makeSUT()
        await vm.load()
        XCTAssertEqual(vm.memoryIDs(for: try card("toRevisit", in: vm)), [BriefDTO.revisitMemoryID])
        XCTAssertTrue(vm.memoryIDs(for: try card("today", in: vm)).isEmpty, "events open nothing yet")
        XCTAssertTrue(vm.hasCommitments(try card("openLoops", in: vm)))
        XCTAssertFalse(vm.hasCommitments(try card("weather", in: vm)))
    }

    // MARK: - Feedback

    func testThumbsUpPostsUpForThatCard() async throws {
        let (vm, client, _) = makeSUT()
        await vm.load()
        await vm.react(.up, to: try card("weather", in: vm))
        let call = try XCTUnwrap(client.feedbackCalls.first)
        XCTAssertEqual(client.feedbackCalls.count, 1)
        XCTAssertEqual(call.briefID, BriefDTO.fixtureID)
        XCTAssertEqual(call.cardID, "weather")
        XCTAssertEqual(call.action, .up)
        XCTAssertEqual(vm.reactions["weather"], .up)
        XCTAssertEqual(vm.count, 4, "a reaction keeps the card")
    }

    func testThumbsDownReplacesUpAndTheSameReactionTwiceIsNotResent() async throws {
        let (vm, client, _) = makeSUT()
        await vm.load()
        let weather = try card("weather", in: vm)
        await vm.react(.up, to: weather)
        await vm.react(.up, to: weather)
        await vm.react(.down, to: weather)
        XCTAssertEqual(client.feedbackCalls.map(\.action), [.up, .down])
        XCTAssertEqual(vm.reactions["weather"], .down)
    }

    func testAFailedReactionGoesBackToWhatItWasWithAnError() async throws {
        let (vm, client, _) = makeSUT()
        await vm.load()
        let weather = try card("weather", in: vm)
        await vm.react(.up, to: weather)
        client.feedbackError = Boom()
        await vm.react(.down, to: weather)
        XCTAssertEqual(vm.reactions["weather"], .up, "rolled back to the last confirmed reaction")
        XCTAssertEqual(vm.errorMessage(forCard: "weather"), BriefViewModel.failureMessage)
        XCTAssertNil(vm.errorMessage(forCard: "today"))
    }

    func testDismissTakesTheCardAwayAndPostsDismiss() async throws {
        let (vm, client, _) = makeSUT()
        await vm.load()
        await vm.dismiss(try card("toRevisit", in: vm))
        XCTAssertEqual(vm.cards.map(\.id), ["today", "openLoops", "weather"])
        XCTAssertEqual(vm.count, 3)
        XCTAssertEqual(client.feedbackCalls.map(\.action), [.dismiss])
        XCTAssertEqual(client.feedbackCalls.first?.cardID, "toRevisit")
    }

    func testReactingWithDismissIsADismiss() async throws {
        let (vm, client, _) = makeSUT()
        await vm.load()
        await vm.react(.dismiss, to: try card("today", in: vm))
        XCTAssertEqual(vm.cards.map(\.id), ["openLoops", "toRevisit", "weather"])
        XCTAssertEqual(client.feedbackCalls.map(\.action), [.dismiss])
    }

    func testADismissLeavesBeforeTheServerAnswers() async throws {
        let blocking = BlockingBriefClient(brief: .fixture())
        let vm = BriefViewModel(client: blocking, commitmentsClient: MockCommitmentsClient())
        await vm.load()
        let weather = try card("weather", in: vm)
        let answer = Task { await vm.dismiss(weather) }
        await waitUntil("the dismiss is in flight") { vm.pendingCardIDs.contains("weather") }
        XCTAssertFalse(vm.cards.contains { $0.id == "weather" }, "optimistic: gone while the POST is in flight")
        blocking.release()
        await answer.value
        XCTAssertTrue(vm.pendingCardIDs.isEmpty)
        XCTAssertEqual(vm.count, 3)
    }

    func testAFailedDismissPutsTheCardBackWhereItWasWithAnError() async throws {
        let (vm, client, _) = makeSUT()
        await vm.load()
        client.feedbackError = Boom()
        await vm.dismiss(try card("openLoops", in: vm))
        XCTAssertEqual(vm.cards.map(\.id), ["today", "openLoops", "toRevisit", "weather"])
        XCTAssertEqual(vm.errorMessage(forCard: "openLoops"), BriefViewModel.failureMessage)
    }

    func testAnotherBriefClearsTheReactions() async throws {
        let (vm, client, _) = makeSUT()
        await vm.load()
        await vm.react(.up, to: try card("weather", in: vm))
        let tomorrow = BriefDTO(
            id: UUID(),
            date: "2026-10-21",
            cards: BriefDTO.fixture().cards,
            endNote: "That's it for today.",
            createdAt: Date(timeIntervalSince1970: 1_792_566_000)
        )
        client.result = .success(MeBriefResponse(brief: tomorrow))
        await vm.load()
        XCTAssertTrue(vm.reactions.isEmpty)
        XCTAssertEqual(vm.dateText, "Wednesday, October 21")
    }

    // MARK: - Open loops

    func testDonePatchesTheCommitmentDoneAndTakesItOffTheCard() async throws {
        let (vm, _, commitments) = makeSUT()
        await vm.load()
        let deck = try XCTUnwrap(vm.commitments(for: try card("openLoops", in: vm))?.first)
        await vm.markDone(deck)
        let call = try XCTUnwrap(commitments.updateCalls.first)
        XCTAssertEqual(call.id, CommitmentDTO.sendDeckID)
        XCTAssertEqual(call.state, .done)
        let left = try XCTUnwrap(vm.commitments(for: try card("openLoops", in: vm)))
        XCTAssertEqual(left.map(\.id), [CommitmentDTO.callMomID, CommitmentDTO.renewID])
    }

    func testDropPatchesTheCommitmentDropped() async throws {
        let (vm, _, commitments) = makeSUT()
        await vm.load()
        let passport = try XCTUnwrap(vm.commitments(for: try card("openLoops", in: vm))?.last)
        await vm.drop(passport)
        XCTAssertEqual(commitments.updateCalls.map(\.state), [.dropped])
        XCTAssertEqual(vm.commitments(for: try card("openLoops", in: vm))?.count, 2)
    }

    func testAFailedDonePutsTheLoopBackWithAnError() async throws {
        let (vm, _, commitments) = makeSUT()
        await vm.load()
        commitments.updateError = Boom()
        let deck = try XCTUnwrap(vm.commitments(for: try card("openLoops", in: vm))?.first)
        await vm.markDone(deck)
        XCTAssertEqual(vm.commitments(for: try card("openLoops", in: vm))?.first?.id, CommitmentDTO.sendDeckID)
        XCTAssertEqual(vm.errorMessage(forCommitment: deck.id), CommitmentCopy.saveFailed)
    }

    func testAConflictSaysSoInPlainWords() async throws {
        let (vm, _, commitments) = makeSUT()
        await vm.load()
        commitments.updateError = APIError.httpError(statusCode: 409, data: Data())
        let deck = try XCTUnwrap(vm.commitments(for: try card("openLoops", in: vm))?.first)
        await vm.drop(deck)
        XCTAssertEqual(vm.errorMessage(forCommitment: deck.id), CommitmentCopy.alreadyOpen)
    }

    func testRereadingTheLoopsBringsBackOneReopenedElsewhere() async throws {
        let (vm, _, _) = makeSUT()
        await vm.load()
        let deck = try XCTUnwrap(vm.commitments(for: try card("openLoops", in: vm))?.first)
        await vm.markDone(deck)
        XCTAssertEqual(vm.commitments(for: try card("openLoops", in: vm))?.count, 2)
        // Reopened from the full list: it is in the open list again.
        await vm.loadCommitments()
        XCTAssertEqual(vm.commitments(for: try card("openLoops", in: vm))?.count, 3)
    }

    // MARK: - Copy

    func testTheDateIsTheBriefsOwnDayInAnyZone() async {
        // `2026-10-20` is a calendar day: it must not slip to the 19th west
        // of UTC.
        XCTAssertEqual(
            BriefViewModel.dateText(for: "2026-10-20", now: .distantPast, locale: Locale(identifier: "en_US")),
            "Tuesday, October 20"
        )
        XCTAssertNil(BriefViewModel.parseDay("not-a-day"))
    }
}

/// Holds the feedback POST until released, to see the optimistic state.
/// Main-actor isolated so its gate is never touched off the main actor; the
/// protocol's requirements hop onto it.
@MainActor
private final class BlockingBriefClient: BriefClientProtocol {
    private let fixture: BriefDTO
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    init(brief: BriefDTO) {
        fixture = brief
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }

    nonisolated func brief(date _: String?) async throws -> MeBriefResponse {
        MeBriefResponse(brief: fixture)
    }

    nonisolated func feedback(briefID _: UUID, cardID _: String, action _: BriefCardFeedbackAction) async throws {
        await wait()
    }

    private func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
