// LuminaVaultClient/LuminaVaultClientTests/CaptureConnectionsTests.swift
//
// "Connects to N memories" after a save.
//
// The chain is: the drainer lands a capture and announces the memory it
// became; Home hears it, asks what that memory is near, and shows a banner
// only when the answer is at least one. Zero is silence, not "0".

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class CaptureConnectionsTests: XCTestCase {
    // MARK: - Home

    private func makeSUT(
        memoryClient: (any MemoryClientProtocol)?,
        drainer: CaptureDrainerHandle = .noop
    ) -> CaptureHomeViewModel {
        CaptureHomeViewModel(
            queue: nil,
            drainer: drainer,
            vaultClient: MockVaultClient(),
            memoryClient: memoryClient
        )
    }

    func testALandedSaveWithNeighboursShowsTheBanner() async {
        let memoryID = UUID()
        let client = MockMemoryClient()
        let neighbours = [RelatedMemoryDTO.fixture(), .fixture(snippet: "Ship on Tuesdays")]
        client.relatedResult = .success(MemoryRelatedResponse(memoryId: memoryID, items: neighbours))
        let sut = makeSUT(memoryClient: client)

        await sut.noteOutcome(CaptureOutcome(localID: UUID(), memoryID: memoryID))

        XCTAssertEqual(sut.connections?.memoryID, memoryID)
        XCTAssertEqual(sut.connections?.count, 2)
        XCTAssertEqual(client.relatedCalls.first?.id, memoryID)
        XCTAssertEqual(client.relatedCalls.first?.limit, CaptureHomeViewModel.connectionsLimit)
    }

    func testNoNeighboursShowsNothing() async {
        let memoryID = UUID()
        let client = MockMemoryClient()
        client.relatedResult = .success(MemoryRelatedResponse(memoryId: memoryID, items: []))
        let sut = makeSUT(memoryClient: client)

        await sut.noteOutcome(CaptureOutcome(localID: UUID(), memoryID: memoryID))

        XCTAssertNil(sut.connections)
    }

    func testOnlyItselfCountsAsNothing() async {
        let memoryID = UUID()
        let client = MockMemoryClient()
        client.relatedResult = .success(MemoryRelatedResponse(memoryId: memoryID, items: [.fixture(id: memoryID)]))
        let sut = makeSUT(memoryClient: client)

        await sut.noteOutcome(CaptureOutcome(localID: UUID(), memoryID: memoryID))

        XCTAssertNil(sut.connections)
    }

    func testALinkHasNoMemoryYetAndAsksNothing() async {
        let client = MockMemoryClient()
        let sut = makeSUT(memoryClient: client)

        await sut.noteOutcome(CaptureOutcome(localID: UUID(), memoryID: nil))

        XCTAssertNil(sut.connections)
        XCTAssertTrue(client.relatedCalls.isEmpty)
    }

    func testAFailedLookupShowsNothing() async {
        let client = MockMemoryClient()
        let sut = makeSUT(memoryClient: client)

        await sut.noteOutcome(CaptureOutcome(localID: UUID(), memoryID: UUID()))

        XCTAssertNil(sut.connections)
    }

    func testTheBannerReplacesSavedButNeverAFailure() async {
        let memoryID = UUID()
        let client = MockMemoryClient()
        client.relatedResult = .success(MemoryRelatedResponse(memoryId: memoryID, items: [.fixture()]))
        let sut = makeSUT(memoryClient: client)

        sut.toast = .queuedOffline(count: 1)
        await sut.noteOutcome(CaptureOutcome(localID: UUID(), memoryID: memoryID))
        XCTAssertNil(sut.toast, "the connection is the better news")

        sut.toast = .failed("Couldn't save that.")
        await sut.noteOutcome(CaptureOutcome(localID: UUID(), memoryID: memoryID))
        XCTAssertNotNil(sut.toast, "a failure is the only sign a capture did not happen")
    }

    func testHomeHearsOutcomesFromTheDrainer() async throws {
        let memoryID = UUID()
        let client = MockMemoryClient()
        client.relatedResult = .success(MemoryRelatedResponse(memoryId: memoryID, items: [.fixture()]))
        let broadcaster = CaptureOutcomeBroadcaster()
        let sut = makeSUT(
            memoryClient: client,
            drainer: CaptureDrainerHandle(kick: {}, outcomes: { broadcaster.subscribe() })
        )

        let listening = Task { await sut.observeCaptureOutcomes() }
        defer { listening.cancel() }
        try await waitUntil { broadcaster.subscriberCount == 1 }

        broadcaster.publish(CaptureOutcome(localID: UUID(), memoryID: memoryID))

        try await waitUntil { sut.connections != nil }
        XCTAssertEqual(sut.connections?.memoryID, memoryID)
    }

    // MARK: - Broadcaster

    func testCancellingAListenerUnsubscribesIt() async throws {
        let broadcaster = CaptureOutcomeBroadcaster()
        let task = Task {
            for await _ in broadcaster.subscribe() {}
        }
        try await waitUntil { broadcaster.subscriberCount == 1 }
        task.cancel()
        try await waitUntil { broadcaster.subscriberCount == 0 }
    }

    func testEveryListenerHearsEveryOutcome() async throws {
        let broadcaster = CaptureOutcomeBroadcaster()
        var first = broadcaster.subscribe().makeAsyncIterator()
        var second = broadcaster.subscribe().makeAsyncIterator()
        let outcome = CaptureOutcome(localID: UUID(), memoryID: UUID())

        broadcaster.publish(outcome)

        let a = await first.next()
        let b = await second.next()
        XCTAssertEqual(a, outcome)
        XCTAssertEqual(b, outcome)
    }

    // MARK: - Drainer

    func testTheDrainerAnnouncesTheMemoryANoteBecame() async throws {
        let rowID = UUID()
        let memoryID = UUID()
        let broadcaster = CaptureOutcomeBroadcaster()
        let drainer = CaptureDrainer(
            queue: OneTextRowQueue(id: rowID),
            vaultUploader: NoteUploader(memoryID: memoryID),
            memoryClient: MockMemoryClient(),
            outcomes: broadcaster
        )
        var outcomes = broadcaster.subscribe().makeAsyncIterator()

        await drainer.tick()

        let outcome = await outcomes.next()
        XCTAssertEqual(outcome, CaptureOutcome(localID: rowID, memoryID: memoryID))
    }

    func testAFailedDrainAnnouncesNothing() async throws {
        let broadcaster = CaptureOutcomeBroadcaster()
        let drainer = CaptureDrainer(
            queue: OneTextRowQueue(id: UUID()),
            vaultUploader: NoteUploader(memoryID: nil, fails: true),
            memoryClient: MockMemoryClient(),
            outcomes: broadcaster
        )
        let stream = broadcaster.subscribe()

        await drainer.tick()

        // Nothing was published, so a later outcome is the first one heard.
        let marker = CaptureOutcome(localID: UUID(), memoryID: nil)
        broadcaster.publish(marker)
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, marker)
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("condition not met in time")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

// MARK: - Stubs

private actor OneTextRowQueue: CaptureQueueProtocol {
    private var rows: [CaptureRowSnapshot]

    init(id: UUID) {
        rows = [
            CaptureRowSnapshot(
            id: id,
            createdAt: .now,
            captionText: "Ship on Tuesdays",
            imageData: Data(),
            contentType: "text/markdown",
            fileExtension: "md",
            lat: nil,
            lng: nil,
            accuracyM: nil,
            placeName: nil,
            spaceID: nil,
            kind: .text,
            urlString: nil,
            attempts: 0
            ),
        ]
    }

    func enqueue(_: CaptureSnapshot) async throws {}
    func pending() async throws -> [CaptureRowSnapshot] { rows }
    func delete(id: UUID) async throws { rows.removeAll { $0.id == id } }
    func markFailure(id _: UUID, error _: String, flipToFailed _: Bool) async throws {}
    func count() async throws -> Int { rows.count }
}

private struct NoteUploader: VaultUploadClientProtocol {
    struct Boom: Error {}
    let memoryID: UUID?
    var fails = false

    func uploadAsset(
        data _: Data,
        contentType _: String,
        relativePath _: String,
        spaceID _: UUID?
    ) async throws -> VaultUploadResponse {
        throw Boom()
    }

    func uploadNote(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID _: UUID?,
        metadata _: VaultNoteMetadataDTO?
    ) async throws -> VaultUploadResponse {
        if fails { throw Boom() }
        return VaultUploadResponse(
            path: relativePath,
            size: data.count,
            contentType: contentType,
            sha256: "",
            memoryId: memoryID
        )
    }
}
