// The rules between the 2D canvas and its layout actor: one live run at a
// time with a late teardown unable to touch a newer run, the graph resent on
// every run, a lost pin release redone, the generation filter, and when the
// view frames the graph (fresh graph on every step, refit once a reheat
// settles, never while a point is dragged).

import CoreGraphics
import LuminaVaultShared
import SwiftUI
@testable import LuminaVaultClient
import Testing

struct BrainCanvasSyncTests {
    private func snap(_ ids: [String], generation: Int, settled: Bool = false) -> LayoutSnapshot {
        LayoutSnapshot(ids: ids, points: ids.map { _ in .zero }, settled: settled, generation: generation)
    }

    private let auto = BrainCanvasSync.ViewFacts(automatic: true, dragging: false, reduceMotion: false)

    // MARK: Runs

    /// A sync that knows graph `key` and has a live run.
    private func running(key: Int = 1) -> (BrainCanvasSync, Int) {
        var s = BrainCanvasSync()
        _ = s.graphChanged(key: key)
        let token = s.startRun().token
        return (s, token)
    }

    @Test func aLateTeardownOfAnOldRunDoesNotClearTheNewRunsChannel() {
        var (s, old) = running()
        // Quick disappear and appear: the new run starts before the old one's tail.
        let new = s.startRun().token
        let oldCleared = s.endRun(old)
        #expect(!oldCleared)
        #expect(s.liveRun == new)
        let newCleared = s.endRun(new)
        #expect(newCleared)
        #expect(s.liveRun == nil)
    }

    @Test func everyRunResendsTheGraphEvenWhenTheLastRunQueuedThatKey() {
        var s = BrainCanvasSync()
        _ = s.graphChanged(key: 7)
        let first = s.startRun()
        #expect(first.sends == [.graph(key: 7)])
        // The run is cancelled before the actor took the graph: the next run
        // must send it again, or the actor never gets it.
        _ = s.endRun(first.token)
        let again = s.startRun().sends
        #expect(again == [.graph(key: 7)])
    }

    @Test func aRunStartsWithTheLatestGraphEvenIfItChangedWhileTheRunWaited() {
        var (s, old) = running(key: 1)
        let queuedOnOld = s.graphChanged(key: 2)
        #expect(queuedOnOld)
        // The old run is cancelled; while the new run waits at the gate the
        // graph changes again, and the old run's sink may drop both.
        _ = s.graphChanged(key: 3)
        _ = s.endRun(old)
        let sends = s.startRun().sends
        #expect(sends == [.graph(key: 3)])
    }

    @Test func withNoGraphYetARunSendsNothingAndTheFirstGraphIsQueued() {
        var s = BrainCanvasSync()
        let sends = s.startRun().sends
        #expect(sends.isEmpty)
        let queued = s.graphChanged(key: 4)
        #expect(queued)
    }

    @Test func aGraphChangeIsSentOnlyDuringARunAndOnlyWhenTheKeyChanged() {
        var s = BrainCanvasSync()
        let outsideRun = s.graphChanged(key: 1)
        #expect(!outsideRun)
        _ = s.startRun()
        let changed = s.graphChanged(key: 2)
        let same = s.graphChanged(key: 2)
        let back = s.graphChanged(key: 1)
        #expect(changed)
        #expect(!same)
        #expect(back)
    }

    @Test func aPinReleaseLostWithTheOldRunIsRedoneAtTheNextStart() {
        var (s, run) = running()
        s.pinned("a")
        let seq = s.releaseSeq("a")
        // The release was queued but the run ended before the actor took it.
        _ = s.endRun(run)
        let sends = s.startRun().sends
        #expect(seq != nil)
        #expect(sends == [.release("a", seq: seq ?? -1), .graph(key: 1)])
    }

    @Test func aDeliveredReleaseIsNotRedone() {
        var (s, _) = running()
        s.pinned("a")
        s.releaseDelivered("a", seq: s.releaseSeq("a") ?? -1)
        let sends = s.startRun().sends
        #expect(sends == [.graph(key: 1)])
    }

    @Test func aReleaseOfAnotherPointLeavesTheHeldOneHeld() {
        var (s, _) = running()
        s.pinned("a")
        let seq = s.releaseSeq("a") ?? -1
        s.releaseDelivered("b", seq: seq)
        let sends = s.startRun().sends
        #expect(sends == [.release("a", seq: seq), .graph(key: 1)])
    }

