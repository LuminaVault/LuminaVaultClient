// LuminaVaultClient/LuminaVaultClientTests/HermieMotionTests.swift
//
// `HermieMotion` is the decision "does this state animate, in which way, at
// this size, under these accessibility settings" — the same kind of pure
// function as `HermieMascotPlayback.shouldPlay`, pinned the same way, with no
// view, no renderer and no Rive runtime in sight.
//
// The load-bearing group is `MARK: - The frozen frame`. Twelve committed
// snapshot baselines render this mascot (eight in `GuidedStartCardSnapshotTests`,
// four Home cases in `CaptureHomeViewSnapshotTests`) and they were recorded on
// CI before Hermie could move. They may not shift by a pixel. Those cases set
// `\.lvAmbientMotionEnabled` false, so the proof is structural: with that flag
// false every state at every size plans `.still`, and `.still` yields
// `HermiePose.identity` — no scale, no rotation, no offset, no opacity, no
// glow change — at which point `HermieMotionModifier` takes its `isStill`
// branch and applies no transform modifier at all.
//
// Every case is `async` on purpose: this toolchain aborts
// (`malloc: pointer being freed was not allocated`) on a *synchronous* test
// method in a `@MainActor` XCTestCase, repo-wide and unrelated to this code.

import CoreGraphics
import XCTest

@testable import LuminaVaultClient

@MainActor
final class HermieMotionTests: XCTestCase {

    /// Sizes the app actually renders the mascot at: chat inline, the two
    /// guided-start avatars, About, Paywall, the 140pt cluster, the empty
    /// state, the onboarding hero and the full hero.
    private let shippedSizes: [CGFloat] = [32, 56, 96, 120, 140, 160, 180, 200, 220]

