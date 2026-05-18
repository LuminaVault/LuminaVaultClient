// LuminaVaultClient/LuminaVaultClientTests/CaptureQueueTests.swift
//
// HER-34 — exercise CaptureQueue against an in-memory SwiftData store.

import XCTest
@testable import LuminaVaultClient

final class CaptureQueueTests: XCTestCase {
    private var queue: CaptureQueue!

    override func setUp() async throws {
        let container = try CaptureQueue.makeInMemoryContainer()
        queue = CaptureQueue(container: container)
    }

    func testEnqueueAndPending() async throws {
        let snapshot = CaptureSnapshot(
            imageData: Data([0xDE, 0xAD]),
            contentType: "image/heic",
            fileExtension: "heic",
        )
        try await queue.enqueue(snapshot)
        let pending = try await queue.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.contentType, "image/heic")
        XCTAssertEqual(pending.first?.fileExtension, "heic")
    }

    func testDeleteRemovesRow() async throws {
        let snapshot = CaptureSnapshot(
            imageData: Data([0x01]),
            contentType: "image/jpeg",
            fileExtension: "jpg",
        )
        try await queue.enqueue(snapshot)
        let pending = try await queue.pending()
        try await queue.delete(id: pending[0].id)
        let after = try await queue.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testMarkFailureIncrementsAndFlips() async throws {
        let snapshot = CaptureSnapshot(
            imageData: Data([0x01]),
            contentType: "image/jpeg",
            fileExtension: "jpg",
        )
        try await queue.enqueue(snapshot)
        let pending = try await queue.pending()
        let id = pending[0].id

        try await queue.markFailure(id: id, error: "boom", flipToFailed: false)
        var rows = try await queue.pending()
        XCTAssertEqual(rows.first?.attempts, 1)

        try await queue.markFailure(id: id, error: "boom", flipToFailed: true)
        rows = try await queue.pending()
        XCTAssertTrue(rows.isEmpty, "row should no longer be pending after flip")
        let total = try await queue.count()
        XCTAssertEqual(total, 1, "row still exists, just not in pending state")
    }
}
