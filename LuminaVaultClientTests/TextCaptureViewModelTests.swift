// LuminaVaultClient/LuminaVaultClientTests/TextCaptureViewModelTests.swift
//
// HER-256 — VM enqueues a single `.text` snapshot per save, optionally
// with a geo fix. Mirrors `CapturePhotosViewModelTests` structure
// (private StubQueue actor + StubLocationService).

import XCTest
@testable import LuminaVaultClient

@MainActor
final class TextCaptureViewModelTests: XCTestCase {
    func testEmptyContentNoOps() async {
        let queue = StubQueue()
        let location = StubLocationService(fix: nil)
        let vm = TextCaptureViewModel(
            queue: queue,
            locationService: location,
            drainer: .noop,
        )
        vm.content = "   \n\t  "  // whitespace-only

        XCTAssertFalse(vm.canSave)
        await vm.save()

        let snapshots = await queue.snapshot()
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertNil(vm.toast, "no toast on a no-op save")
    }

    func testSaveEnqueuesTextSnapshotWithoutLocation() async throws {
        let queue = StubQueue()
        let location = StubLocationService(fix: LocationFix(lat: 1, lng: 1, accuracyM: 1, placeName: nil))
        let kicked = KickFlag()
        let drainer = CaptureDrainerHandle(kick: { await kicked.set() })

        let vm = TextCaptureViewModel(
            queue: queue,
            locationService: location,
            drainer: drainer,
        )
        vm.content = "  learned about pgvector today  "

        await vm.save()

        let snapshots = await queue.snapshot()
        XCTAssertEqual(snapshots.count, 1)
        let snap = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snap.kind, .text)
        XCTAssertEqual(snap.captionText, "learned about pgvector today", "VM must trim whitespace before enqueue")
        XCTAssertTrue(snap.imageData.isEmpty)
        XCTAssertNil(snap.lat, "geo skipped when toggle off")

        let wasCalled = await location.wasCalled
        XCTAssertFalse(wasCalled, "location service must not be consulted when toggle off")
        let wasKicked = await kicked.value
        XCTAssertTrue(wasKicked, "drainer must be kicked after enqueue")
        XCTAssertEqual(vm.content, "", "content cleared after success")
    }

    func testSaveAttachesGeoWhenLocationOn() async {
        let queue = StubQueue()
        let fix = LocationFix(lat: 51.5, lng: -0.12, accuracyM: 10, placeName: "London, UK")
        let location = StubLocationService(fix: fix)

        let vm = TextCaptureViewModel(
            queue: queue,
            locationService: location,
            drainer: .noop,
        )
        vm.content = "rainy day note"
        vm.locationEnabled = true

        await vm.save()

        let snapshots = await queue.snapshot()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].kind, .text)
        XCTAssertEqual(snapshots[0].lat, 51.5)
        XCTAssertEqual(snapshots[0].lng, -0.12)
        XCTAssertEqual(snapshots[0].placeName, "London, UK")
    }

    func testSaveSurfacesEnqueueFailureAsToast() async {
        let queue = ThrowingQueue()
        let location = StubLocationService(fix: nil)
        let vm = TextCaptureViewModel(
            queue: queue,
            locationService: location,
            drainer: .noop,
        )
        vm.content = "this enqueue will throw"

        await vm.save()

        if case .failed = vm.toast {
            // expected
        } else {
            XCTFail("expected .failed toast, got \(String(describing: vm.toast))")
        }
        XCTAssertEqual(vm.content, "this enqueue will throw", "content preserved on failure for retry")
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

private actor StubLocationService: LocationServiceProtocol {
    private let fix: LocationFix?
    private(set) var wasCalled = false
    init(fix: LocationFix?) { self.fix = fix }
    func requestFix() async -> LocationFix? {
        wasCalled = true
        return fix
    }
}

private actor KickFlag {
    private(set) var value: Bool = false
    func set() { value = true }
}
