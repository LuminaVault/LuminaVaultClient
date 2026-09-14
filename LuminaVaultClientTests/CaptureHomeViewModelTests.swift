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

    // MARK: - Filing into a Space

    func testACaptureIsFiledIntoTheSelectedSpace() async throws {
        // Without this the fast path could only ever write to the vault root,
        // which made Spaces something you had to go and fix afterwards.
        let queue = StubCaptureQueue()
        let spaceID = UUID()
        let vm = makeVM(queue: queue)
        vm.availableSpaces = [Self.space(id: spaceID, name: "Work", slug: "work")]
        vm.selectedSpaceID = spaceID
        vm.text = "a note for work"

        await vm.submit()

        let snapshots = await queue.snapshot()
        let snap = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snap.spaceID, spaceID)
    }

    func testAVoiceNoteIsFiledIntoTheSelectedSpaceToo() async throws {
        let queue = HoldingCaptureQueue()
        let spaceID = UUID()
        let vm = makeVM(queue: queue)
        vm.availableSpaces = [Self.space(id: spaceID, name: "Work", slug: "work")]
        vm.selectedSpaceID = spaceID

        await vm.enqueueVoice(Data("audio".utf8))

        let row = try XCTUnwrap(vm.pending.first)
        XCTAssertTrue(row.predictedPath.hasPrefix("work/"), "got \(row.predictedPath)")
    }

    func testThePredictedPathFollowsTheSpaceFolder() async throws {
        // The server keeps only the basename and files it under the Space's
        // slug, so a row filed into a Space that still predicted `inbox/` would
        // never match the real file and would linger on screen.
        let spaceID = UUID()
        let vm = makeVM(queue: HoldingCaptureQueue())
        vm.availableSpaces = [Self.space(id: spaceID, name: "Work", slug: "work")]
        vm.selectedSpaceID = spaceID
        vm.text = "filed"

        await vm.submit()

        let row = try XCTUnwrap(vm.pending.first)
        XCTAssertEqual(row.predictedPath, "work/\(row.id.uuidString).md")
    }

    func testUnfiledStillPredictsInbox() async throws {
        let vm = makeVM(queue: HoldingCaptureQueue())
        vm.selectedSpaceID = nil
        vm.text = "unfiled"

        await vm.submit()

        let row = try XCTUnwrap(vm.pending.first)
        XCTAssertEqual(row.predictedPath, "inbox/\(row.id.uuidString).md")
    }

    private static func space(id: UUID, name: String, slug: String) -> SpaceDTO {
        SpaceDTO(id: id, name: name, slug: slug, description: nil, color: nil, icon: nil)
    }

    // MARK: - Captures that fail

    func testAFailedCaptureIsNotMistakenForASavedOne() async throws {
        // The bug this guards: `pending()` filters on state, so a row that
        // exhausted its retries leaves it exactly like a drained one does.
        // Reading that as success removed the row and left no file anywhere —
        // the capture vanished with no error.
        let queue = HoldingCaptureQueue()
        let vm = makeVM(queue: queue)
        vm.text = "something I do not want to lose"
        await vm.submit()

        let row = try XCTUnwrap(vm.pending.first)
        await queue.fail(id: row.id, reason: "The server said no.")
        await vm.loadFeed()

        let stillThere = try XCTUnwrap(vm.pending.first)
        XCTAssertTrue(stillThere.hasFailed, "a failed capture must not disappear")
        XCTAssertEqual(stillThere.failure, "The server said no.")
        XCTAssertEqual(vm.visiblePending.count, 1, "and it must still be on screen")
    }

    func testAFailedRowStaysVisibleEvenOnceTheListingMovesOn() async throws {
        // `visiblePending` hides rows the feed already lists. A failed row has
        // no file to be listed, so that filter must not apply to it.
        let vaultClient = MockVaultClient()
        let queue = HoldingCaptureQueue()
        let vm = makeVM(queue: queue, vaultClient: vaultClient)
        vm.text = "a note"
        await vm.submit()
        let row = try XCTUnwrap(vm.pending.first)
        await queue.fail(id: row.id, reason: "offline")

        vaultClient.listFilesResult = .success(
            VaultFileListResponse(
                files: [
                    VaultFileDTO(
                        id: UUID(),
                        path: row.predictedPath,
                        contentType: "text/markdown",
                        sizeBytes: 6,
                        sha256: ""
                    ),
                ],
                limit: 50,
                nextBefore: nil
            )
        )
        await vm.loadFeed()

        XCTAssertEqual(vm.visiblePending.count, 1)
    }

    func testRetryPutsTheCaptureBackInTheQueue() async throws {
        let queue = HoldingCaptureQueue()
        let vm = makeVM(queue: queue)
        vm.text = "worth another go"
        await vm.submit()
        let row = try XCTUnwrap(vm.pending.first)
        await queue.fail(id: row.id, reason: "timed out")
        await vm.loadFeed()

        await vm.retry(try XCTUnwrap(vm.pending.first))

        let queued = try await queue.pending()
        XCTAssertEqual(queued.map(\.id), [row.id], "the original capture is retried, not re-typed")
        let stillFailed = try await queue.failed()
        XCTAssertTrue(stillFailed.isEmpty)
    }

    func testDiscardDeletesTheCapture() async throws {
        let queue = HoldingCaptureQueue()
        let vm = makeVM(queue: queue)
        vm.text = "give up on this"
        await vm.submit()
        let row = try XCTUnwrap(vm.pending.first)
        await queue.fail(id: row.id, reason: "nope")
        await vm.loadFeed()

        await vm.discard(try XCTUnwrap(vm.pending.first))

        XCTAssertTrue(vm.pending.isEmpty)
        let count = try await queue.count()
        XCTAssertEqual(count, 0, "discard is the only thing that throws the capture away")
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

    func testAPendingRowIsHiddenOnceTheFeedIsShowingTheRealFile() async throws {
        // The row is dropped when its queue entry goes, but the feed may have
        // refetched first. Showing both for a moment reads as a duplicate save.
        let vaultClient = MockVaultClient()
        let vm = makeVM(queue: HoldingCaptureQueue(), vaultClient: vaultClient)
        vm.text = "a note"
        await vm.submit()

        let row = try XCTUnwrap(vm.pending.first)
        XCTAssertEqual(vm.visiblePending.count, 1, "not listed yet, so it must be visible")

        vaultClient.listFilesResult = .success(
            VaultFileListResponse(
                files: [
                    VaultFileDTO(
                        id: UUID(),
                        path: row.predictedPath,
                        contentType: "text/markdown",
                        sizeBytes: 6,
                        sha256: ""
                    ),
                ],
                limit: 50,
                nextBefore: nil
            )
        )
        await vm.files.load()

        XCTAssertTrue(vm.visiblePending.isEmpty, "the real row supersedes the placeholder")
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
    private var failedRows: [CaptureRowSnapshot] = []

    /// Mirrors the real queue: a row that exhausts its retries moves out of
    /// `pending()` and into `failed()`. That is exactly the transition the view
    /// model used to read as a successful save.
    func fail(id: UUID, reason: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        var row = rows.remove(at: index)
        row.lastError = reason
        failedRows.append(row)
    }

    func failed() async throws -> [CaptureRowSnapshot] { failedRows }

    func retry(id: UUID) async throws {
        guard let index = failedRows.firstIndex(where: { $0.id == id }) else { return }
        var row = failedRows.remove(at: index)
        row.lastError = nil
        rows.append(row)
    }
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
    func delete(id: UUID) async throws {
        rows.removeAll { $0.id == id }
        failedRows.removeAll { $0.id == id }
    }
    func markFailure(id _: UUID, error _: String, flipToFailed _: Bool) async throws {}
    func count() async throws -> Int { rows.count + failedRows.count }
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
