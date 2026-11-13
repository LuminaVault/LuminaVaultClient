// Runs the 2D Brain layout off the main actor and streams where the points
// are, so scrolling and gestures never wait on physics.
//
// The run loop: after `setGraph` or `pin` it steps `ForceSimulation2D` once a
// frame (2 ticks, then a snapshot), sleeping on the injected clock between
// steps, so a settle is seen moving instead of jumping. A late step never
// catches up in a burst: the next one is due a frame after it. When the layout
// settles it publishes one snapshot with `settled == true` and goes idle: no
// timer, no polling, until the next `setGraph` or `pin`. A `setGraph` during a
// run swaps the graph under the same loop. Under Reduce Motion
// (`setQuiet(true)`) it ticks in short unpaced batches with a `Task.yield()`
// between them and publishes only the settled snapshot.
//
// Subscribing with `updates()` replaces any earlier subscriber, delivers the
// current snapshot at once and resumes a paused layout. When the subscriber
// goes away (its task is cancelled, or it drops the stream), the layout
// pauses: nothing ticks while nobody is listening. Each stream buffers only
// the newest snapshot, so a slow consumer never sees a backlog.

import CoreGraphics
import Foundation

nonisolated struct LayoutSnapshot: Sendable, Equatable {
    /// Sorted by id code units; the same order as `points`.
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
        var ticks = 0
    }

    /// One paced step per display frame.
    nonisolated static let frameInterval: Duration = .microseconds(16_667)
    nonisolated static let ticksPerFrame = 2
    /// A quiet batch stops after this long or `quietBatchTicks`, whichever
    /// comes first.
    nonisolated static let quietBatchBudget: Duration = .milliseconds(4)
    nonisolated static let quietBatchTicks = 16

    /// Time since the actor was made, and a sleep until such a time, both on
    /// the injected clock.
    private let elapsed: @Sendable () -> Duration
    private let sleepUntil: @Sendable (Duration) async throws -> Void

    private var simulation = ForceSimulation2D()
    private var ids: [String] = []
    private var generation = 0
    private var quiet = false
    private var paused = false
    private var stopped = false
    private var runner: Task<Void, Never>?
    /// When the step just run was due.
    private var lastDue: Duration = .zero
    private var continuation: AsyncStream<LayoutSnapshot>.Continuation?
    /// Identifies the current subscriber, so a late goodbye from an older one
    /// does not pause the layout.
    private var subscriber = 0
    private(set) var stats = Stats()

    /// No run loop is active.
    var isIdle: Bool { runner == nil }
    var isPaused: Bool { paused }

    init(clock: any Clock<Duration> = ContinuousClock()) {
        (elapsed, sleepUntil) = Self.timing(clock)
    }

    deinit {
        runner?.cancel()
        continuation?.finish()
    }

    private nonisolated static func timing<C: Clock<Duration>>(
        _ clock: C
    ) -> (@Sendable () -> Duration, @Sendable (Duration) async throws -> Void) {
        let start = clock.now
        return (
            { start.duration(to: clock.now) },
            { due in try await clock.sleep(until: start.advanced(by: due), tolerance: nil) }
        )
    }

    // MARK: Subscribing

    /// A stream of snapshots, newest only, starting with the current one.
    /// Replaces (finishes) any earlier subscriber's stream and resumes a
    /// paused layout. After `stop()` it returns a finished stream.
    func updates() -> AsyncStream<LayoutSnapshot> {
        let (stream, next) = AsyncStream.makeStream(of: LayoutSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        guard !stopped else {
            next.finish()
            return stream
        }
        subscriber += 1
        let token = subscriber
        let previous = continuation
        continuation = next
        next.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.subscriberLeft(token) }
        }
        previous?.finish()
        resume()
        return stream
    }

    private func subscriberLeft(_ token: Int) {
        guard token == subscriber, !stopped else { return }
        continuation = nil
        pause()
    }

    // MARK: Commands

    /// Lays out a new visible graph: known ids keep their place, newcomers start
    /// near their placed neighbours, hidden ids are parked for later. While
    /// paused the graph and generation change but nothing runs.
    func setGraph(_ graph: VisibleBrainGraph) {
        guard !stopped else { return }
        simulation.setGraph(graph)
        ids = simulation.nodes.map(\.id)
        generation += 1
        wake()
    }

    /// Holds a point at `point` (a drag), or lets it go with `nil`. Unknown ids
    /// and non-finite points are ignored; far points are clamped.
    func pin(_ id: String, at point: CGPoint?) {
        guard !stopped, let index = simulation.index(of: id) else { return }
        if let point, !(point.x.isFinite && point.y.isFinite) { return }
        simulation.pin(index, at: point)
        wake()
    }

    /// Reduce Motion: no intermediate frames, only the settled snapshot.
    func setQuiet(_ quiet: Bool) {
        self.quiet = quiet
    }

    /// Stops ticking and keeps everything else: the layout, how warm it is and
    /// the stream. `setGraph` and `pin` still update the layout but start
    /// nothing until `resume()`.
    func pause() {
        paused = true
        runner?.cancel()
        runner = nil
    }

    /// Publishes the current snapshot at once and carries on if the layout is
    /// still warm.
    func resume() {
        guard !stopped else { return }
        paused = false
        let warm = simulation.alpha >= ForceSimulation2D.settleAlpha
        if generation > 0 { publish(settled: !warm) }
        if warm { wake() }
    }

    func positions() -> [String: CGPoint] {
        Dictionary(zip(ids, simulation.positions), uniquingKeysWith: { first, _ in first })
    }

    /// Ends the run loop and finishes the stream. Later commands do nothing.
    func stop() {
        stopped = true
        runner?.cancel()
        runner = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: Run loop

    private func wake() {
        guard runner == nil, !paused, !stopped else { return }
        stats.loopStarts += 1
        let first = quiet ? Duration.zero : elapsed() + Self.frameInterval
        lastDue = first
        let sleepUntil = sleepUntil
        // The task holds the actor only while a step runs, never while it
        // sleeps, so releasing the actor ends the loop. Every await is here,
        // none inside `step()`.
        runner = Task { [weak self] in
            var due = first
            while !Task.isCancelled {
                if due == .zero {
                    await Task.yield()
                } else {
                    do { try await sleepUntil(due) } catch { return }
                }
                guard let next = await self?.step() else { return }
                due = next
            }
        }
    }

    /// Runs one step. Returns nil when the run is over, `.zero` to go on at
    /// once (quiet), or the elapsed time at which the next step is due.
    private func step() -> Duration? {
        guard !stopped, !paused, !Task.isCancelled else { return nil }
        if quiet {
            let begin = elapsed()
            var warm = true
            var ticks = 0
            repeat {
                warm = simulation.tick()
                ticks += 1
            } while warm && ticks < Self.quietBatchTicks && elapsed() - begin < Self.quietBatchBudget
            stats.ticks += ticks
            if !warm { return finishRun() }
            return .zero
        }
        var warm = true
        for _ in 0 ..< Self.ticksPerFrame where warm {
            warm = simulation.tick()
            stats.ticks += 1
        }
        if !warm { return finishRun() }
        publish(settled: false)
        let now = elapsed()
        var due = lastDue + Self.frameInterval
        if due <= now { due = now + Self.frameInterval }
        lastDue = due
        return due
    }

    private func finishRun() -> Duration? {
        publish(settled: true)
        runner = nil
        return nil
    }

    private func publish(settled: Bool) {
        stats.yields += 1
        continuation?.yield(
            LayoutSnapshot(ids: ids, points: simulation.positions, settled: settled, generation: generation)
        )
    }
}
