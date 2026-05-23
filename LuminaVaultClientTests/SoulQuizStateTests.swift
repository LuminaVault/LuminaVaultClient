// LuminaVaultClient/LuminaVaultClientTests/SoulQuizStateTests.swift
// HER-100 — view-model: step advancement, resume-on-relaunch, save lifecycle.

import XCTest
@testable import LuminaVaultClient

final class SoulQuizStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuite: String!

    override func setUp() {
        super.setUp()
        defaultsSuite = "her100.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuite)
        defaults = nil
        defaultsSuite = nil
        super.tearDown()
    }

    @MainActor
    func testFreshStateStartsOnToneStep() {
        let state = SoulQuizState(userId: UUID(), defaults: defaults)
        XCTAssertEqual(state.step, .tone)
        XCTAssertNil(state.answers.tone)
    }

    @MainActor
    func testAdvanceWalksStepLadder() {
        let state = SoulQuizState(userId: UUID(), defaults: defaults)
        state.advance() // priorities
        state.advance() // style
        state.advance() // examples
        state.advance() // confirm
        XCTAssertEqual(state.step, .confirm)
        state.advance()
        XCTAssertEqual(state.step, .done)
        state.advance() // idempotent at done
        XCTAssertEqual(state.step, .done)
    }

    @MainActor
    func testResumeReadsPersistedStepAndAnswers() {
        let userId = UUID()
        let first = SoulQuizState(userId: userId, defaults: defaults)
        first.answers.tone = .playful
        first.answers.priorities = [.focus, .learning]
        first.advance() // priorities
        first.advance() // style

        // New instance reading the same UserDefaults must resume on
        // the same step with the same answers intact.
        let resumed = SoulQuizState(userId: userId, defaults: defaults)
        XCTAssertEqual(resumed.step, .style)
        XCTAssertEqual(resumed.answers.tone, .playful)
        XCTAssertEqual(resumed.answers.priorities, [.focus, .learning])
    }

    @MainActor
    func testResumeIsScopedByUserId() {
        let alice = UUID()
        let bob = UUID()
        let aliceState = SoulQuizState(userId: alice, defaults: defaults)
        aliceState.answers.tone = .formal
        aliceState.advance()
        let bobState = SoulQuizState(userId: bob, defaults: defaults)
        XCTAssertEqual(bobState.step, .tone)
        XCTAssertNil(bobState.answers.tone)
    }

    @MainActor
    func testClearPersistenceWipesSnapshot() {
        let userId = UUID()
        let state = SoulQuizState(userId: userId, defaults: defaults)
        state.answers.tone = .casual
        state.advance()
        state.clearPersistence()

        let fresh = SoulQuizState(userId: userId, defaults: defaults)
        XCTAssertEqual(fresh.step, .tone)
        XCTAssertNil(fresh.answers.tone)
    }

    @MainActor
    func testGoToJumpsToArbitraryStep() {
        let state = SoulQuizState(userId: UUID(), defaults: defaults)
        state.goTo(.examples)
        XCTAssertEqual(state.step, .examples)
    }

    @MainActor
    func testSaveLifecycleTogglesIsSavingAndError() {
        let state = SoulQuizState(userId: UUID(), defaults: defaults)
        XCTAssertFalse(state.isSaving)
        XCTAssertNil(state.saveError)

        state.beginSave()
        XCTAssertTrue(state.isSaving)
        XCTAssertNil(state.saveError)

        state.endSave(error: "boom")
        XCTAssertFalse(state.isSaving)
        XCTAssertEqual(state.saveError, "boom")

        state.beginSave()
        XCTAssertNil(state.saveError, "beginSave clears stale error")
        state.endSave(error: nil)
        XCTAssertNil(state.saveError)
    }
}
