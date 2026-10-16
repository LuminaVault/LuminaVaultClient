// LuminaVaultClient/LuminaVaultClientTests/ResurfaceWidgetStoreTests.swift
//
// The App Group file behind "Today's memory": what the app writes is what
// the widget reads, an answered memory leaves it, and sign-out removes it.

import Foundation
import XCTest

@testable import LuminaVaultClient

@MainActor
final class ResurfaceWidgetStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ResurfaceWidgetStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ResurfaceWidgetStore(fileURL: directory.appendingPathComponent(ResurfaceWidgetStore.fileName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func item(_ snippet: String) -> ResurfaceWidgetItem {
        ResurfaceWidgetItem(memoryId: UUID(), snippet: snippet, why: "Saved a year ago today")
    }

    func testNothingWrittenReadsAsEmpty() {
        XCTAssertEqual(store.read(), .empty)
        XCTAssertNil(store.read().current)
    }

    func testRoundTrip() {
        let snapshot = ResurfaceWidgetSnapshot(
            items: [item("a"), item("b")],
            updatedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        store.write(snapshot)
        XCTAssertEqual(store.read(), snapshot)
        XCTAssertEqual(store.read().current?.snippet, "a")
    }

    func testRemovingTheAnsweredMemoryShowsTheNext() {
        let first = item("a")
        store.write(ResurfaceWidgetSnapshot(items: [first, item("b")], updatedAt: .now))
        store.remove(memoryId: first.memoryId)
        XCTAssertEqual(store.read().items.map(\.snippet), ["b"])
    }

    func testClearRemovesTheFile() {
        store.write(ResurfaceWidgetSnapshot(items: [item("a")], updatedAt: .now))
        store.clear()
        XCTAssertEqual(store.read(), .empty)
    }

    func testTheDeepLinkIsTheMemoryRoute() throws {
        let item = item("a")
        let url = try XCTUnwrap(item.deepLink)
        XCTAssertEqual(NotificationRouter.deepLink(from: url), .memory(id: item.memoryId))
    }
}