    /// A full cycle at 5% steps, plus the two ends.
    private let cycleSweep: [Double] = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }

    // MARK: - The frozen frame

    /// The snapshot suites' seam. Flag false ⇒ nothing moves, for every state
    /// at every size the app ships.
    func testAmbientMotionOffIsStillForEveryStateAndSize() async {
        for state in HermieMascotState.allCases {
            for size in shippedSizes {
                XCTAssertEqual(
                    HermieMotion.plan(
                        for: state,
                        size: size,
                        reduceMotion: false,
                        ambientMotionEnabled: false
                    ),
                    .still,
                    "\(state) at \(size)pt must be still: snapshot suites set lvAmbientMotionEnabled = false"
                )
            }
        }
    }

    /// A still plan has exactly one pose, at every cycle, at every size. This
    /// is the other half of the frozen-frame proof: even if something did
    /// leave `cycle` non-zero, a still plan cannot produce a transform.
    func testStillPlanIsIdentityAtEveryCycleAndSize() async {
        for size in shippedSizes {
            for cycle in cycleSweep {
                XCTAssertEqual(
                    HermieMotionPlan.still.pose(at: cycle, size: size),
                    .identity,
                    "still plan produced a transform at cycle \(cycle), size \(size)"
                )
            }
        }
        // And off the ends, in case a `repeatForever` overshoots.
        XCTAssertEqual(HermieMotionPlan.still.pose(at: -3.7, size: 220), .identity)
        XCTAssertEqual(HermieMotionPlan.still.pose(at: 42.5, size: 220), .identity)
    }

    /// Identity is literally the default: no field of it deviates.
    func testIdentityPoseIsNeutral() async {
        let identity = HermiePose.identity
        XCTAssertEqual(identity.scaleX, 1)
        XCTAssertEqual(identity.scaleY, 1)
        XCTAssertEqual(identity.rotationDegrees, 0)
        XCTAssertEqual(identity.offsetYRatio, 0)
        XCTAssertEqual(identity.opacity, 1)
        XCTAssertEqual(
            identity.glow, 1,
            "glow multiplies the two palette shadows; 1 must reproduce 0.45 / 0.20 exactly"
        )
        XCTAssertTrue(identity.isIdentity)
        XCTAssertEqual(identity.offsetY(for: 220), 0)
    }

    /// Reduce Motion always wins, independently of the ambient flag — the
    /// degradation `View.lvRepeatingAnimation` prescribes for a loop.
    func testReduceMotionIsStillForEveryState() async {
        for state in HermieMascotState.allCases {
            XCTAssertEqual(
                HermieMotion.plan(
                    for: state,
                    size: 220,
                    reduceMotion: true,
                    ambientMotionEnabled: true
                ),
                .still,
                "\(state) must not move under Reduce Motion"
            )
        }
    }

    // MARK: - Size

    /// The 32pt mascots in the chat transcript stay static: dozens of
    /// simultaneous loops would be real CPU for motion nobody can see.
    func testBelowThresholdIsStill() async {
        for state in HermieMascotState.allCases {
            for size in [CGFloat(1), 24, 32, HermieMotion.sizeThreshold - 0.5] {
                XCTAssertEqual(
                    HermieMotion.plan(
                        for: state,
                        size: size,
                        reduceMotion: false,
                        ambientMotionEnabled: true
                    ),
                    .still,
                    "\(state) at \(size)pt is too small for the motion to read"
                )
            }
        }
    }

    /// Including 56pt — the guided-start card and the spotlight bubble, the
    /// two places Hermie is most obviously meant to be doing something and
    /// the two where he was inert. Their eight committed baselines are
    /// unaffected: those suites set `\.lvAmbientMotionEnabled` false, which
    /// stills the mascot a step before size is even consulted.
    func testAtAndAboveThresholdEveryStateMoves() async {
        for state in HermieMascotState.allCases {
            for size in [HermieMotion.sizeThreshold, 56, 96, 140, 220] {
                XCTAssertNotEqual(
                    HermieMotion.plan(
                        for: state,
                        size: size,
                        reduceMotion: false,
                        ambientMotionEnabled: true
                    ),
                    .still,
                    "\(state) at \(size)pt should have a reaction"
                )
            }
        }
    }

    /// Amplitude is proportional to the rendered size, so a hero and an
    /// avatar perform the same gesture rather than the avatar twitching.
    func testTravelScalesWithRenderedSize() async {
        for state in HermieMascotState.allCases {
            let pose = HermieMotion.pose(for: state, cycle: 0.25, size: 220)
            XCTAssertEqual(
                pose.offsetY(for: 220),
                pose.offsetY(for: 110) * 2,
                accuracy: 1e-12,
                "\(state) travel must be proportional to size"
            )
        }
    }

    // MARK: - Loop seam / settle

    /// The invariant the whole design rests on: cycle 0 is exactly the
    /// resting pose for every state. A loop therefore starts from rest with
    /// no jump, and a one-shot that has not been triggered shows nothing.
    func testEveryStateRestsExactlyAtIdentityAtCycleZero() async {
        for state in HermieMascotState.allCases {
            for size in shippedSizes {
                XCTAssertEqual(
                    HermieMotion.pose(for: state, cycle: 0, size: size),
                    .identity,
                    "\(state) does not start at rest"
                )
            }
        }
    }

    /// …and returns to it at cycle 1, so an ambient loop has no seam and a
    /// one-shot settles instead of ending somewhere else. Approximate, not
    /// exact: `sin(2 * .pi)` in Double is −2.4e-16, not 0.
    func testEveryStateReturnsToRestAtCycleOne() async {
        for state in HermieMascotState.allCases {
            assertNearIdentity(
                HermieMotion.pose(for: state, cycle: 1, size: 220),
                label: "\(state) at the end of its cycle"
            )
        }
    }

    /// A loop keeps going past 1, so its curves have to stay periodic with
    /// period exactly 1 — otherwise the second lap is not the first one.
    ///
    /// Only the looping states: `happy` rides `arc`, whose period is 2, and
    /// that is fine precisely because it plays once and stops. This test
    /// found that out by failing on it.
    func testLoopsRemainPeriodicPastOne() async {
        for state in HermieMascotState.allCases where plan(state).isLooping {
            let first = HermieMotion.pose(for: state, cycle: 0.3, size: 220)
            let second = HermieMotion.pose(for: state, cycle: 1.3, size: 220)
            XCTAssertEqual(first.scaleY, second.scaleY, accuracy: 1e-12)
            XCTAssertEqual(first.rotationDegrees, second.rotationDegrees, accuracy: 1e-12)
            XCTAssertEqual(first.offsetYRatio, second.offsetYRatio, accuracy: 1e-12)
            XCTAssertEqual(first.glow, second.glow, accuracy: 1e-12)
        }
    }

    // MARK: - Which states loop

    /// Ambient states run continuously and must be gated on visibility;
    /// reactions play once and settle. Getting this backwards would either
    /// burn CPU on a completion or leave Hermie celebrating forever.
    func testAmbientStatesLoopAndReactionsDoNot() async {
        let ambient: [HermieMascotState] = [.idle, .thinking, .sad, .sleeping, .learning]
        let oneShot: [HermieMascotState] = [.happy, .celebrating]
        XCTAssertEqual(
            Set(ambient).union(oneShot), Set(HermieMascotState.allCases),
            "a new state needs a decision here"
        )

        for state in ambient {
            XCTAssertTrue(plan(state).isLooping, "\(state) is an ambient state")
        }
        for state in oneShot {
            XCTAssertFalse(plan(state).isLooping, "\(state) is a reaction, not a mood")
            XCTAssertLessThanOrEqual(
                plan(state).duration ?? .infinity, 2.0,
                "\(state) should be over before the user has moved on"
            )
        }
    }

    /// Matched state-for-state with the web implementation so the two read as
    /// one character. Changing one of these without changing the other is the
    /// failure this guards.
    func testTemposMatchTheCrossPlatformTable() async {
        XCTAssertEqual(plan(.idle).duration, 3.0)
        XCTAssertEqual(plan(.thinking).duration, 1.6)
        XCTAssertEqual(plan(.happy).duration, 2.0)
        XCTAssertEqual(plan(.sad).duration, 4.0)
        XCTAssertEqual(plan(.sleeping).duration, 4.5)
        XCTAssertEqual(plan(.learning).duration, 1.2)
        XCTAssertEqual(plan(.celebrating).duration, 0.9)
    }

    func testEveryPlanHasAPositiveDuration() async {
        for state in HermieMascotState.allCases {
            let duration = plan(state).duration
            XCTAssertNotNil(duration, "\(state)")
            XCTAssertGreaterThan(duration ?? 0, 0, "\(state)")
        }
        XCTAssertNil(HermieMotionPlan.still.duration)
    }

    // MARK: - Legibility

    /// Seven states used to render one static image. Each one now has to do
    /// something, and something of its own: no state may be secretly at rest,
    /// and no two may trace the same path.
    func testEveryStateActuallyMoves() async {
        for state in HermieMascotState.allCases {
            let peak = cycleSweep.map { deviation(HermieMotion.pose(for: state, cycle: $0, size: 220)) }
                .max() ?? 0
            XCTAssertGreaterThan(
                peak, 0.01,
                "\(state) barely deviates from rest — it would read as the static image"
            )
        }
    }

    func testNoTwoStatesTraceTheSamePath() async {
        let states = HermieMascotState.allCases
        for (i, a) in states.enumerated() {
            for b in states[(i + 1)...] {
                let pathA = cycleSweep.map { HermieMotion.pose(for: a, cycle: $0, size: 220) }
                let pathB = cycleSweep.map { HermieMotion.pose(for: b, cycle: $0, size: 220) }
                XCTAssertNotEqual(pathA, pathB, "\(a) and \(b) look the same")
            }
        }
    }

    /// `thinking` is the only state that travels sideways and `sad` the only
    /// one that loses light — those two facts are what make them readable at
    /// a glance rather than "the mascot did something".
    func testSignatureGesturesAreWhereTheyShouldBe() async {
        let thinking = HermieMotion.pose(for: .thinking, cycle: 0.25, size: 220)
        XCTAssertGreaterThan(thinking.rotationDegrees, 3, "thinking should sway")
        let thinkingBack = HermieMotion.pose(for: .thinking, cycle: 0.75, size: 220)
        XCTAssertLessThan(
            thinkingBack.rotationDegrees, -3,
            "the sway is a pendulum — it has to go both ways"
        )

        XCTAssertLessThan(
            HermieMotion.pose(for: .sad, cycle: 0.5, size: 220).glow, 0.5,
            "sad dims"
        )
        XCTAssertGreaterThan(
            HermieMotion.pose(for: .learning, cycle: 0.5, size: 220).glow, 1.5,
            "learning flares"
        )
        XCTAssertLessThan(
            HermieMotion.pose(for: .happy, cycle: 0.5, size: 220).offsetYRatio, -0.05,
            "happy leaves the ground"
        )
        XCTAssertLessThan(
            HermieMotion.pose(for: .celebrating, cycle: 0.25, size: 220).offsetYRatio, -0.05,
            "celebrating's first hop"
        )
        XCTAssertLessThan(
            HermieMotion.pose(for: .celebrating, cycle: 0.75, size: 220).offsetYRatio, -0.05,
            "…and its second — that is what makes it a double hop"
        )
        XCTAssertGreaterThan(
            HermieMotion.pose(for: .sleeping, cycle: 0.5, size: 220).scaleY,
            HermieMotion.pose(for: .idle, cycle: 0.5, size: 220).scaleY,
            "sleeping breathes deeper than idle"
        )
    }

    /// Nothing here is a cartoon. These are the bounds of "a reaction", past
    /// which the mascot would be overlapping its neighbours or flickering.
    func testPosesStayWithinSaneBounds() async {
        for state in HermieMascotState.allCases {
            for cycle in cycleSweep {
                let pose = HermieMotion.pose(for: state, cycle: cycle, size: 220)
                let where_ = "\(state) at cycle \(cycle)"
                // The widest excursion in the set is `happy`'s landing squash
                // at 0.91 scaleY / 1.07 scaleX. Anything past this stops
                // reading as a mascot reacting and starts reading as a bug.
                XCTAssertTrue((0.90...1.10).contains(pose.scaleX), "\(where_) scaleX \(pose.scaleX)")
                XCTAssertTrue((0.90...1.10).contains(pose.scaleY), "\(where_) scaleY \(pose.scaleY)")
                XCTAssertLessThanOrEqual(abs(pose.rotationDegrees), 7, where_)
                XCTAssertLessThanOrEqual(abs(pose.offsetYRatio), 0.12, where_)
                XCTAssertTrue((0.80...1.0).contains(pose.opacity), "\(where_) opacity \(pose.opacity)")
                XCTAssertTrue((0.30...2.0).contains(pose.glow), "\(where_) glow \(pose.glow)")
                // The glow multiplies shadow opacities, which must stay legal.
                XCTAssertTrue((0.0...1.0).contains(0.45 * pose.glow), where_)
                XCTAssertTrue((0.0...1.0).contains(0.20 * pose.glow), where_)
            }
        }
    }

    // MARK: - Curves

    /// The four curves are where the frozen-frame guarantee actually comes
    /// from: a pose cannot deviate at the seam if every term it is built from
    /// vanishes there.
    func testEveryCurveVanishesAtBothEndsOfTheCycle() async {
        for (name, curve) in curves {
            XCTAssertEqual(curve(0), 0, accuracy: 1e-15, "\(name) at cycle 0")
            XCTAssertEqual(curve(1), 0, accuracy: 1e-12, "\(name) at cycle 1")
        }
    }

    func testCurvesReachTheirPeaks() async {
        XCTAssertEqual(HermieMotion.breath(0.5), 1, accuracy: 1e-12)
        XCTAssertEqual(HermieMotion.arc(0.5), 1, accuracy: 1e-12)
        XCTAssertEqual(HermieMotion.swing(0.25), 1, accuracy: 1e-12)
        XCTAssertEqual(HermieMotion.swing(0.75), -1, accuracy: 1e-12)
        XCTAssertEqual(HermieMotion.hops(0.25), 1, accuracy: 1e-12)
        XCTAssertEqual(HermieMotion.hops(0.75), 1, accuracy: 1e-12)
        XCTAssertEqual(HermieMotion.wiggle(0.125), 1, accuracy: 1e-12)
        XCTAssertEqual(HermieMotion.wiggle(0.375), -1, accuracy: 1e-12)
    }

    // MARK: - Helpers

    private var curves: [(String, (Double) -> Double)] {
        [
            ("breath", HermieMotion.breath),
            ("swing", HermieMotion.swing),
            ("arc", HermieMotion.arc),
            ("hops", HermieMotion.hops),
            ("wiggle", HermieMotion.wiggle),
        ]
    }

    private func plan(_ state: HermieMascotState) -> HermieMotionPlan {
        HermieMotion.plan(for: state, size: 220, reduceMotion: false, ambientMotionEnabled: true)
    }

    /// How far this pose is from rest, on a scale where ~0.01 is invisible.
    /// Rotation is divided by 100 so a degree counts for about a percent of
    /// scale, which is roughly how they read.
    private func deviation(_ pose: HermiePose) -> Double {
        max(
            abs(Double(pose.scaleX) - 1),
            abs(Double(pose.scaleY) - 1),
            abs(pose.rotationDegrees) / 100,
            abs(Double(pose.offsetYRatio)),
            abs(1 - pose.opacity),
            abs(pose.glow - 1)
        )
    }

    private func assertNearIdentity(
        _ pose: HermiePose,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Double(pose.scaleX), 1, accuracy: 1e-12, "\(label) scaleX", file: file, line: line)
        XCTAssertEqual(Double(pose.scaleY), 1, accuracy: 1e-12, "\(label) scaleY", file: file, line: line)
        XCTAssertEqual(pose.rotationDegrees, 0, accuracy: 1e-12, "\(label) rotation", file: file, line: line)
        XCTAssertEqual(Double(pose.offsetYRatio), 0, accuracy: 1e-12, "\(label) offset", file: file, line: line)
        XCTAssertEqual(pose.opacity, 1, accuracy: 1e-12, "\(label) opacity", file: file, line: line)
        XCTAssertEqual(pose.glow, 1, accuracy: 1e-12, "\(label) glow", file: file, line: line)
    }
}
