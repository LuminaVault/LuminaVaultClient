// LuminaVaultClient/LuminaVaultClientTests/CaptureHomeViewModelTests.swift
//
// What the Home composer decides to save, and what it does with what you
// typed.
//
// The routing decision is the interesting part and every way of getting it
// wrong is silent: a pasted link written as a note is a file containing a URL
// that nobody ever fetches, and a sentence *about* a link filed as a bare
// bookmark has thrown away the sentence. Neither throws.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class CaptureHomeViewModelTests: XCTestCase {
    private func makeVM(
        queue: CaptureQueueProtocol? = nil,
        drainer: CaptureDrainerHandle = .noop,
        vaultClient: MockVaultClient = MockVaultClient()
    ) -> CaptureHomeViewModel {
        CaptureHomeViewModel(
            queue: queue ?? StubCaptureQueue(),
            drainer: drainer,
            vaultClient: vaultClient
        )
    }

    // MARK: - What it saves

    func testASoleURLIsSavedAsALink() async throws {
        let queue = StubCaptureQueue()
        let vm = makeVM(queue: queue)
        vm.text = "  https://example.com/post  "

        XCTAssertNotNil(vm.detectedLink)
        await vm.submit()

        let snapshots = await queue.snapshot()
        let snap = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snap.kind, .url)
        XCTAssertEqual(snap.urlString, "https://example.com/post")
    }

    func testProseIsSavedAsANote() async throws {
        let queue = StubCaptureQueue()
        let vm = makeVM(queue: queue)
        vm.text = "Dentist moved to Thursday"

        XCTAssertNil(vm.detectedLink)
        await vm.submit()

        let snapshots = await queue.snapshot()
        let snap = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snap.kind, .text)
        XCTAssertEqual(snap.captionText, "Dentist moved to Thursday")
    }

    func testASentenceContainingALinkStaysANote() async throws {
        // Filing this as a bookmark would keep the URL and lose the thought,
        // which is the part the user actually wrote.
        let queue = StubCaptureQueue()
        let vm = makeVM(queue: queue)
        vm.text = "worth reading https://example.com/post before Friday"

        XCTAssertNil(vm.detectedLink)
        await vm.submit()

        let snapshots = await queue.snapshot()
        let snap = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snap.kind, .text)
        XCTAssertEqual(snap.captionText, "worth reading https://example.com/post before Friday")
    }

    func testANonFetchableSchemeIsNotPromotedToALink() async throws {
        let queue = StubCaptureQueue()
        let vm = makeVM(queue: queue)
        vm.text = "javascript:alert(1)"

        XCTAssertNil(vm.detectedLink, "only http(s) is something the server can fetch")
        await vm.submit()

        let snapshots = await queue.snapshot()
        let snap = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snap.kind, .text)
    }

    func testWhitespaceOnlyDoesNotEnqueue() async {
        let queue = StubCaptureQueue()
        let vm = makeVM(queue: queue)
        vm.text = "   \n\t "

        XCTAssertFalse(vm.canSave)
        await vm.submit()

        let snapshots = await queue.snapshot()
        XCTAssertTrue(snapshots.isEmpty)
    }

    // MARK: - The composer's own state

    func testTheDrainerIsKickedAndTheFieldCleared() async {
        let kicked = KickedFlag()
        let vm = makeVM(drainer: CaptureDrainerHandle(kick: { await kicked.set() }))
        vm.text = "something worth keeping"

        await vm.submit()

        let wasKicked = await kicked.value
        XCTAssertTrue(wasKicked, "an enqueued capture must not wait for the next launch")
        XCTAssertEqual(vm.text, "")
    }

    func testTextSurvivesAFailedSave() async {
        // Losing what someone just typed is worse than making them try again.
        let vm = makeVM(queue: ThrowingCaptureQueue())
        vm.text = "a thought worth keeping"

        await vm.submit()

        XCTAssertEqual(vm.text, "a thought worth keeping")
        XCTAssertTrue(vm.pending.isEmpty, "nothing was queued, so nothing should claim to be")
        if case .failed = vm.toast {} else { XCTFail("a failed save must say so") }
    }

    func testSavingIsBlockedUntilTheQueueExists() async {
        // The queue is nil until the vault is prepared. Accepting a capture
        // then would drop it silently.
        let vm = CaptureHomeViewModel(queue: nil, drainer: .noop, vaultClient: MockVaultClient())
        vm.text = "too early"

        XCTAssertFalse(vm.canSave)
        await vm.submit()

        XCTAssertEqual(vm.text, "too early")
    }

    // MARK: - Optimistic rows

    func testAPendingRowAppearsAndNamesWhatWasSaved() async throws {
        // `StubCaptureQueue.pending()` keeps rows queued, standing in for a
        // device that is offline: the row must stay visible.
        let vm = makeVM(queue: HoldingCaptureQueue())
        vm.text = "https://example.com/post"

        await vm.submit()

        let row = try XCTUnwrap(vm.pending.first)
        XCTAssertEqual(row.kind, .url)
        XCTAssertEqual(row.displayText, "example.com", "a link row is titled by its host")
    }

    func testAPendingNoteKnowsWhereItWillLand() async throws {
        // The snapshot id is the basename the drainer uploads under and the
        // server keeps only the basename, so the path is known before the
        // request is made. That is what makes reconciliation exact.
        let vm = makeVM(queue: HoldingCaptureQueue())
        vm.text = "a note"

        await vm.submit()

        let row = try XCTUnwrap(vm.pending.first)
        XCTAssertEqual(row.predictedPath, "inbox/\(row.id.uuidString).md")
    }

    func testAPendingRowClearsOnceTheQueueDrains() async {
        // The stub drops rows as soon as they are enqueued, which is what a
        // successful drain looks like from here.
        let vm = makeVM(queue: StubCaptureQueue())
        vm.text = "a note"

        await vm.submit()

        XCTAssertTrue(vm.pending.isEmpty, "a drained row must not linger as 'queued'")
    }
}

