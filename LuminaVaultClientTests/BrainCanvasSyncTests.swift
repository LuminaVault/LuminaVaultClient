// The rules between the 2D canvas and its layout actor: one live run at a
// time with a late teardown unable to touch a newer run, the graph resent on
// every run, a lost pin release redone, the generation filter, and when the
// view frames the graph (fresh graph on every step, refit once a reheat
// settles, never while a point is dragged).

import CoreGraphics
@testable import LuminaVaultClient
import Testing

struct BrainCanvasSyncTests {
    private func snap(_ ids: [String], generation: Int, settled: Bool = false) -> LayoutSnapshot {
        LayoutSnapshot(ids: ids, points: ids.map { _ in .zero }, settled: settled, generation: generation)
    }

    private let auto = BrainCanvasSync.ViewFacts(automatic: true, dragging: false, reduceMotion: false)

    // MARK: Runs

    @Test func aLateTeardownOfAnOldRunDoesNotClearTheNewRunsChannel() {
        var s = BrainCanvasSync()
        let old = s.startRun(key: 1).token
        // Quick disappear and appear: the new run starts before the old one's tail.
        let new = s.startRun(key: 1).token
        let r1 = s.endRun(old)
        #expect(!r1)
        #expect(s.liveRun == new)
        let r2 = s.endRun(new)
        #expect(r2)
        #expect(s.liveRun == nil)
    }

    @Test func everyRunResendsTheGraphEvenWhenTheLastRunQueuedThatKey() {
        var s = BrainCanvasSync()
        let first = s.startRun(key: 7)
        #expect(first.sends == [.graph])
        // The run is cancelled before the actor took the graph: the next run
        // must send it again, or the actor never gets it.
        _ = s.endRun(first.token)
        let r3 = s.startRun(key: 7).sends
        #expect(r3 == [.graph])
    }

    @Test func aGraphChangeIsSentOnlyDuringARunAndOnlyWhenTheKeyChanged() {
        var s = BrainCanvasSync()
        let r4 = s.graphChanged(key: 2)
        #expect(!r4)
        _ = s.startRun(key: 1)
        let r5 = s.graphChanged(key: 2)
        #expect(r5)
        let r6 = s.graphChanged(key: 2)
        #expect(!r6)
        let r7 = s.graphChanged(key: 1)
        #expect(r7)
    }

    @Test func aPinReleaseLostWithTheOldRunIsRedoneAtTheNextStart() {
        var s = BrainCanvasSync()
        let run = s.startRun(key: 1).token
        s.pinned("a")
        // The release was queued but the run ended before the actor took it.
        _ = s.endRun(run)
        let r8 = s.startRun(key: 1).sends
        #expect(r8 == [.release("a"), .graph])
    }

    @Test func aDeliveredReleaseIsNotRedone() {
        var s = BrainCanvasSync()
        _ = s.startRun(key: 1)
        s.pinned("a")
        s.releaseDelivered("a")
        let r9 = s.startRun(key: 1).sends
        #expect(r9 == [.graph])
    }

    @Test func aReleaseOfAnotherPointLeavesTheHeldOneHeld() {
        var s = BrainCanvasSync()
        _ = s.startRun(key: 1)
        s.pinned("a")
        s.releaseDelivered("b")
        let r10 = s.startRun(key: 1).sends
        #expect(r10 == [.release("a"), .graph])
    }

    // MARK: Generations

    @Test func snapshotsStillArriveWhenAQueuedGraphWasLostWithItsRun() {
        var s = BrainCanvasSync()
        let run = s.startRun(key: 1).token
        let r11 = s.receive(snap(["a"], generation: 1, settled: true), view: auto).accept
        #expect(r11)
        // A new graph is queued, then the run is cancelled before the actor takes it.
        let r12 = s.graphChanged(key: 2)
        #expect(r12)
        _ = s.endRun(run)
        // The next run: the actor republishes what it has (still generation
        // 1), then takes the resent graph.
        _ = s.startRun(key: 2)
        let r13 = s.receive(snap(["a"], generation: 1, settled: true), view: auto).accept
        #expect(r13)
        let r14 = s.receive(snap(["a", "b"], generation: 2), view: auto).accept
        #expect(r14)
    }

    @Test func aSnapshotOlderThanOneAlreadySeenIsDropped() {
        var s = BrainCanvasSync()
        _ = s.receive(snap(["a"], generation: 3), view: auto)
        let r15 = s.receive(snap(["a"], generation: 2), view: auto).accept
        #expect(!r15)
        let r16 = s.receive(snap(["a"], generation: 3), view: auto).accept
        #expect(r16)
    }

