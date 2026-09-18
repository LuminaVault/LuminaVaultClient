// LuminaVaultClient/LuminaVaultClientTests/GuidedStartStepTests.swift
//
// Guided start — the step vocabulary and the progress derivation.
//
// The step ids double as the analytics `step` property and the spotlight
// target names on every platform, so they are asserted literally here: a
// rename that survives compilation still breaks the shared PostHog funnel.
// Copy is asserted verbatim against `docs/guided-start.md`.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

final class GuidedStartStepTests: XCTestCase {

    // MARK: - Ids and ordering

    func testRawValuesAreTheContractIds() {
        XCTAssertEqual(GuidedStartStep.saveMemory.rawValue, "save_memory")
        XCTAssertEqual(GuidedStartStep.syncLearn.rawValue, "sync_learn")
        XCTAssertEqual(GuidedStartStep.ask.rawValue, "ask")
    }

    func testIdentifierIsTheRawValue() {
        for step in GuidedStartStep.allCases {
            XCTAssertEqual(step.id, step.rawValue)
        }
    }

    func testDeclarationOrderIsTheLoopOrder() {
        XCTAssertEqual(GuidedStartStep.allCases, [.saveMemory, .syncLearn, .ask])
    }

    // MARK: - Copy

    func testTitlesMatchTheContract() {
        XCTAssertEqual(GuidedStartStep.saveMemory.title, "Save a memory")
        XCTAssertEqual(GuidedStartStep.syncLearn.title, "Sync & Learn")
        XCTAssertEqual(GuidedStartStep.ask.title, "Ask about it")
    }

    func testHermieLinesMatchTheContract() {
        XCTAssertEqual(
            GuidedStartStep.saveMemory.hermieLine,
            "Type anything you want to remember, then Save."
        )
        XCTAssertEqual(
            GuidedStartStep.syncLearn.hermieLine,
            "Now let me read it — tap Sync & Learn."
        )
        XCTAssertEqual(
            GuidedStartStep.ask.hermieLine,
            "Ask me anything about what you just saved."
        )
    }

    func testCardCopyMatchesTheContract() {
        XCTAssertEqual(GuidedStartCopy.headline, "Get started with Hermie")
        XCTAssertEqual(GuidedStartCopy.skip, "Skip")
        XCTAssertEqual(
            GuidedStartCopy.completion,
            "That's the whole loop. Everything you save, I learn."
        )
        XCTAssertEqual(
            GuidedStartCopy.nothingPending,
            "Save something first — then I'll have something to learn."
        )
        XCTAssertEqual(GuidedStartCopy.progress(completed: 0), "0 of 3")
        XCTAssertEqual(GuidedStartCopy.progress(completed: 2), "2 of 3")
    }

    // MARK: - Targets

    func testTargetsMatchTheContract() {
        XCTAssertEqual(GuidedStartStep.saveMemory.target, .composer)
        XCTAssertEqual(GuidedStartStep.syncLearn.target, .sync)
        XCTAssertEqual(GuidedStartStep.ask.target, .chat)
    }

    func testTargetRawValuesAreStable() {
        XCTAssertEqual(GuidedTarget.composer.rawValue, "composer")
        XCTAssertEqual(GuidedTarget.sync.rawValue, "sync")
        XCTAssertEqual(GuidedTarget.chat.rawValue, "chat")
    }

    // MARK: - Latch mapping

    func testEachStepReadsItsOwnLatch() {
        let capture = makeStepState(capture: true)
        XCTAssertTrue(GuidedStartStep.saveMemory.isComplete(in: capture))
        XCTAssertFalse(GuidedStartStep.syncLearn.isComplete(in: capture))
        XCTAssertFalse(GuidedStartStep.ask.isComplete(in: capture))

        let compile = makeStepState(compile: true)
        XCTAssertFalse(GuidedStartStep.saveMemory.isComplete(in: compile))
        XCTAssertTrue(GuidedStartStep.syncLearn.isComplete(in: compile))
        XCTAssertFalse(GuidedStartStep.ask.isComplete(in: compile))

        let query = makeStepState(query: true)
        XCTAssertFalse(GuidedStartStep.saveMemory.isComplete(in: query))
        XCTAssertFalse(GuidedStartStep.syncLearn.isComplete(in: query))
        XCTAssertTrue(GuidedStartStep.ask.isComplete(in: query))
    }

    // MARK: - Progress

    func testProgressOnAFreshAccount() {
        let progress = GuidedStartProgress(makeStepState())
        XCTAssertEqual(progress.completed, [])
        XCTAssertEqual(progress.completedCount, 0)
        XCTAssertEqual(progress.next, .saveMemory)
        XCTAssertFalse(progress.isAllDone)
    }

    func testProgressPicksFirstIncompleteInDeclarationOrder() {
        let progress = GuidedStartProgress(makeStepState(capture: true))
        XCTAssertEqual(progress.completed, [.saveMemory])
        XCTAssertEqual(progress.completedCount, 1)
        XCTAssertEqual(progress.next, .syncLearn)
        XCTAssertFalse(progress.isAllDone)
    }

    /// A latch can flip out of order (a chat reply on another device latches
    /// `firstQueryCompleted` before anything was compiled). `next` is still
    /// the first incomplete step, not the one after the highest complete one.
    func testProgressSkipsOutOfOrderLatches() {
        let progress = GuidedStartProgress(makeStepState(capture: true, query: true))
        XCTAssertEqual(progress.completed, [.saveMemory, .ask])
        XCTAssertEqual(progress.completedCount, 2)
        XCTAssertEqual(progress.next, .syncLearn)
        XCTAssertFalse(progress.isAllDone)
    }

    func testProgressIsAllDoneWhenEveryLatchIsTrue() {
        let progress = GuidedStartProgress(makeStepState(capture: true, compile: true, query: true))
        XCTAssertEqual(progress.completedCount, 3)
        XCTAssertNil(progress.next)
        XCTAssertTrue(progress.isAllDone)
    }

    /// `nil` is "not loaded", not "nothing done" — but it must still be a
    /// usable value so the card can render nothing without special-casing.
    func testProgressFromNoSnapshotIsEmpty() {
        let progress = GuidedStartProgress(nil)
        XCTAssertEqual(progress.completedCount, 0)
        XCTAssertEqual(progress.next, .saveMemory)
        XCTAssertFalse(progress.isAllDone)
    }
}

// MARK: - Fixture

func makeStepState(
    capture: Bool = false,
    compile: Bool = false,
    query: Bool = false
) -> OnboardingStateDTO {
    OnboardingStateDTO(
        signupCompleted: true,
        signupCompletedAt: nil,
        emailVerifiedCompleted: true,
        emailVerifiedCompletedAt: nil,
        soulConfiguredCompleted: true,
        soulConfiguredCompletedAt: nil,
        firstCaptureCompleted: capture,
        firstCaptureCompletedAt: nil,
        firstKBCompileCompleted: compile,
        firstKBCompileCompletedAt: nil,
        firstQueryCompleted: query,
        firstQueryCompletedAt: nil,
        brainConfiguredCompleted: true,
        brainConfiguredCompletedAt: nil
    )
}
