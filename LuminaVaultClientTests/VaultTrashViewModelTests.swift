// LuminaVaultClient/LuminaVaultClientTests/VaultTrashViewModelTests.swift
// Backlog E3.4 — the Trash screen's list, restore and delete forever.

@testable import LuminaVaultClient
import Foundation
import XCTest

@MainActor
final class VaultTrashViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ path: String, title: String? = nil) -> VaultTrashItem {
        VaultTrashItem(path: path, sizeBytes: 10, title: title, deletedAt: now)
    }

    func testLoadListsItems() async {
        let client = MockVaultClient()
        client.listTrashResult = .success([item("inbox/a.md"), item("inbox/b.md")])
        let vm = VaultTrashViewModel(vaultClient: client)
        await vm.load()
        XCTAssertEqual(vm.items.map(\.path), ["inbox/a.md", "inbox/b.md"])
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasLoaded)
    }

    func testRestoreDropsTheRowAndSaysWhenRenamed() async {
        let a = item("inbox/a.md")
        let client = MockVaultClient()
        client.listTrashResult = .success([a])
        client.restoreTrashResult = .success(
            VaultFileDTO(id: UUID(), path: "inbox/a-restored.md", contentType: "text/markdown", sizeBytes: 10, sha256: "")
        )
        let vm = VaultTrashViewModel(vaultClient: client)
        await vm.load()
        await vm.restore(a)
        XCTAssertEqual(client.restoredTrashIDs, [a.id])
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.notice, "Restored as inbox/a-restored.md")
    }

    func testRestoreGoneFileDropsTheRowWithAClearMessage() async {
        let a = item("inbox/a.md")
        let client = MockVaultClient()
        client.listTrashResult = .success([a])
        client.restoreTrashResult = .failure(APIError.httpError(statusCode: 410, data: Data()))
        let vm = VaultTrashViewModel(vaultClient: client)
        await vm.load()
        await vm.restore(a)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.error, "This file is no longer available.")
    }

    func testRestoreFailureKeepsTheRow() async {
        let a = item("inbox/a.md")
        let client = MockVaultClient()
        client.listTrashResult = .success([a])
        client.restoreTrashResult = .failure(URLError(.notConnectedToInternet))
        let vm = VaultTrashViewModel(vaultClient: client)
        await vm.load()
        await vm.restore(a)
        XCTAssertEqual(vm.items, [a])
        XCTAssertNotNil(vm.error)
    }

    func testDeleteForever() async {
        let a = item("inbox/a.md")
        let client = MockVaultClient()
        client.listTrashResult = .success([a])
        let vm = VaultTrashViewModel(vaultClient: client)
        await vm.load()
        await vm.deleteForever(a)
        XCTAssertEqual(client.deletedTrashIDs, [a.id])
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.notice, "Deleted inbox/a.md for good")
    }

    func testDaysLeft() {
        let deleted = item("a.md")
        XCTAssertEqual(deleted.daysLeft(now: now), 30)
        XCTAssertEqual(deleted.daysLeft(now: now.addingTimeInterval(26 * 86_400)), 4)
        XCTAssertEqual(deleted.daysLeft(now: now.addingTimeInterval(40 * 86_400)), 0)
    }

    func testDecodesTheWireShape() throws {
        let json = Data("""
        {"items":[{"id":"6dc03c39-3830-49df-a0f0-e06760b8c392","path":"inbox/a.md","contentType":"text/markdown",
        "sizeBytes":12,"title":"A","deletedAt":"2026-11-15T10:00:00Z"}]}
        """.utf8)
        let list = try JSONDecoder.hvDefault.decode(VaultTrashListResponse.self, from: json)
        XCTAssertEqual(list.items.first?.path, "inbox/a.md")
        XCTAssertEqual(list.items.first?.title, "A")
        XCTAssertNil(list.items.first?.spaceId)
    }
}