// MARK: - Stubs

/// Records what was enqueued and reports nothing pending, i.e. the drainer
/// always got there first.
private actor StubCaptureQueue: CaptureQueueProtocol {
    private var enqueued: [CaptureSnapshot] = []
    func snapshot() -> [CaptureSnapshot] { enqueued }
    func enqueue(_ snapshot: CaptureSnapshot) async throws { enqueued.append(snapshot) }
    func pending() async throws -> [CaptureRowSnapshot] { [] }
    func delete(id _: UUID) async throws {}
    func markFailure(id _: UUID, error _: String, flipToFailed _: Bool) async throws {}
    func count() async throws -> Int { enqueued.count }
}

/// Keeps everything queued — an offline device, where a pending row is the
/// only thing the user has to look at.
private actor HoldingCaptureQueue: CaptureQueueProtocol {
    private var rows: [CaptureRowSnapshot] = []
    func enqueue(_ snapshot: CaptureSnapshot) async throws {
        rows.append(
            CaptureRowSnapshot(
                id: snapshot.id,
                createdAt: snapshot.createdAt,
                captionText: snapshot.captionText,
                imageData: snapshot.imageData,
                contentType: snapshot.contentType,
                fileExtension: snapshot.fileExtension,
                lat: snapshot.lat,
                lng: snapshot.lng,
                accuracyM: snapshot.accuracyM,
                placeName: snapshot.placeName,
                spaceID: snapshot.spaceID,
                kind: snapshot.kind,
                urlString: snapshot.urlString,
                attempts: 0
            )
        )
    }
    func pending() async throws -> [CaptureRowSnapshot] { rows }
    func delete(id _: UUID) async throws {}
    func markFailure(id _: UUID, error _: String, flipToFailed _: Bool) async throws {}
    func count() async throws -> Int { rows.count }
}

private actor ThrowingCaptureQueue: CaptureQueueProtocol {
    struct EnqueueError: Error {}
    func enqueue(_: CaptureSnapshot) async throws { throw EnqueueError() }
    func pending() async throws -> [CaptureRowSnapshot] { [] }
    func delete(id _: UUID) async throws {}
    func markFailure(id _: UUID, error _: String, flipToFailed _: Bool) async throws {}
    func count() async throws -> Int { 0 }
}

private actor KickedFlag {
    private(set) var value = false
    func set() { value = true }
}