    // MARK: Framing

    @Test func aFreshGraphIsFramedOnEveryStepAndExactlyWhenItSettles() {
        var s = BrainCanvasSync()
        let first = s.receive(snap(["a", "b"], generation: 1), view: auto)
        #expect(first.resetAutomatic)
        #expect(first.fit == .now)
        let r17 = s.receive(snap(["a", "b"], generation: 1), view: auto).fit
        #expect(r17 == .now)
        let r18 = s.receive(snap(["a", "b"], generation: 1, settled: true), view: auto).fit
        #expect(r18 == .now)
        // Settled: nothing more until something changes.
        let r19 = s.receive(snap(["a", "b"], generation: 1, settled: true), view: auto).fit
        #expect(r19 == .none)
    }

    @Test func aFreshGraphReturnsAMovedViewToTheAutomaticFit() {
        var s = BrainCanvasSync()
        _ = s.receive(snap(["a"], generation: 1, settled: true), view: auto)
        let moved = BrainCanvasSync.ViewFacts(automatic: false, dragging: false, reduceMotion: false)
        let fresh = s.receive(snap(["x", "y"], generation: 2), view: moved)
        #expect(fresh.resetAutomatic)
        #expect(fresh.fit == .now)
    }

    @Test func aChangeInWhichPointsShowGlidesToTheNewFitOnceItSettles() {
        var s = BrainCanvasSync()
        _ = s.receive(snap(["a", "b"], generation: 1, settled: true), view: auto)
        let reheat = s.receive(snap(["a", "b", "c"], generation: 2), view: auto)
        #expect(!reheat.resetAutomatic)
        #expect(reheat.fit == .none)
        let r20 = s.receive(snap(["a", "b", "c"], generation: 2, settled: true), view: auto).fit
        #expect(r20 == .eased)
    }

    @Test func underReduceMotionTheRefitIsImmediate() {
        var s = BrainCanvasSync()
        let quiet = BrainCanvasSync.ViewFacts(automatic: true, dragging: false, reduceMotion: true)
        _ = s.receive(snap(["a", "b"], generation: 1, settled: true), view: quiet)
        _ = s.receive(snap(["a"], generation: 2), view: quiet)
        let r21 = s.receive(snap(["a"], generation: 2, settled: true), view: quiet).fit
        #expect(r21 == .now)
    }

    @Test func noRefitOnceTheUserMovedTheView() {
        var s = BrainCanvasSync()
        _ = s.receive(snap(["a", "b"], generation: 1, settled: true), view: auto)
        let moved = BrainCanvasSync.ViewFacts(automatic: false, dragging: false, reduceMotion: false)
        _ = s.receive(snap(["a", "b", "c"], generation: 2), view: moved)
        let r22 = s.receive(snap(["a", "b", "c"], generation: 2, settled: true), view: moved).fit
        #expect(r22 == .none)
    }

    @Test func neverRefitsUnderAPointBeingDragged() {
        var s = BrainCanvasSync()
        let dragging = BrainCanvasSync.ViewFacts(automatic: true, dragging: true, reduceMotion: false)
        let r23 = s.receive(snap(["a", "b"], generation: 1), view: dragging).fit
        #expect(r23 == .none)
        // The owed fit is dropped at the settle, as on the web.
        let r24 = s.receive(snap(["a", "b"], generation: 1, settled: true), view: dragging).fit
        #expect(r24 == .none)
        let r25 = s.receive(snap(["a", "b"], generation: 1, settled: true), view: auto).fit
        #expect(r25 == .none)
    }

    @Test func aResentGraphWithTheSamePointsFramesNothing() {
        var s = BrainCanvasSync()
        _ = s.receive(snap(["a", "b"], generation: 1, settled: true), view: auto)
        let again = s.receive(snap(["a", "b"], generation: 2), view: auto)
        #expect(!again.resetAutomatic)
        #expect(again.fit == .none)
        let r26 = s.receive(snap(["a", "b"], generation: 2, settled: true), view: auto).fit
        #expect(r26 == .none)
    }

    @Test func pointsSeenBeforeMakeAGraphAnUpdateNotAFreshGraph() {
        var s = BrainCanvasSync()
        _ = s.receive(snap(["a", "b"], generation: 1, settled: true), view: auto)
        _ = s.receive(snap(["a"], generation: 2, settled: true), view: auto)
        // "b" was hidden, not forgotten.
        let r27 = s.receive(snap(["b"], generation: 3), view: auto).resetAutomatic
        #expect(!r27)
    }
}
