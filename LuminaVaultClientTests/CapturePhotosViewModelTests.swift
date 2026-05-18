// LuminaVaultClient/LuminaVaultClientTests/CapturePhotosViewModelTests.swift
//
// HER-34 — VM enqueues every loaded photo and attaches the geo fix
// when the location toggle is on. Direct PhotosPickerItem testing is
// impossible (the framework owns the bridge to the photo library), so
// we drive the VM through a seam: a `loadedItems` setter and the
// `save()` flow.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class CapturePhotosViewModelTests: XCTestCase {
    func testSaveEnqueuesEverythingWithoutLocation() async throws {
        let queue = StubQueue()
        let location = StubLocationService(fix: nil)
        let kicked = KickFlag()
        let drainer = CaptureDrainerHandle(kick: { await kicked.set() })

        let vm = CapturePhotosViewModel(
            queue: queue,
            locationService: location,
            drainer: drainer,
        )
        vm.loadedItems = [
            LoadedItem(id: UUID(), data: Data([0x01]), contentType: "image/heic", fileExtension: "heic", caption: "first"),
            LoadedItem(id: UUID(), data: Data([0x02]), contentType: "image/jpeg", fileExtension: "jpg", caption: ""),
            LoadedItem(id: UUID(), data: Data([0x03]), contentType: "image/heic", fileExtension: "heic", caption: "third"),
        ]

        await vm.save()

        let snapshots = await queue.snapshot()
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(snapshots[0].captionText, "first")
        XCTAssertEqual(snapshots[1].captionText, "")
        XCTAssertEqual(snapshots[2].captionText, "third")
        XCTAssertNil(snapshots[0].lat)
        XCTAssertNil(snapshots[0].lng)
        let wasKicked = await kicked.value
        XCTAssertTrue(wasKicked)
    }

    func testSaveAttachesGeoWhenLocationOn() async throws {
        let queue = StubQueue()
        let fix = LocationFix(lat: 51.5, lng: -0.12, accuracyM: 10, placeName: "London, UK")
        let location = StubLocationService(fix: fix)

        let vm = CapturePhotosViewModel(
            queue: queue,
            locationService: location,
            drainer: .noop,
        )
        vm.locationEnabled = true
        vm.loadedItems = [
            LoadedItem(id: UUID(), data: Data([0x01]), contentType: "image/heic", fileExtension: "heic", caption: ""),
        ]

        await vm.save()

        let snapshots = await queue.snapshot()
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].lat, 51.5)
        XCTAssertEqual(snapshots[0].lng, -0.12)
        XCTAssertEqual(snapshots[0].placeName, "London, UK")
    }

    func testSaveSkipsLocationWhenToggleOff() async throws {
        let queue = StubQueue()
        let location = StubLocationService(fix: LocationFix(lat: 1, lng: 1, accuracyM: 1, placeName: nil))
        let vm = CapturePhotosViewModel(
            queue: queue,
            locationService: location,
            drainer: .noop,
        )
        vm.locationEnabled = false
        vm.loadedItems = [
            LoadedItem(id: UUID(), data: Data([0x01]), contentType: "image/heic", fileExtension: "heic", caption: ""),
        ]

        await vm.save()

        let called = await location.wasCalled
        XCTAssertFalse(called, "location should not be consulted when toggle is off")
        let snapshots = await queue.snapshot()
        XCTAssertNil(snapshots.first?.lat)
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
