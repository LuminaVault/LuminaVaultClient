// LuminaVaultClient/LuminaVaultClientTests/HermesRunsListViewModelTests.swift
//
// Hermes Companion Phase 1 — the runs list. What matters here is the
// grouping (a run blocked on an approval must not be buried among finished
// ones) and that a failed refresh never blanks a populated screen.

import LuminaVaultShared
import XCTest
@testable import LuminaVaultClient

@MainActor
final class HermesRunsListViewModelTests: XCTestCase {
    private var client: StubHermesRunsClient!
    private var sut: HermesRunsListViewModel!

    override func setUp() async throws {
        try await super.setUp()
        client = StubHermesRunsClient()
        sut = HermesRunsListViewModel(client: client, limit: 30)
    }

    func testLoadSendsTheConfiguredLimit() async {
        client.listResult = .success([])

        await sut.load()

        XCTAssertEqual(client.listLimits, [30])
        XCTAssertEqual(sut.state, .loaded)
    }

    func testRunsAreGroupedSoBlockedOnesSurfaceFirst() async {
        client.listResult = .success([
            .stub(status: .completed, prompt: "done", id: Self.id(1)),
            .stub(status: .waitingForApproval, prompt: "blocked", id: Self.id(2)),
            .stub(status: .running, prompt: "going", id: Self.id(3)),
            .stub(status: .queued, prompt: "queued", id: Self.id(4)),
            .stub(status: .lost, prompt: "lost", id: Self.id(5)),
        ])

        await sut.load()

        XCTAssertEqual(sut.waitingForApproval.map(\.prompt), ["blocked"])
        XCTAssertEqual(sut.active.map(\.prompt), ["going", "queued"])
        // `lost` is terminal — nothing more can arrive for it.
        XCTAssertEqual(sut.finished.map(\.prompt), ["done", "lost"])
    }

    func testColdLoadFailureShowsTheFailure() async {
        client.listResult = .failure(
            APIError.httpError(statusCode: 501, data: Data(#"{"error":{"message":"hermes_runs_unsupported"}}"#.utf8))
        )

        await sut.load()

        XCTAssertEqual(sut.state, .failed(.unsupported))
        XCTAssertTrue(sut.runs.isEmpty)
    }

    /// Pull-to-refresh on a bad network must not throw away the list the user
    /// is looking at.
    func testRefreshFailureKeepsTheExistingList() async {
        client.listResult = .success([.stub(status: .running, prompt: "going")])
        await sut.load()

        client.listResult = .failure(APIError.networkFailure(URLError(.notConnectedToInternet)))
        await sut.load()

        XCTAssertEqual(sut.state, .loaded)
        XCTAssertEqual(sut.runs.map(\.prompt), ["going"])
    }

    private static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
