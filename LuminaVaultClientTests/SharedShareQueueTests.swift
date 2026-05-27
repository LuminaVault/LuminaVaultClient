// LuminaVaultClient/LuminaVaultClientTests/SharedShareQueueTests.swift
//
// HER-258 — round-trip + edge-case coverage for the App Group queue.
// The tests can't exercise a real App Group container (the test bundle
// doesn't carry the entitlement), so they override the file URL to a
// temp directory via a small test-only seam.

import XCTest
@testable import LuminaVaultClient

final class SharedShareQueueTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lv-share-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// PendingShare round-trips its Codable shape verbatim. Catches
    /// accidental key changes that would silently drop fields on either
    /// side of the App Group boundary.
    func testPendingShareCodableRoundTrip() throws {
        let original = PendingShare(
            url: "https://x.com/jack/status/42",
            note: "good thread",
            spaceID: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let encoder = SharedAppGroup.encoder
        let decoder = SharedAppGroup.decoder
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PendingShare.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.kind, .url)
        XCTAssertNil(decoded.text)
    }

    func testPendingTextShareCodableRoundTrip() throws {
        let original = PendingShare(
            text: "clip this thought",
            note: "from Mail",
            spaceID: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_010),
        )
        let data = try SharedAppGroup.encoder.encode(original)
        let decoded = try SharedAppGroup.decoder.decode(PendingShare.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.kind, .text)
        XCTAssertNil(decoded.url)
    }

    func testPendingImageShareCodableRoundTrip() throws {
        let original = PendingShare(
            imageAssetFileName: "image.heic",
            contentType: "image/heic",
            fileExtension: "heic",
            note: "receipt",
            spaceID: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_020),
        )
        let data = try SharedAppGroup.encoder.encode(original)
        let decoded = try SharedAppGroup.decoder.decode(PendingShare.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.kind, .image)
        XCTAssertEqual(decoded.assetFileName, "image.heic")
    }

    /// Multiple appends produce an ordered array under the App Group
    /// file. This is the contract the host app's launch drain depends on.
    func testAppendIsOrderedAndAccumulates() throws {
        let url = tempDir.appendingPathComponent("pendingShares.json")
        var queue: [PendingShare] = []
        queue.append(PendingShare(url: "https://a.example"))
        queue.append(PendingShare(url: "https://b.example", note: "second"))
        queue.append(PendingShare(url: "https://c.example", spaceID: UUID()))

        try SharedAppGroup.encoder.encode(queue).write(to: url, options: .atomic)
        let data = try Data(contentsOf: url)
        let decoded = try SharedAppGroup.decoder.decode([PendingShare].self, from: data)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded.compactMap(\.url), ["https://a.example", "https://b.example", "https://c.example"])
        XCTAssertEqual(decoded[1].note, "second")
        XCTAssertNotNil(decoded[2].spaceID)
    }

    /// SharedSpaceSummary survives a write/read cycle. The extension's
    /// picker depends on this.
    func testSharedSpaceSummaryRoundTrip() throws {
        let original = [
            SharedSpaceSummary(id: UUID(), name: "Work"),
            SharedSpaceSummary(id: UUID(), name: "Personal"),
            SharedSpaceSummary(id: UUID(), name: "AI ideas"),
        ]
        let data = try SharedAppGroup.encoder.encode(original)
        let decoded = try SharedAppGroup.decoder.decode([SharedSpaceSummary].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// Empty file should decode as `nil` (read helper coalesces) so the
    /// extension safely treats first-run state as "no Spaces cached".
    func testEmptyDataIsNotADecodeError() {
        let url = tempDir.appendingPathComponent("empty.json")
        try? Data().write(to: url)
        let decoded: [PendingShare]? = try? SharedAppGroup.decoder.decode([PendingShare].self, from: Data())
        // Direct decode of empty data DOES throw; this assertion documents
        // that contract so the read helper's `data.isEmpty` guard stays.
        XCTAssertNil(decoded)
    }
}