    @Test func draggingAnotherPointBeforeTheFirstReleaseLandsKeepsBothTracked() {
        var (s, run) = running()
        s.pinned("a")
        let a = s.releaseSeq("a") ?? -1
        // a's release is queued, not yet taken; the user drags b.
        s.pinned("b")
        let b = s.releaseSeq("b") ?? -1
        _ = s.endRun(run)
        let sends = s.startRun().sends
        #expect(sends == [.release("a", seq: a), .release("b", seq: b), .graph(key: 1)])
    }

    @Test func anOlderReleaseLandingDoesNotClearANewerDragOfTheSamePoint() {
        var (s, run) = running()
        s.pinned("a")
        let first = s.releaseSeq("a") ?? -1
        // Released (queued), then dragged again before the release lands.
        s.pinned("a")
        let second = s.releaseSeq("a") ?? -1
        s.releaseDelivered("a", seq: first)
        #expect(second != first)
        _ = s.endRun(run)
        let sends = s.startRun().sends
        #expect(sends == [.release("a", seq: second), .graph(key: 1)])
    }

    // MARK: Generations

    @Test func snapshotsStillArriveWhenAQueuedGraphWasLostWithItsRun() {
        var (s, run) = running(key: 1)
        let r11 = s.receive(snap(["a"], generation: 1, settled: true), view: auto).accept
        #expect(r11)
        // A new graph is queued, then the run is cancelled before the actor takes it.
        let r12 = s.graphChanged(key: 2)
        #expect(r12)
        _ = s.endRun(run)
        // The next run: the actor republishes what it has (still generation
        // 1), then takes the resent graph.
        let restart = s.startRun().sends
        #expect(restart == [.graph(key: 2)])
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

// MARK: - Positions paired with the current scene

@MainActor
struct BrainPositionCacheTests {
    private static func graph(_ ids: [String]) -> VisibleBrainGraph {
        let nodes = ids.map { BrainGraphNodeDTO(id: $0, kind: .note, label: $0, weight: 1) }
        var index = BrainGraphIndex()
        for n in nodes { index.byID[n.id] = n }
        return VisibleBrainGraph(nodes: nodes, edges: [], index: index)
    }

    private static func scene(_ ids: [String]) -> BrainCanvasScene {
        BrainCanvasScene(graph: graph(ids)) { _ in Color.blue }
    }

    /// The snapshot sorts ids; each id's point is distinct.
    private let snapshot = LayoutSnapshot(
        ids: ["a", "b", "c", "d"],
        points: [CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 3, y: 0), CGPoint(x: 4, y: 0)],
        settled: true,
        generation: 1
    )

    private func expectEachIDAtItsOwnPoint(_ points: [CGPoint], _ scene: BrainCanvasScene) {
        #expect(points.count == scene.ids.count)
        for (i, id) in scene.ids.enumerated() where i < points.count {
            guard let at = snapshot.ids.firstIndex(of: id) else { continue }
            #expect(points[i] == snapshot.points[at], "\(id)")
        }
    }

    @Test func aGraphChangeWithTheSameCountRealignsTheSameSnapshot() {
        var cache = BrainPositionCache()
        let before = Self.scene(["a", "b", "c"])
        expectEachIDAtItsOwnPoint(cache.positions(snapshot: snapshot, serial: 1, scene: before), before)
        // A filter swaps "c" for "d" while the canvas stays up: same count, other ids.
        let after = Self.scene(["d", "a", "b"])
        expectEachIDAtItsOwnPoint(cache.positions(snapshot: snapshot, serial: 1, scene: after), after)
    }

    @Test func aGraphChangeWithAnotherCountRealignsToo() {
        var cache = BrainPositionCache()
        _ = cache.positions(snapshot: snapshot, serial: 1, scene: Self.scene(["a", "b"]))
        let after = Self.scene(["c", "a", "d", "b"])
        expectEachIDAtItsOwnPoint(cache.positions(snapshot: snapshot, serial: 1, scene: after), after)
    }

    @Test func alignsOncePerSnapshotAndScenePair() {
        var cache = BrainPositionCache()
        let scene = Self.scene(["a", "b", "c"])
        for _ in 0 ..< 5 { _ = cache.positions(snapshot: snapshot, serial: 1, scene: scene) }
        #expect(cache.alignments == 1)
        _ = cache.positions(snapshot: snapshot, serial: 2, scene: scene)
        #expect(cache.alignments == 2)
        // A recolour builds a new scene with the same key: nothing to redo.
        _ = cache.positions(snapshot: snapshot, serial: 2, scene: BrainCanvasScene(graph: Self.graph(["a", "b", "c"])) { _ in Color.red })
        #expect(cache.alignments == 2)
    }

    @Test func noSnapshotMeansNoPoints() {
        var cache = BrainPositionCache()
        #expect(cache.positions(snapshot: nil, serial: 0, scene: Self.scene(["a"])).isEmpty)
    }
}
