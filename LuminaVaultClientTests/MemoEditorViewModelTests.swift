// LuminaVaultClient/LuminaVaultClientTests/MemoEditorViewModelTests.swift
// HER-37: contract tests for MemoEditorViewModel.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class MemoEditorViewModelTests: XCTestCase {
    var client: MockMemoClient!
    var sut: MemoEditorViewModel!

    override func setUp() async throws {
        try await super.setUp()
        client = MockMemoClient()
        sut = MemoEditorViewModel(client: client)
    }

    func testInitialStateIsEditingNoBlankSave() {
        XCTAssertEqual(sut.phase, .editing)
        XCTAssertFalse(sut.canSave)
    }

    func testCanSaveAfterTopicEntered() {
        sut.topic = "Sleep"
        XCTAssertTrue(sut.canSave)
    }

    func testSeedPrefillsTopicAndHint() {
        let seeded = MemoEditorViewModel(
            client: client,
            seed: MemoRequest(topic: "Travel", hint: "since March", save: true),
        )
        XCTAssertEqual(seeded.topic, "Travel")
        XCTAssertEqual(seeded.hint, "since March")
    }

    func testSaveHappyPath() async {
        sut.topic = " sleep "
        sut.hint = "  "
        await sut.save()
        if case let .saved(response) = sut.phase {
            XCTAssertEqual(response.path, "memos/2026-05-17/sleep-patterns.md")
        } else {
            XCTFail("expected saved, got \(sut.phase)")
        }
        XCTAssertEqual(client.generateCalls.count, 1)
        XCTAssertEqual(client.generateCalls.first?.topic, "sleep")
        XCTAssertNil(client.generateCalls.first?.hint)
        XCTAssertEqual(client.generateCalls.first?.save, true)
    }

    func testSaveFailureAdvancesToFailed() async {
        client.generateResult = .failure(APIError.unauthorized)
        sut.topic = "sleep"
        await sut.save()
        if case .failed = sut.phase {} else {
            XCTFail("expected failed, got \(sut.phase)")
        }
    }

    func testSaveBlankTopicIsNoop() async {
        sut.topic = "   "
        await sut.save()
        XCTAssertEqual(sut.phase, .editing)
        XCTAssertTrue(client.generateCalls.isEmpty)
    }
}
