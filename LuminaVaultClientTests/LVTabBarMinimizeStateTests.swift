// LuminaVaultClient/LuminaVaultClientTests/LVTabBarMinimizeStateTests.swift
//
// `LVTabBarMinimizeState` used to publish a continuous `progress: CGFloat`,
// written from `noteScroll(offsetY:)` on essentially every scroll frame. Since
// `LVTabBar` reads it and applies `.animation(_:value:)`, each write
// invalidated the bar and *restarted the spring* — roughly sixty spring
// re-targets per gesture, behind the app's busiest scroll surfaces.
//
// It is now the discrete `isMinimized`, flipped on 12pt of committed
// directional travel with reversal-resets for hysteresis. These tests pin both
// halves of that claim: the state machine itself, and — via the Observation
// runtime, the same technique as `ChatObservationScopeTests` — the fact that
// scrolling which does not cross the threshold notifies nobody.

@testable import LuminaVaultClient
import Observation
import XCTest

/// Flag written from `withObservationTracking`'s `onChange`, which is
/// `@Sendable`. Declared at file scope, outside the `@MainActor` test case, so
/// it does not inherit main-actor isolation and the callback can write it
/// without crossing an isolation boundary. `@unchecked` is sound here because
/// the Observation runtime invokes `onChange` synchronously on the thread doing
/// the mutation — which in these tests is the single test thread — so there is
/// no concurrent access to check.
private final class ObservationFlag: @unchecked Sendable {
    var fired = false
}

@MainActor
final class LVTabBarMinimizeStateTests: XCTestCase {
    /// Feeds a run of absolute content offsets, as `onScrollGeometryChange`
    /// would. The first sample only seeds the delta baseline.
    private func scroll(_ state: LVTabBarMinimizeState, through offsets: [CGFloat]) {
        for offset in offsets {
            state.noteScroll(offsetY: offset)
        }
    }

    /// Runs `body`, tracking whatever it reads, and reports whether `mutate`
    /// caused a change notification for any of those reads.
    private func didNotify(reading body: @escaping () -> Void, mutate: () -> Void) -> Bool {
        let flag = ObservationFlag()
        withObservationTracking(body) { flag.fired = true }
        mutate()
        return flag.fired
    }

    // MARK: - Threshold

    func testStartsExpanded() {
        XCTAssertFalse(LVTabBarMinimizeState().isMinimized)
    }

    func testScrollingDownPastTheThresholdMinimizes() {
        let state = LVTabBarMinimizeState()
        scroll(state, through: [0, 6, 13])
        XCTAssertTrue(state.isMinimized, "12pt of downward travel should collapse the bar")
    }

    func testScrollingDownShortOfTheThresholdDoesNothing() {
        let state = LVTabBarMinimizeState()
        scroll(state, through: [0, 4, 8, 11])
        XCTAssertFalse(state.isMinimized, "11pt is under the 12pt threshold")
    }

    func testScrollingBackUpPastTheThresholdExpands() {
        let state = LVTabBarMinimizeState()
        scroll(state, through: [0, 40])
        XCTAssertTrue(state.isMinimized)

        scroll(state, through: [26])
        XCTAssertFalse(state.isMinimized, "14pt of upward travel should re-expand the bar")
    }

    // MARK: - Hysteresis

    /// The property the whole redesign hangs on: a scroll that hovers at the
    /// boundary must not flip the bar back and forth. Reversing direction
    /// discards the travel banked the other way, so each flip costs a full
    /// 12pt of *committed* movement.
    func testOscillatingAtTheBoundaryDoesNotChatter() {
        let state = LVTabBarMinimizeState()
        state.noteScroll(offsetY: 0)

        for _ in 0..<20 {
            state.noteScroll(offsetY: 11)
            XCTAssertFalse(state.isMinimized)
            state.noteScroll(offsetY: 0)
            XCTAssertFalse(state.isMinimized)
        }
    }

