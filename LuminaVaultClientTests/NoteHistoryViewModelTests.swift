// LuminaVaultClient/LuminaVaultClientTests/NoteHistoryViewModelTests.swift
// Backlog E4.5 — the note history sheet: list, read a version, restore.

import Foundation
import XCTest
@testable import LuminaVaultClient

@MainActor
final class NoteHistoryViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func version(_ sha: String, deleted: Bool = false, reason: String = "upload") -> VaultHistoryVersion {
        VaultHistoryVersion(sha: sha, committedAt: now, reason: reason, sizeBytes: 5, deleted: deleted)
    }

    func testLoadListsVersionsForThePath() async {
        let client = MockVaultClient()
        client.historyResult = .success([version("b"), version("a")])
        let vm = NoteHistoryViewModel(vaultClient: client, path: "inbox/n.md", currentSHA: "cur")
        await vm.load()
        XCTAssertEqual(vm.versions.map(\.sha), ["b", "a"])
        XCTAssertEqual(client.historyPaths, ["inbox/n.md"])
        XCTAssertTrue(vm.hasLoaded)
        XCTAssertNil(vm.error)
    }

    func testLoadFailureShowsAnError() async {
        let client = MockVaultClient()
        client.historyResult = .failure(URLError(.notConnectedToInternet))
        let vm = NoteHistoryViewModel(vaultClient: client, path: "inbox/n.md", currentSHA: nil)
        await vm.load()
        XCTAssertNotNil(vm.error)
        XCTAssertTrue(vm.versions.isEmpty)
    }

    func testLoadVersionReadsTextOrMarksBinary() async {
        let client = MockVaultClient()
        client.readVersionResult = .success((Data("old text".utf8), "text/markdown"))
        let vm = NoteHistoryViewModel(vaultClient: client, path: "inbox/n.md", currentSHA: nil)
        await vm.loadVersion(version("a"))
        XCTAssertEqual(vm.versionText, "old text")
        XCTAssertFalse(vm.versionIsBinary)

        client.readVersionResult = .success((Data([0xFF, 0xD8]), "image/jpeg"))
        await vm.loadVersion(version("b"))
        XCTAssertNil(vm.versionText)
        XCTAssertTrue(vm.versionIsBinary)
    }

    func testDeletedVersionIsNotLoadedOrRestored() async {
        let client = MockVaultClient()
        let vm = NoteHistoryViewModel(vaultClient: client, path: "inbox/n.md", currentSHA: "cur")
        await vm.loadVersion(version("d", deleted: true))
        XCTAssertNil(vm.versionText)
        let restored = await vm.restore(version("d", deleted: true))
        XCTAssertNil(restored)
        XCTAssertTrue(client.restoreVersionCalls.isEmpty)
    }

    func testRestoreSendsIfMatchOfTheShownVersion() async {
        let client = MockVaultClient()
        let vm = NoteHistoryViewModel(vaultClient: client, path: "inbox/n.md", currentSHA: "cur")
        let file = await vm.restore(version("a"))
        XCTAssertNotNil(file)
        XCTAssertEqual(client.restoreVersionCalls.count, 1)
        XCTAssertEqual(client.restoreVersionCalls.first?.sha, "a")
        XCTAssertEqual(client.restoreVersionCalls.first?.path, "inbox/n.md")
        XCTAssertEqual(client.restoreVersionCalls.first?.ifMatch, "\"cur\"")
    }

    func testRestoreConflictShowsTheAlertAndReturnsNil() async {
        let client = MockVaultClient()
        client.restoreVersionResult = .failure(APIError.httpError(statusCode: 412, data: Data()))
        let vm = NoteHistoryViewModel(vaultClient: client, path: "inbox/n.md", currentSHA: "cur")
        let file = await vm.restore(version("a"))
        XCTAssertNil(file)
        XCTAssertTrue(vm.showConflict)
        XCTAssertNil(vm.error)
    }

    func testReasonLabels() {
        XCTAssertEqual(version("a").reasonLabel, "Saved")
        XCTAssertEqual(version("a", reason: "sweep").reasonLabel, "Saved")
        XCTAssertEqual(version("a", reason: "restore").reasonLabel, "Restored")
        XCTAssertEqual(version("a", deleted: true).reasonLabel, "Deleted")
    }

    func testEndpointsEscapeThePath() {
        let history = VaultEndpoints.History(filePath: "inbox/a+b c.md", limit: nil, before: nil)
        XCTAssertEqual(history.path, "/v1/vault/history?path=inbox/a%2Bb%20c.md")
        let restore = VaultEndpoints.VersionRestore(sha: "abc", filePath: "inbox/a.md", ifMatch: "\"x\"")
        XCTAssertEqual(restore.path, "/v1/vault/versions/abc/restore?path=inbox/a.md")
        XCTAssertEqual(restore.additionalHeaders, ["If-Match": "\"x\""])
        XCTAssertEqual(
            VaultEndpoints.versionPath(sha: "abc", filePath: "inbox/a.md"),
            "/v1/vault/versions/abc?path=inbox/a.md"
        )
    }
}
