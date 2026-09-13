// LuminaVaultClient/LuminaVaultClientTests/VaultFilesViewModelTests.swift
//
// The listing half of the vault, now shared with the capture home's recent
// feed.
//
// Two things here are silent when they break. A `spaceSlug` that stops being
// forwarded turns a Space's file list into every file the tenant has, which
// looks like a working screen. And keyset paging that ignores its cursor
// re-requests page one forever, which looks like a list that will not load
// more rather than like an error.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class VaultFilesViewModelTests: XCTestCase {
    private func file(_ path: String, sizeBytes: Int64 = 128) -> VaultFileDTO {
        VaultFileDTO(
            id: UUID(),
            path: path,
            contentType: "text/markdown",
            sizeBytes: sizeBytes,
            sha256: ""
        )
    }

    func testNilSpaceSlugListsEverySpace() async throws {
        // This is what makes the home feed a record of what you have saved
        // rather than one folder's contents.
        let client = MockVaultClient()
        client.listFilesResult = .success(
            VaultFileListResponse(files: [file("inbox/a.md")], limit: 50, nextBefore: nil)
        )
        let vm = VaultFilesViewModel(vaultClient: client, spaceSlug: nil)

        await vm.load()

        let call = try XCTUnwrap(client.listFilesCalls.first)
        XCTAssertNil(call.spaceSlug, "a nil slug must reach the client, not be defaulted")
        XCTAssertEqual(vm.files.count, 1)
    }

    func testSpaceSlugIsForwarded() async throws {
        let client = MockVaultClient()
        let vm = VaultFilesViewModel(vaultClient: client, spaceSlug: "work")

        await vm.load()

        let call = try XCTUnwrap(client.listFilesCalls.first)
        XCTAssertEqual(call.spaceSlug, "work")
    }

    func testLoadMorePagesOnTheCursor() async throws {
        let cursor = Date(timeIntervalSince1970: 1_700_000_000)
        let client = MockVaultClient()
        client.listFilesResult = .success(
            VaultFileListResponse(files: [file("inbox/a.md")], limit: 50, nextBefore: cursor)
        )
        let vm = VaultFilesViewModel(vaultClient: client, spaceSlug: nil)
        await vm.load()
        XCTAssertEqual(vm.nextCursor, cursor)

        client.listFilesResult = .success(
            VaultFileListResponse(files: [file("inbox/b.md")], limit: 50, nextBefore: nil)
        )
        await vm.loadMore()

        XCTAssertEqual(client.listFilesCalls.count, 2)
        XCTAssertEqual(client.listFilesCalls[1].before, cursor, "page two must ask from the cursor")
        XCTAssertEqual(vm.files.map(\.path), ["inbox/a.md", "inbox/b.md"])
        XCTAssertNil(vm.nextCursor)
    }

    func testLoadMoreStopsWithoutACursor() async {
        let client = MockVaultClient()
        client.listFilesResult = .success(
            VaultFileListResponse(files: [file("inbox/a.md")], limit: 50, nextBefore: nil)
        )
        let vm = VaultFilesViewModel(vaultClient: client, spaceSlug: nil)
        await vm.load()

        await vm.loadMore()

        XCTAssertEqual(client.listFilesCalls.count, 1, "no cursor means there is no next page to ask for")
    }

    func testFailureSurfacesAnErrorRatherThanEmptyingTheList() async {
        struct Boom: Error {}
        let client = MockVaultClient()
        client.listFilesResult = .failure(Boom())
        let vm = VaultFilesViewModel(vaultClient: client, spaceSlug: nil)

        await vm.load()

        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoading, "the spinner must not be left running after a failure")
    }
}
