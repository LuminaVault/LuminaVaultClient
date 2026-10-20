// LuminaVaultClient/LuminaVaultClientTests/LearnedThisWeekViewModelTests.swift
//
// "What I learned this week". What the client owns: the digest loads into
// two lists; Keep / Forget on a memory is a PATCH with the right review
// state and on a SOUL change an approve / reject; answers are optimistic and
// roll back, with an inline error, when the server says no; and an empty
// digest is an empty state rather than a failure.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class LearnedThisWeekViewModelTests: XCTestCase {
    private struct Boom: Error {}

    private func makeSUT(
        digest: LearnedDigestResponse = .fixture(),
        loadFails: Bool = false
    ) -> (LearnedThisWeekViewModel, MockLearnedClient, MockMemoryClient, MockSelfImprovementClient) {
        let client = MockLearnedClient(digest)
        if loadFails { client.result = .failure(Boom()) }
        let memoryClient = MockMemoryClient()
        memoryClient.patchResult = .success(.learnedFixture())
        let improvementClient = MockSelfImprovementClient()
        let vm = LearnedThisWeekViewModel(
            client: client,
            memoryClient: memoryClient,
            improvementClient: improvementClient
        )
        return (vm, client, memoryClient, improvementClient)
    }

    // MARK: - Load

    func testLoadFillsBothSectionsAndAsksForTheDefaultWindow() async {
        let (vm, client, _, _) = makeSUT()
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.soulChanges.count, 2)
        XCTAssertEqual(vm.memories.count, 2)
        XCTAssertEqual(vm.count, 4)
        XCTAssertFalse(vm.isEmpty)
        XCTAssertEqual(client.requestedSince, [nil], "the server picks the last 7 days")
        XCTAssertNotNil(vm.rangeText)
    }

    func testAnEmptyDigestIsLoadedAndEmpty() async {
        let (vm, _, _, _) = makeSUT(digest: .empty)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertTrue(vm.isEmpty)
        XCTAssertEqual(vm.count, 0)
    }

    func testAFailedFirstLoadFails() async {
        let (vm, _, _, _) = makeSUT(loadFails: true)
        await vm.load()
        guard case .failed = vm.phase else { return XCTFail("expected .failed, got \(vm.phase)") }
    }

    func testAFailedRefreshKeepsWhatIsOnScreen() async {
        let (vm, client, _, _) = makeSUT()
        await vm.load()
        client.result = .failure(Boom())
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.count, 4)
    }

    // MARK: - Memories

    func testKeepingAMemoryPatchesItApproved() async throws {
        let memory = LearnedMemoryDTO.fixture()
        let (vm, _, memoryClient, _) = makeSUT(digest: .fixture(soulChanges: [], memories: [memory]))
        await vm.load()
        await vm.keep(memory)
        let call = try XCTUnwrap(memoryClient.patchCalls.first)
        XCTAssertEqual(memoryClient.patchCalls.count, 1)
        XCTAssertEqual(call.id, memory.id)
        XCTAssertEqual(call.request.reviewState, "approved")
        XCTAssertNil(call.request.content, "keep changes nothing but the review state")
        XCTAssertTrue(vm.memories.isEmpty)
        XCTAssertTrue(vm.isEmpty)
    }

    func testForgettingAMemoryPatchesItRejected() async throws {
        let memory = LearnedMemoryDTO.fixture()
        let (vm, _, memoryClient, _) = makeSUT(digest: .fixture(soulChanges: [], memories: [memory]))
        await vm.load()
        await vm.forget(memory)
        XCTAssertEqual(try XCTUnwrap(memoryClient.patchCalls.first).request.reviewState, "rejected")
        XCTAssertTrue(vm.memories.isEmpty)
    }

    func testAMemoryLeavesTheListBeforeTheServerAnswers() async {
        let memory = LearnedMemoryDTO.fixture()
        let blocking = BlockingMemoryClient()
        let sut = LearnedThisWeekViewModel(
            client: MockLearnedClient(.fixture(soulChanges: [], memories: [memory])),
            memoryClient: blocking,
            improvementClient: MockSelfImprovementClient()
        )
        await sut.load()
        let answer = Task { await sut.keep(memory) }
        await waitUntil("the PATCH is in flight") { sut.pendingIDs.contains(memory.id) }
        XCTAssertTrue(sut.memories.isEmpty, "optimistic: gone while the PATCH is in flight")
        blocking.release()
        await answer.value
        XCTAssertTrue(sut.pendingIDs.isEmpty)
        XCTAssertTrue(sut.memories.isEmpty)
    }

    func testAFailedMemoryAnswerPutsItBackWhereItWasWithAnError() async {
        let first = LearnedMemoryDTO.fixture(snippet: "first")
        let second = LearnedMemoryDTO.fixture(snippet: "second")
        let (vm, _, memoryClient, _) = makeSUT(digest: .fixture(soulChanges: [], memories: [first, second]))
        memoryClient.patchResult = .failure(Boom())
        await vm.load()
        await vm.forget(first)
        XCTAssertEqual(vm.memories.map(\.id), [first.id, second.id])
        XCTAssertEqual(vm.errorMessage(for: first.id), LearnedThisWeekViewModel.failureMessage)
        XCTAssertNil(vm.errorMessage(for: second.id))
        XCTAssertTrue(vm.pendingIDs.isEmpty)
    }

    func testRetryingClearsTheError() async {
        let memory = LearnedMemoryDTO.fixture()
        let (vm, _, memoryClient, _) = makeSUT(digest: .fixture(soulChanges: [], memories: [memory]))
        memoryClient.patchResult = .failure(Boom())
        await vm.load()
        await vm.keep(memory)
        XCTAssertNotNil(vm.actionFailure)
        memoryClient.patchResult = .success(.learnedFixture())
        await vm.keep(memory)
        XCTAssertNil(vm.actionFailure)
        XCTAssertTrue(vm.memories.isEmpty)
    }

    // MARK: - SOUL changes

    func testKeepingASoulChangeApprovesIt() async throws {
        let change = LearnedSoulChangeDTO.fixture()
        let (vm, _, memoryClient, improvement) = makeSUT(digest: .fixture(soulChanges: [change], memories: []))
        await vm.load()
        await vm.keep(change)
        let call = try XCTUnwrap(improvement.decideCalls.first)
        XCTAssertEqual(improvement.decideCalls.count, 1)
        XCTAssertEqual(call.id, change.id)
        XCTAssertTrue(call.approve)
        XCTAssertTrue(memoryClient.patchCalls.isEmpty)
        XCTAssertTrue(vm.soulChanges.isEmpty)
    }

    func testForgettingASoulChangeRejectsIt() async throws {
        let change = LearnedSoulChangeDTO.fixture()
        let (vm, _, _, improvement) = makeSUT(digest: .fixture(soulChanges: [change], memories: []))
        await vm.load()
        await vm.forget(change)
        XCTAssertEqual(try XCTUnwrap(improvement.decideCalls.first).approve, false)
        XCTAssertTrue(vm.soulChanges.isEmpty)
    }

    func testAFailedSoulAnswerRollsBack() async {
        let change = LearnedSoulChangeDTO.fixture()
        let (vm, _, _, improvement) = makeSUT(digest: .fixture(soulChanges: [change], memories: []))
        improvement.decideError = Boom()
        await vm.load()
        await vm.keep(change)
        XCTAssertEqual(vm.soulChanges.map(\.id), [change.id])
        XCTAssertEqual(vm.errorMessage(for: change.id), LearnedThisWeekViewModel.failureMessage)
    }

    func testAnsweringEverythingLeavesItEmpty() async {
        let (vm, _, _, _) = makeSUT()
        await vm.load()
        for change in vm.soulChanges { await vm.forget(change) }
        for memory in vm.memories { await vm.keep(memory) }
        XCTAssertTrue(vm.isEmpty)
        XCTAssertEqual(vm.count, 0)
    }

    // MARK: - Home

    func testHomeCountsWhatIsLeftAndNothingBeforeItLoads() async {
        let (learned, _, _, _) = makeSUT()
        let glance = HomeGlanceViewModel(
            homeClient: MockHomeSummaryClient(),
            resurface: nil,
            pendingClient: MockKBCompileClient(),
            learned: learned
        )
        XCTAssertEqual(glance.learnedCount, 0)
        await glance.load()
        XCTAssertEqual(glance.learnedCount, 4)
        await learned.forget(learned.memories[0])
        XCTAssertEqual(glance.learnedCount, 3, "an answer in the sheet comes straight back to the row")
    }

    // MARK: - Copy

    func testRangeTextReadsAsTwoShortDates() {
        let text = LearnedThisWeekViewModel.rangeText(
            since: Date(timeIntervalSince1970: 1_791_547_200),
            until: Date(timeIntervalSince1970: 1_792_152_000),
            locale: Locale(identifier: "en_US"),
            timeZone: .gmt
        )
        XCTAssertEqual(text, "Oct 9 – Oct 16")
    }
}

/// A memory client whose PATCH waits until the test lets it go, so the
/// optimistic state can be looked at mid-flight.
@MainActor
private final class BlockingMemoryClient: MemoryClientProtocol {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }

    nonisolated func patch(id: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO {
        await wait()
        return .learnedFixture(id: id)
    }

    private func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    nonisolated func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse { throw APIError.unauthorized }
    nonisolated func get(id _: UUID) async throws -> MemoryDTO { throw APIError.unauthorized }
    nonisolated func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse { throw APIError.unauthorized }
    nonisolated func search(_: MemorySearchRequest) async throws -> MemorySearchResponse { throw APIError.unauthorized }
    nonisolated func delete(id _: UUID) async throws { throw APIError.unauthorized }
}
