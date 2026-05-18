// LuminaVaultClient/LuminaVaultClientTests/MemoListViewModelTests.swift
// HER-37: contract tests for MemoListViewModel (Lumina's Notebook).

import XCTest
@testable import LuminaVaultClient

@MainActor
final class MemoListViewModelTests: XCTestCase {
    var client: MockMemoClient!
    var sut: MemoListViewModel!

    override func setUp() async throws {
        try await super.setUp()
        client = MockMemoClient()
        sut = MemoListViewModel(client: client)
    }

    func testInitialPhaseIsLoading() {
        XCTAssertEqual(sut.phase, .loading)
        XCTAssertTrue(sut.memos.isEmpty)
    }

    func testLoadHappyPath() async {
        client.listResult = .success(.stubTwoMemos)
        await sut.load()
        XCTAssertEqual(sut.memos.count, 2)
        XCTAssertEqual(sut.memos.first?.title, "Sleep Patterns")
        XCTAssertEqual(client.listCallCount, 1)
    }

    func testLoadEmptyResponse() async {
        client.listResult = .success(.empty)
        await sut.load()
        if case .loaded(let memos) = sut.phase {
            XCTAssertTrue(memos.isEmpty)
        } else {
            XCTFail("expected loaded, got \(sut.phase)")
        }
    }

    func testLoadFailureAdvancesToFailed() async {
        client.listResult = .failure(APIError.unauthorized)
        await sut.load()
        if case .failed = sut.phase {} else {
            XCTFail("expected failed, got \(sut.phase)")
        }
    }
}
