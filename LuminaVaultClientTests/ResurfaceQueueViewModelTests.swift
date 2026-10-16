// LuminaVaultClient/LuminaVaultClientTests/ResurfaceQueueViewModelTests.swift
//
// The "To revisit" card. What the client owns: answering moves on to the
// next memory without a refetch, the card goes once the queue is empty, an
// answer that fails leaves the memory where it was, the sentence after an
// answer says when it comes back, and the widget hears about every change.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class ResurfaceQueueViewModelTests: XCTestCase {
    private struct Boom: Error {}

    private static let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeSUT(
        items: [ResurfaceItemDTO] = [.fixture(snippet: "a"), .fixture(snippet: "b"), .fixture(snippet: "c")],
        loadFails: Bool = false
    ) -> (ResurfaceQueueViewModel, MockResurfaceClient, MockMemoryClient, PublishRecorder) {
        let resurfaceClient = MockResurfaceClient()
        resurfaceClient.result = loadFails ? .failure(Boom()) : .success(ResurfaceResponse(items: items))
        let memoryClient = MockMemoryClient()
        memoryClient.reviewResult = .success(
            MemoryReviewResponse(memoryId: UUID(), reviewedAt: Self.now, reviewCount: 1)
        )
        let recorder = PublishRecorder()
        let sut = ResurfaceQueueViewModel(
            resurfaceClient: resurfaceClient,
            memoryClient: memoryClient,
            publish: { recorder.published.append($0.map(\.snippet)) },
            now: { Self.now }
        )
        return (sut, resurfaceClient, memoryClient, recorder)
    }

    func testLoadAsksForThreeAndShowsTheFirst() async {
        let (sut, client, _, recorder) = makeSUT()
        XCTAssertEqual(sut.phase, .loading)
        XCTAssertFalse(sut.showsCard)
        await sut.load()
        XCTAssertEqual(client.requestedLimits, [3])
        XCTAssertEqual(sut.current?.snippet, "a")
        XCTAssertTrue(sut.showsCard)
        XCTAssertEqual(recorder.published, [["a", "b", "c"]])
    }

    func testAnAnswerPostsItAndMovesToTheNextWithoutRefetching() async {
        let (sut, client, memoryClient, recorder) = makeSUT()
        await sut.load()
        let first = sut.items[0]
        await sut.perform(.soon, on: first)
        XCTAssertEqual(memoryClient.reviewCalls.map(\.id), [first.memoryId])
        XCTAssertEqual(memoryClient.reviewCalls.map(\.action), [.soon])
        XCTAssertEqual(sut.current?.snippet, "b")
        XCTAssertEqual(client.requestedLimits.count, 1)
        XCTAssertEqual(recorder.published.last, ["b", "c"])
        XCTAssertNil(sut.pendingMemoryID)
    }

    func testTheCardGoesOnceTheQueueIsAnsweredOut() async {
        let (sut, _, _, recorder) = makeSUT(items: [.fixture(snippet: "only")])
        await sut.load()
        await sut.perform(.kept, on: sut.items[0])
        XCTAssertNil(sut.current)
        XCTAssertTrue(sut.showsCard, "the confirmation finishes showing first")
        sut.clearConfirmation()
        XCTAssertFalse(sut.showsCard)
        XCTAssertEqual(recorder.published.last, [], "the widget hears the queue is empty")
    }

    func testAFailedAnswerKeepsTheMemory() async {
        let (sut, _, memoryClient, recorder) = makeSUT()
        await sut.load()
        memoryClient.reviewResult = .failure(Boom())
        await sut.perform(.later, on: sut.items[0])
        XCTAssertEqual(sut.current?.snippet, "a")
        XCTAssertEqual(sut.items.count, 3)
        XCTAssertNotNil(sut.actionError)
        XCTAssertNil(sut.confirmation)
        XCTAssertEqual(recorder.published.count, 1, "nothing changed, nothing republished")
    }

    func testTheConfirmationUsesTheServersDate() async {
        let (sut, _, memoryClient, _) = makeSUT()
        await sut.load()
        memoryClient.reviewResult = .success(MemoryReviewResponse(
            memoryId: sut.items[0].memoryId,
            reviewedAt: Self.now,
            reviewCount: 1,
            nextReviewAt: Self.now.addingTimeInterval(3 * 86400)
        ))
        await sut.perform(.soon, on: sut.items[0])
        XCTAssertEqual(sut.confirmation, "See it again in 3 days")
    }

    func testConfirmationCopy() {
        let now = Self.now
        func days(_ n: Double) -> Date { now.addingTimeInterval(n * 86400) }
        XCTAssertEqual(ResurfaceQueueViewModel.confirmation(for: .soon, nextReviewAt: nil, now: now), "See it again in a few days")
        XCTAssertEqual(ResurfaceQueueViewModel.confirmation(for: .later, nextReviewAt: nil, now: now), "See it again in about a month")
        XCTAssertEqual(ResurfaceQueueViewModel.confirmation(for: .later, nextReviewAt: days(30), now: now), "See it again in about a month")
        XCTAssertEqual(ResurfaceQueueViewModel.confirmation(for: .soon, nextReviewAt: days(1), now: now), "See it again tomorrow")
        XCTAssertEqual(ResurfaceQueueViewModel.confirmation(for: .soon, nextReviewAt: days(2.2), now: now), "See it again in 3 days")
        XCTAssertEqual(ResurfaceQueueViewModel.confirmation(for: .later, nextReviewAt: days(14), now: now), "See it again in 2 weeks")
        XCTAssertEqual(ResurfaceQueueViewModel.confirmation(for: .later, nextReviewAt: days(90), now: now), "See it again in 3 months")
        XCTAssertEqual(ResurfaceQueueViewModel.confirmation(for: .never, nextReviewAt: nil, now: now), "Won't show this one again.")
        XCTAssertEqual(ResurfaceQueueViewModel.confirmation(for: .kept, nextReviewAt: nil, now: now), "Kept. It stays in your vault.")
    }

    func testAFailedFirstLoadFailsAndShowsNoCard() async {
        let (sut, _, _, recorder) = makeSUT(loadFails: true)
        await sut.load()
        guard case .failed = sut.phase else { return XCTFail("expected failed, got \(sut.phase)") }
        XCTAssertFalse(sut.showsCard)
        XCTAssertTrue(recorder.published.isEmpty, "a failed load must not blank the widget")
    }

    func testAFailedRefreshKeepsTheQueue() async {
        let (sut, client, _, _) = makeSUT()
        await sut.load()
        client.result = .failure(Boom())
        await sut.load()
        XCTAssertEqual(sut.phase, .loaded)
        XCTAssertEqual(sut.items.count, 3)
    }

    func testTheWidgetSnapshotCarriesSnippetAndWhy() {
        let item = ResurfaceItemDTO.fixture(snippet: "s", why: "Saved a year ago today")
        let snapshot = ResurfaceWidgetPublisher.snapshot(for: [item], at: Self.now)
        XCTAssertEqual(snapshot.items, [ResurfaceWidgetItem(memoryId: item.memoryId, snippet: "s", why: "Saved a year ago today")])
        XCTAssertEqual(snapshot.updatedAt, Self.now)
    }
}

@MainActor
private final class PublishRecorder {
    var published: [[String]] = []
}
