// LuminaVaultClient/LuminaVaultClientTests/WorkspaceViewModelTests.swift
//
// The workspace screen's state machine. Kept in step with the web view
// model's tests on purpose: the two render the same endpoints, so a
// difference in behaviour is a bug on one platform rather than a platform
// difference.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
    // MARK: - Stub

    private final class StubClient: HermesWorkspaceClientProtocol, @unchecked Sendable {
        var statusResult: Result<HermesWorkspaceStatusDTO, any Error> = .success(.stub())
        var listings: [String: HermesWorkspaceListingDTO] = [:]
        var fileResult: Result<HermesWorkspaceFileDTO, any Error> =
            .success(HermesWorkspaceFileDTO(path: "/repo/README.md", content: "# hi"))
        var diffResult: Result<HermesWorkspaceDiffDTO, any Error> =
            .success(HermesWorkspaceDiffDTO(path: "README.md", diff: "@@ -1 +1 @@"))
        /// Paths that should hang until `release()` is called.
        var slowPaths: Set<String> = []
        private var gate = CheckedContinuation<Void, Never>?.none

        func release() {
            gate?.resume()
            gate = nil
        }

        func status(path _: String) async throws -> HermesWorkspaceStatusDTO {
            try statusResult.get()
        }

        func listing(path: String) async throws -> HermesWorkspaceListingDTO {
            if slowPaths.contains(path) {
                await withCheckedContinuation { self.gate = $0 }
            }
            return listings[path] ?? HermesWorkspaceListingDTO(path: path, entries: [])
        }

        func file(path _: String) async throws -> HermesWorkspaceFileDTO {
            try fileResult.get()
        }

        func diff(repoPath _: String, file _: String) async throws -> HermesWorkspaceDiffDTO {
            try diffResult.get()
        }
    }

    private func entry(_ name: String, _ isDirectory: Bool) -> HermesWorkspaceFileEntryDTO {
        HermesWorkspaceFileEntryDTO(name: name, path: "/repo/\(name)", isDirectory: isDirectory)
    }

    // MARK: - Loading

    func testOpenLoadsTreeAndStatus() async {
        let client = StubClient()
        client.listings["/repo"] = HermesWorkspaceListingDTO(
            path: "/repo",
            entries: [entry("README.md", false), entry("Sources", true)]
        )
        let sut = WorkspaceViewModel(client: client)

        await sut.open(root: "/repo")

        XCTAssertEqual(sut.cwd, "/repo")
        // Directories first, then alphabetical.
        XCTAssertEqual(sut.entries.map(\.name), ["Sources", "README.md"])
        XCTAssertEqual(sut.status?.repo.branch, "main")
        XCTAssertNil(sut.error)
    }

    func testOpeningADirectoryMovesTheTreeAndAFileFillsTheDetail() async {
        let client = StubClient()
        client.listings["/repo"] = HermesWorkspaceListingDTO(path: "/repo", entries: [])
        client.listings["/repo/Sources"] = HermesWorkspaceListingDTO(path: "/repo/Sources", entries: [])
        let sut = WorkspaceViewModel(client: client)
        await sut.open(root: "/repo")

        await sut.open(entry: entry("Sources", true))
        XCTAssertEqual(sut.cwd, "/repo/Sources")

        await sut.open(entry: entry("README.md", false))
        XCTAssertEqual(sut.selection, .file(path: "/repo/README.md"))
        XCTAssertEqual(sut.fileContent, "# hi")
    }

    /// Both cannot be on screen at once; leaving the other set would render a
    /// file's contents under a diff header.
    func testShowingADiffClearsTheFileAndViceVersa() async {
        let client = StubClient()
        let sut = WorkspaceViewModel(client: client)
        await sut.open(root: "/repo")

        await sut.showFile(path: "/repo/README.md")
        XCTAssertNil(sut.diffText)

        await sut.showDiff(file: "README.md")
        XCTAssertNil(sut.fileContent)
        XCTAssertEqual(sut.diffText, "@@ -1 +1 @@")
    }

    // MARK: - States

    /// A tenant with no remote Hermes is a configuration state, not a fault.
    /// Showing it as an error sends someone hunting for a broken thing.
    ///
    /// The string matters: the server sends `hermes_mirror_unsupported` from
    /// the shared mirror error mapper, not a workspace-specific code.
    func testUnsupportedWorkspaceIsAStateNotAnError() async {
        let client = StubClient()
        client.statusResult = .failure(
            APIError.httpError(statusCode: 501, data: Data(#"{"error":{"message":"hermes_mirror_unsupported"}}"#.utf8))
        )
        let sut = WorkspaceViewModel(client: client)

        await sut.loadStatus()

        XCTAssertTrue(sut.isUnsupported)
        XCTAssertNil(sut.error)
    }

    func testARealFailureSurfacesAsAnError() async {
        let client = StubClient()
        client.statusResult = .failure(
            APIError.httpError(statusCode: 502, data: Data(#"{"error":{"message":"gateway exploded"}}"#.utf8))
        )
        let sut = WorkspaceViewModel(client: client)

        await sut.loadStatus()

        XCTAssertFalse(sut.isUnsupported)
        XCTAssertNotNil(sut.error)
    }

    func testTruncatedDiffIsFlagged() async {
        let client = StubClient()
        client.diffResult = .success(
            HermesWorkspaceDiffDTO(path: "big.swift", diff: "cut", truncated: true)
        )
        let sut = WorkspaceViewModel(client: client)
        await sut.open(root: "/repo")

        await sut.showDiff(file: "big.swift")

        XCTAssertTrue(sut.diffTruncated)
    }

    // MARK: - Pure helpers

    func testSortPutsDirectoriesFirstThenAlphabetical() {
        let sorted = WorkspaceViewModel.sorted([
            entry("README.md", false),
            entry("Tests", true),
            entry("Package.swift", false),
            entry("Sources", true),
        ])
        XCTAssertEqual(sorted.map(\.name), ["Sources", "Tests", "Package.swift", "README.md"])
    }

    func testParentPathWalksUpAndStopsAtTheRoot() {
        // Without the stop, "go up" would offer an infinite climb.
        XCTAssertEqual(WorkspaceViewModel.parentPath("/work/repo/Sources"), "/work/repo")
        XCTAssertEqual(WorkspaceViewModel.parentPath("/work"), "/")
        XCTAssertNil(WorkspaceViewModel.parentPath("/"))
        XCTAssertNil(WorkspaceViewModel.parentPath(""))
    }

    func testParentPathIgnoresATrailingSlash() {
        XCTAssertEqual(WorkspaceViewModel.parentPath("/work/repo/"), "/work")
    }

    func testChurnTotalsTheChangeSet() async {
        let client = StubClient()
        client.statusResult = .success(.stub(changes: [
            HermesWorkspaceChangeDTO(path: "a", added: 10, removed: 2, status: "modified"),
            HermesWorkspaceChangeDTO(path: "b", added: 3, removed: 7, status: "added"),
        ]))
        let sut = WorkspaceViewModel(client: client)
        await sut.loadStatus()

        XCTAssertEqual(sut.churn.added, 13)
        XCTAssertEqual(sut.churn.removed, 9)
    }
}

private extension HermesWorkspaceStatusDTO {
    static func stub(changes: [HermesWorkspaceChangeDTO] = []) -> HermesWorkspaceStatusDTO {
        HermesWorkspaceStatusDTO(
            repo: HermesWorkspaceRepoDTO(root: "/repo", branch: "main"),
            branches: [HermesWorkspaceBranchDTO(name: "main", isCurrent: true)],
            worktrees: [],
            changes: changes
        )
    }
}
