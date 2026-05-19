// LuminaVaultClient/LuminaVaultClientTests/URLCaptureViewModelTests.swift
//
// HER-257 — VM validates URL surface-level, enqueues a single `.url`
// snapshot per save, and surfaces enqueue failures as a toast. Mirrors
// TextCaptureViewModelTests structure.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class URLCaptureViewModelTests: XCTestCase {
    func testEmptyURLNoOps() async {
        let queue = StubQueue()
        let vm = URLCaptureViewModel(queue: queue, drainer: .noop)
        vm.urlString = "   \n"

        XCTAssertFalse(vm.canSave)
        await vm.save()

        let snapshots = await queue.snapshot()
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertNil(vm.toast)
    }

    func testInvalidSchemeBlocksSave() async {
        let queue = StubQueue()
        let vm = URLCaptureViewModel(queue: queue, drainer: .noop)
        vm.urlString = "javascript:alert(1)"

        XCTAssertFalse(vm.canSave, "non-http(s) schemes must be rejected")
        await vm.save()

        let snapshots = await queue.snapshot()
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testValidURLEnqueuesURLSnapshot() async {
        let queue = StubQueue()
        let kicked = KickFlag()
        let drainer = CaptureDrainerHandle(kick: { await kicked.set() })

        let vm = URLCaptureViewModel(queue: queue, drainer: drainer)
        vm.urlString = "  https://x.com/jack/status/123  "

        XCTAssertTrue(vm.canSave)
        await vm.save()

        let snapshots = await queue.snapshot()
        XCTAssertEqual(snapshots.count, 1)
        let snap = try! XCTUnwrap(snapshots.first)
        XCTAssertEqual(snap.kind, .url)
        XCTAssertEqual(snap.urlString, "https://x.com/jack/status/123", "VM must trim whitespace")
        XCTAssertNil(snap.captionText, "no note → no captionText")
        XCTAssertNil(snap.spaceID)

        let wasKicked = await kicked.value
        XCTAssertTrue(wasKicked)
        XCTAssertEqual(vm.urlString, "", "url cleared after success")
    }

    func testURLWithNoteAndSpaceCarriesThroughSnapshot() async {
        let queue = StubQueue()
        let space = UUID()
        let vm = URLCaptureViewModel(queue: queue, drainer: .noop)
        vm.urlString = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        vm.note = "  rickroll classic  "
        vm.selectedSpaceID = space

        await vm.save()

        let snapshots = await queue.snapshot()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].captionText, "rickroll classic")
        XCTAssertEqual(snapshots[0].spaceID, space)
    }

    func testEnqueueFailureSurfacesAsToast() async {
        let queue = ThrowingQueue()
        let vm = URLCaptureViewModel(queue: queue, drainer: .noop)
        vm.urlString = "https://example.com"

        await vm.save()

        if case .failed = vm.toast {
            // expected
        } else {
            XCTFail("expected .failed toast, got \(String(describing: vm.toast))")
        }
        XCTAssertEqual(vm.urlString, "https://example.com", "url preserved on failure for retry")
    }
}

// MARK: - Stubs

private actor StubQueue: CaptureQueueProtocol {
    private var enqueued: [CaptureSnapshot] = []
    func snapshot() -> [CaptureSnapshot] { enqueued }
    func enqueue(_ snapshot: CaptureSnapshot) async throws { enqueued.append(snapshot) }
    func pending() async throws -> [CaptureRowSnapshot] { [] }
    func delete(id: UUID) async throws {}
    func markFailure(id: UUID, error: String, flipToFailed: Bool) async throws {}
    func count() async throws -> Int { enqueued.count }
}

private actor ThrowingQueue: CaptureQueueProtocol {
    struct EnqueueError: Error {}
    func enqueue(_ snapshot: CaptureSnapshot) async throws { throw EnqueueError() }
    func pending() async throws -> [CaptureRowSnapshot] { [] }
    func delete(id: UUID) async throws {}
    func markFailure(id: UUID, error: String, flipToFailed: Bool) async throws {}
    func count() async throws -> Int { 0 }
}

private actor KickFlag {
    private(set) var value: Bool = false
    func set() { value = true }
}