    func testJitterWhileMinimizedDoesNotExpand() {
        let state = LVTabBarMinimizeState()
        scroll(state, through: [0, 400])
        XCTAssertTrue(state.isMinimized)

        for _ in 0..<20 {
            state.noteScroll(offsetY: 392)
            state.noteScroll(offsetY: 400)
        }
        XCTAssertTrue(state.isMinimized, "8pt of jitter must not re-expand a minimized bar")
    }

    /// A run of frames each under the per-frame noise floor still accumulates
    /// into a real gesture — the threshold is on committed travel, not on any
    /// single delta.
    func testSlowDragAccumulatesAcrossFrames() {
        let state = LVTabBarMinimizeState()
        state.noteScroll(offsetY: 0)
        for step in stride(from: CGFloat(1), through: 14, by: 1) {
            state.noteScroll(offsetY: step)
        }
        XCTAssertTrue(state.isMinimized)
    }

    // MARK: - Overscroll

    func testTopRubberBandIsIgnored() {
        let state = LVTabBarMinimizeState()
        scroll(state, through: [0, -30, -60, -30])
        XCTAssertFalse(state.isMinimized, "negative offsets are rubber-band, not a gesture")
    }

    /// Coming back from a rubber-band must not synthesise one huge delta out of
    /// the offsets straddling zero.
    func testRubberBandDoesNotSynthesiseAJump() {
        let state = LVTabBarMinimizeState()
        scroll(state, through: [0, -80, 0])
        XCTAssertFalse(state.isMinimized)
    }

    // MARK: - expand()

    func testExpandResetsAMinimizedBar() {
        let state = LVTabBarMinimizeState()
        scroll(state, through: [0, 400])
        XCTAssertTrue(state.isMinimized)

        state.expand()
        XCTAssertFalse(state.isMinimized)
    }

    func testExpandOnAnExpandedBarIsANoOp() {
        let state = LVTabBarMinimizeState()
        let fired = didNotify {
            _ = state.isMinimized
        } mutate: {
            state.expand()
        }
        XCTAssertFalse(fired, "expanding an already-expanded bar must not invalidate the tab bar")
    }

    /// `expand()` also drops banked travel, so tapping a tab mid-scroll cannot
    /// leave the bar one frame away from collapsing again.
    func testExpandDiscardsBankedTravel() {
        let state = LVTabBarMinimizeState()
        scroll(state, through: [0, 11])
        state.expand()
        scroll(state, through: [17])
        XCTAssertFalse(state.isMinimized, "travel banked before expand() must not count toward the next flip")
    }

    // MARK: - Observation scope

    /// The actual performance claim. `LVTabBar` reads `isMinimized` in its
    /// body and animates on it, so every notification is an invalidation plus a
    /// spring re-target. Sub-threshold scrolling must produce none.
    func testSubThresholdScrollingDoesNotNotifyObservers() {
        let state = LVTabBarMinimizeState()
        state.noteScroll(offsetY: 0)

        let fired = didNotify {
            _ = state.isMinimized
        } mutate: {
            for offset in stride(from: CGFloat(1), through: 11, by: 1) {
                state.noteScroll(offsetY: offset)
            }
        }

        XCTAssertFalse(fired, "scrolling under the threshold must not invalidate the tab bar")
    }

    /// And a full gesture must change the published state exactly once, not
    /// once per frame. Every change is one tab-bar invalidation and one spring
    /// re-target, so this count *is* the fix: 60 frames, 1 write.
    func testAFullGestureFlipsTheStateOnce() {
        let state = LVTabBarMinimizeState()
        state.noteScroll(offsetY: 0)

        var flips = 0
        var previous = state.isMinimized

        // One continuous 300pt drag down, sampled at a realistic frame rate.
        for offset in stride(from: CGFloat(0), through: 300, by: 5) {
            state.noteScroll(offsetY: offset)
            if state.isMinimized != previous {
                flips += 1
                previous = state.isMinimized
            }
        }

        XCTAssertEqual(flips, 1, "a single directional gesture should flip the bar exactly once")
        XCTAssertTrue(state.isMinimized)
    }
}
