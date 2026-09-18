// LuminaVaultClient/LuminaVaultClientTests/GuidedStartHermieStateTests.swift
//
// Which reaction the wizard asks Hermie for, in every phase it can be in.
//
// `GuidedStartCoordinator.hermieState(for:isAllDone:)` is a pure function
// over `Phase` and one bool, which is what lets this enumerate the mapping
// *exhaustively* — every phase, every step, both completion values — rather
// than sampling it.
//
// Two of the assertions here are negative, and they are the reason the file
// exists. `sleeping` and `sad` have reactions (`HermieMotion` covers all
// seven states, because other features drive those two), but nothing in the
// wizard may reach them: a first-time user who has not started yet should be
// invited, not shown a mascot asleep, and there is no wizard input that means
// "failed". Web reached the same conclusion and added the same test, so
// neither platform can wire one up silently.
//
// Every case is `async` on purpose: this toolchain aborts
// (`malloc: pointer being freed was not allocated`) on a *synchronous* test
// method in a `@MainActor` XCTestCase, repo-wide and unrelated to this code.

import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class GuidedStartHermieStateTests: XCTestCase {

    private static let started = Date(timeIntervalSince1970: 1_757_865_429)

    /// Every phase the coordinator can publish, paired with both values of
    /// `progress.isAllDone`. If a case is added to `Phase` the compiler will
    /// not catch it here, so `testEveryPhaseIsCovered` does.
    private var allInputs: [(GuidedStartCoordinator.Phase, Bool)] {
        var inputs: [(GuidedStartCoordinator.Phase, Bool)] = []
        for allDone in [false, true] {
            inputs.append((.idle, allDone))
            inputs.append((.finished, allDone))
            for step in GuidedStartStep.allCases {
                inputs.append((.active(step, startedAt: Self.started), allDone))
                inputs.append((.celebrating(step), allDone))
            }
        }
        return inputs
    }

    // MARK: - The mapping

    func testRestingCardIsIdle() async {
        XCTAssertEqual(state(.idle, allDone: false), .idle)
    }

    /// Steps 1 and 3 are `thinking` — Hermie is waiting on the user.
    func testOpenStepsOneAndThreeAreThinking() async {
        XCTAssertEqual(state(.active(.saveMemory, startedAt: Self.started)), .thinking)
        XCTAssertEqual(state(.active(.ask, startedAt: Self.started)), .thinking)
    }

    /// Step 2 is `learning`, not `thinking`, and this is a deliberate
    /// deviation from the wording of the shared contract — matched on web,
    /// with the contract being amended rather than the platforms disagreeing.
    /// "Sync & Learn" hands Hermie something to read, and `learning` is
    /// already defined as the absorb pulse for a compile or embedding job.
    func testSyncAndLearnIsLearningNotThinking() async {
        XCTAssertEqual(
            state(.active(.syncLearn, startedAt: Self.started)),
            .learning,
            "step 2 is literally a compile; it gets the absorb pulse"
        )
    }

    func testAStepCompletingIsHappyAndTheLastOneCelebrates() async {
        for step in GuidedStartStep.allCases {
            XCTAssertEqual(state(.celebrating(step), allDone: false), .happy)
            XCTAssertEqual(state(.celebrating(step), allDone: true), .celebrating)
        }
        XCTAssertEqual(state(.finished, allDone: true), .celebrating)
        XCTAssertEqual(
            state(.finished, allDone: false), .celebrating,
            "the finished card celebrates regardless — it is the end of the loop"
        )
    }

    // MARK: - What the wizard must never ask for

    /// The negative half. Adding a `sleeping` trigger here would need this
    /// test changed, which is the point.
    func testNoWizardInputEverPutsHermieToSleep() async {
        for (phase, allDone) in allInputs {
            XCTAssertNotEqual(
                GuidedStartCoordinator.hermieState(for: phase, isAllDone: allDone),
                .sleeping,
                "\(phase) / allDone=\(allDone): a user who has not started yet is invited, not asleep"
            )
        }
    }

    func testNoWizardInputEverMakesHermieSad() async {
        for (phase, allDone) in allInputs {
            XCTAssertNotEqual(
                GuidedStartCoordinator.hermieState(for: phase, isAllDone: allDone),
                .sad,
                "\(phase) / allDone=\(allDone): no wizard input means 'failed'"
            )
        }
    }

    /// The wizard's whole vocabulary, so a new reaction cannot appear without
    /// a decision being recorded here.
    func testTheWizardUsesExactlyFiveOfTheSevenStates() async {
        let used = Set(allInputs.map { GuidedStartCoordinator.hermieState(for: $0.0, isAllDone: $0.1) })
        XCTAssertEqual(used, [.idle, .thinking, .learning, .happy, .celebrating])
        XCTAssertEqual(
            Set(HermieMascotState.allCases).subtracting(used), [.sleeping, .sad],
            "the two states the wizard deliberately does not reach"
        )
    }

    /// `allInputs` is hand-rolled, so this pins that it really does cover the
    /// phases — a fifth `Phase` case would otherwise slip past the negatives
    /// above unnoticed.
    func testEveryPhaseIsCovered() async {
        let phases = allInputs.map(\.0)
        XCTAssertTrue(phases.contains(.idle))
        XCTAssertTrue(phases.contains(.finished))
        for step in GuidedStartStep.allCases {
            XCTAssertTrue(phases.contains(.active(step, startedAt: Self.started)), "\(step)")
            XCTAssertTrue(phases.contains(.celebrating(step)), "\(step)")
        }
        // 2 constants + 2 per step, times both completion values.
        XCTAssertEqual(allInputs.count, (2 + 2 * GuidedStartStep.allCases.count) * 2)
    }

    // MARK: - Helper

    private func state(
        _ phase: GuidedStartCoordinator.Phase,
        allDone: Bool = false
    ) -> HermieMascotState {
        GuidedStartCoordinator.hermieState(for: phase, isAllDone: allDone)
    }
}
