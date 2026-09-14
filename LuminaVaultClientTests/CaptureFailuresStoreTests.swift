// LuminaVaultClient/LuminaVaultClientTests/CaptureFailuresStoreTests.swift
//
// The app-wide backstop for captures that gave up.
//
// Before this existed, `PendingCaptureState.failed` was written and never read:
// a capture from the sheet, the share extension or a previous session simply
// disappeared. What matters here is that a failed row is found at all, that
// retrying reuses the captured payload rather than asking the user to redo it,
// and that nothing deletes a capture except an explicit discard.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class CaptureFailuresStoreTests: XCTestCase {
    private func row(_ kind: PendingCaptureKind, text: String? = nil, url: String? = nil) -> CaptureRowSnapshot {
        CaptureRowSnapshot(
            id: UUID(),
            createdAt: .now,
            captionText: text,
            imageData: Data(),
            contentType: "",
            fileExtension: "",
            lat: nil,
            lng: nil,
            accuracyM: nil,
            placeName: nil,
            spaceID: nil,
            kind: kind,
            urlString: url,
            attempts: 6,
            lastError: "The server said no."
        )
    }

    func testFailedCapturesAreFound() async {
        let failed = [row(.text, text: "a note"), row(.voice)]
        let store = CaptureFailuresStore(queue: FakeQueue(failed: failed), drainer: .noop)

        await store.refresh()

        XCTAssertEqual(store.count, 2)
        XCTAssertTrue(store.hasFailures)
    }

    func testNoQueueMeansNoFailuresRatherThanACrash() async {
        // The queue is nil until the vault is prepared, and the header asks for
        // a count on every render.
        let store = CaptureFailuresStore(queue: nil, drainer: .noop)

        await store.refresh()

        XCTAssertEqual(store.count, 0)
    }

    func testRetryReusesTheCaptureAndKicksTheDrainer() async throws {
        let target = row(.text, text: "worth another go")
        let queue = FakeQueue(failed: [target])
        let kicked = KickFlag()
        let store = CaptureFailuresStore(
            queue: queue,
            drainer: CaptureDrainerHandle(kick: { await kicked.set() })
        )
        await store.refresh()

        await store.retry(target)

        let retried = await queue.retried
        XCTAssertEqual(retried, [target.id], "the original capture is requeued, not re-entered")
        let wasKicked = await kicked.value
        XCTAssertTrue(wasKicked, "a retry that waits for the next launch is not a retry")
        XCTAssertEqual(store.count, 0, "and it leaves the review list")
    }

    func testRetryAllRequeuesEveryRow() async {
        let rows = [row(.text, text: "one"), row(.url, url: "https://example.com")]
        let queue = FakeQueue(failed: rows)
        let store = CaptureFailuresStore(queue: queue, drainer: .noop)
        await store.refresh()

        await store.retryAll()

        let retried = await queue.retried
        XCTAssertEqual(Set(retried), Set(rows.map(\.id)))
        XCTAssertEqual(store.count, 0)
    }

    func testDiscardIsTheOnlyThingThatDeletes() async {
        let target = row(.voice)
        let queue = FakeQueue(failed: [target])
        let store = CaptureFailuresStore(queue: queue, drainer: .noop)
        await store.refresh()

        await store.retry(target)
        var deleted = await queue.deleted
        XCTAssertTrue(deleted.isEmpty, "retrying must never throw the capture away")

        await store.refresh()
        let remaining = await queue.failedRows
        XCTAssertTrue(remaining.isEmpty)

        // And when the user does ask, it goes.
        let second = row(.text, text: "give up")
        let queue2 = FakeQueue(failed: [second])
        let store2 = CaptureFailuresStore(queue: queue2, drainer: .noop)
        await store2.refresh()
        await store2.discard(second)
        deleted = await queue2.deleted
        XCTAssertEqual(deleted, [second.id])
        XCTAssertEqual(store2.count, 0)
    }

    func testTitlesSayWhatWasCaptured() {
        // A voice note has no text of its own — it failed before it could be
        // transcribed — so "Voice note" is the honest label rather than blank.
        XCTAssertEqual(CaptureFailuresStore.title(for: row(.voice)), "Voice note")
        XCTAssertEqual(
            CaptureFailuresStore.title(for: row(.url, url: "https://example.com/post")),
            "example.com"
        )
        XCTAssertEqual(CaptureFailuresStore.title(for: row(.text, text: "the note")), "the note")
        XCTAssertEqual(CaptureFailuresStore.title(for: row(.text, text: "   ")), "Note")
    }
}

// MARK: - Stubs

private actor FakeQueue: CaptureQueueProtocol {
    private(set) var failedRows: [CaptureRowSnapshot]
    private(set) var retried: [UUID] = []
    private(set) var deleted: [UUID] = []

    init(failed: [CaptureRowSnapshot]) { self.failedRows = failed }

    func enqueue(_: CaptureSnapshot) async throws {}
    func pending() async throws -> [CaptureRowSnapshot] { [] }
    func failed() async throws -> [CaptureRowSnapshot] { failedRows }
    func retry(id: UUID) async throws {
        retried.append(id)
        failedRows.removeAll { $0.id == id }
    }
    func delete(id: UUID) async throws {
        deleted.append(id)
        failedRows.removeAll { $0.id == id }
    }
    func markFailure(id _: UUID, error _: String, flipToFailed _: Bool) async throws {}
    func count() async throws -> Int { failedRows.count }
}

private actor KickFlag {
    private(set) var value = false
    func set() { value = true }
}
