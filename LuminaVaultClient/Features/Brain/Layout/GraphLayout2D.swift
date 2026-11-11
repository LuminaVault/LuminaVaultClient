// Runs the 2D Brain layout off the main actor and streams where the points
// are, so scrolling and gestures never wait on physics.
//
// The run loop: after `setGraph` or `pin` it ticks `ForceSimulation2D` in
// short batches, with a `Task.yield()` between them so new messages and
// cancellation are handled promptly, and publishes a snapshot at most every
// 33 ms. When the layout settles it publishes one snapshot with
// `settled == true` and goes idle: no timer, no polling, until the next
// `setGraph` or `pin`. A `setGraph` during a run swaps the graph under the same
// loop. Under Reduce Motion (`setQuiet(true)`) only the settled snapshot is
// published.
//
// The stream buffers only the newest snapshot, so a slow consumer never sees
// a backlog and at most one snapshot's points are held for it.

import CoreGraphics
import Foundation

nonisolated struct LayoutSnapshot: Sendable, Equatable {
    /// Sorted by id; the same order as `points`.
    var ids: [String]
    var points: [CGPoint]
    var settled: Bool
    /// Increments on every `setGraph`, so the canvas can drop snapshots of an
    /// older graph.
    var generation: Int
}

actor GraphLayout2D {
    /// Counters for tests.
    nonisolated struct Stats: Sendable, Equatable {
        var yields = 0
        var loopStarts = 0
    }

    nonisolated static let frameInterval: Duration = .milliseconds(33)
    /// A batch stops after this long or `batchMaxTicks`, whichever comes first.
    nonisolated static let batchBudget: Duration = .milliseconds(4)
    nonisolated static let batchMaxTicks = 16

    /// One stream for the life of the actor, newest snapshot only.
    nonisolated let updates: AsyncStream<LayoutSnapshot>
    private let continuation: AsyncStream<LayoutSnapshot>.Continuation
    /// Time since the actor was made, read from the injected clock.
    private let elapsed: @Sendable () -> Duration

    private var simulation = ForceSimulation2D()
    private var ids: [String] = []
    private var generation = 0
    private var quiet = false
    private var stopped = false
    private var runner: Task<Void, Never>?
    private var lastPublished: Duration?
    private(set) var stats = Stats()

    /// No run loop is active.
    var isIdle: Bool { runner == nil }

    init(clock: any Clock<Duration> = ContinuousClock()) {
        (updates, continuation) = AsyncStream.makeStream(
            of: LayoutSnapshot.self, bufferingPolicy: .bufferingNewest(1)
        )
        elapsed = Self.stopwatch(clock)
    }

    deinit {
        runner?.cancel()
        continuation.finish()
    }

    private nonisolated static func stopwatch<C: Clock<Duration>>(_ clock: C) -> @Sendable () -> Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }

    // MARK: Commands

    /// Lays out a new visible graph: known ids keep their place, newcomers start
    /// near their placed neighbours, hidden ids are parked for later.
    func setGraph(_ graph: VisibleBrainGraph) {
        guard !stopped else { return }
        simulation.setGraph(graph)
        ids = simulation.nodes.map(\.id)
        generation += 1
        wake()
    }

    /// Holds a point at `point` (a drag), or lets it go with `nil`. Unknown ids
    /// are ignored.
    func pin(_ id: String, at point: CGPoint?) {
        guard !stopped, let index = simulation.index(of: id) else { return }
        simulation.pin(index, at: point)
        wake()
    }

    /// Reduce Motion: publish only the settled snapshot of each run.
    func setQuiet(_ quiet: Bool) {
        self.quiet = quiet
    }

    func positions() -> [String: CGPoint] {
        Dictionary(uniqueKeysWithValues: zip(ids, simulation.positions))
    }

    /// Ends the run loop and finishes the stream. Later commands do nothing.
    func stop() {
        stopped = true
        runner?.cancel()
        runner = nil
        continuation.finish()
    }

    // MARK: Run loop

    private func wake() {
        guard runner == nil else { return }
        stats.loopStarts += 1
        // Holds the actor only for the length of a batch, so releasing the
        // actor ends the loop at its next batch.
        runner = Task { [weak self] in
            while !Task.isCancelled {
                guard await self?.runBatch() == true else { return }
                await Task.yield()
            }
        }
    }

    /// Ticks one batch; returns whether the loop should go on.
    private func runBatch() -> Bool {
        guard !stopped, !Task.isCancelled else { return false }
        let begin = elapsed()
        var warm = true
        var ticks = 0
        repeat {
            warm = simulation.tick()
            ticks += 1
        } while warm && ticks < Self.batchMaxTicks && elapsed() - begin < Self.batchBudget
        let now = elapsed()
        if !warm {
            publish(settled: true, at: now)
            runner = nil
            return false
        }
        if !quiet, lastPublished.map({ now - $0 >= Self.frameInterval }) ?? true {
            publish(settled: false, at: now)
        }
        return true
    }

    private func publish(settled: Bool, at now: Duration) {
        lastPublished = now
        stats.yields += 1
        continuation.yield(
            LayoutSnapshot(ids: ids, points: simulation.positions, settled: settled, generation: generation)
        )
    }
}
