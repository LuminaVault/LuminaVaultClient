// The 2D Brain graph: a SwiftUI `Canvas` fed by the `GraphLayout2D` actor.
// Behaves as the web 2D renderer: points filled by colour, hubs as rings, the
// selection ringed in the highlight colour, everything outside the lit set
// dimmed with its labels hidden, the view fitted automatically until the user
// pans or zooms.
//
// How it uses the layout: one `.task` (a "run") holds one `updates()` stream
// for as long as the canvas is on screen and the app is in the foreground.
// Leaving (another tab, the background) cancels the run, which drops the
// stream and so pauses the layout; coming back starts a new run, whose
// subscription resumes it. Runs never overlap: a new one waits for the old
// one's teardown. Commands (graph, pins, Reduce Motion) go through one ordered
// channel per run, drained inside the run. `BrainCanvasSync` holds the rules:
// run tokens, the graph resent on every run, a lost pin release redone, the
// generation filter and when to frame the graph. The actor is owned here and
// released with the canvas; its own `deinit` ends the run loop, so nothing
// calls `stop()`.
//
// Redraws: the canvas draws when a snapshot, the view, the highlight or the
// theme changes. The `TimelineView` runs only while the view is easing to a
// fit or gliding after a fling; at rest it is paused and nothing is drawn.

import LuminaVaultShared
import os
import SwiftUI

/// One interval per canvas draw (`draw`), for Instruments and the
/// performance measurements: at rest there are none.
nonisolated private let canvasSignposter = OSSignposter(subsystem: "com.luminavault", category: "brain.canvas")

struct BrainGraphCanvas: View {
    let graph: VisibleBrainGraph
    let highlight: BrainHighlight
    let colourOf: (BrainGraphNodeDTO) -> Color
    /// A tap on a point; `additive` for a long press.
    let onTap: (_ id: String, _ additive: Bool) -> Void
    let onBackgroundTap: () -> Void
    /// A double tap on a point.
    let onOpen: (_ id: String) -> Void
    /// Put this point in the middle, at the current zoom (search's one
    /// explicit camera move). A new token is a new request.
    var centreOn: BrainCentreRequest?
    /// What covers the bottom of the canvas (the selection tray, overlaid so
    /// the canvas never resizes when it comes and goes). Used only to centre
    /// a searched point in the part above it; the automatic fit ignores it.
    var bottomInset: CGFloat = 0
    /// The scene built by the screen when its inputs change (graph, colours,
    /// theme). Nil (tests, previews): built here from `graph` and `colourOf`.
    var scene: BrainCanvasScene?
    /// Tests and previews: draw this snapshot and never start a layout.
    var fixedSnapshot: LayoutSnapshot?
    /// Tests and previews: this view instead of the automatic fit.
    var fixedViewport: BrainGraphViewport?

    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        BrainGraphCanvasSurface(
            inputs: self,
            scene: scene ?? BrainCanvasScene(graph: graph, colourOf: colourOf),
            theme: BrainGraphTheme(palette: palette, scheme: scheme)
        )
    }
}

/// Everything that lives across frames but must not redraw the canvas when it
/// changes: the layout actor, the run's command channel, the sync rules, the
/// last snapshot, the press in progress.
@MainActor
private final class BrainCanvasDriver {
    enum Command: Sendable {
        case graph(VisibleBrainGraph)
        case pin(String, CGPoint)
        case release(String, seq: Int)
        case quiet(Bool)
    }

    let layout = GraphLayout2D()
    let scratch = BrainCanvasScratch()
    var sync = BrainCanvasSync()
    /// The live run's channel.
    var commands: AsyncStream<Command>.Continuation?
    /// The current graph and Reduce Motion, kept here by `onChange` so a run
    /// reads them when it starts and never from the copy of the view its
    /// task captured.
    var latestGraph: VisibleBrainGraph?
    var reduceMotion = false
    /// The snapshot's points in the current scene's order.
    var positionCache = BrainPositionCache()

    var press: BrainPressTracker?
    var pressBegan = Date.distantPast
    var lastLocation = CGPoint.zero
    var pinchBase: BrainGraphViewport?
    var lastTap: (id: String, at: Date)?
    /// A centre request whose point had no position yet; tried again on the
    /// next snapshot.
    var pendingCentre: BrainCentreRequest?

    var isDraggingPoint: Bool { press?.phase == .draggingPoint }

    private var running = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Waits until no other run is live, then marks this one live.
    func beginRun() async {
        while running {
            await withCheckedContinuation { waiting.append($0) }
        }
        running = true
    }

    func endRun() {
        running = false
        let next = waiting
        waiting = []
        for waiter in next { waiter.resume() }
    }

    func send(_ command: Command) {
        if case let .pin(id, _) = command { sync.pinned(id) }
        commands?.yield(command)
    }

    /// Lets go of a point the user held.
    func release(_ id: String) {
        guard let seq = sync.releaseSeq(id) else { return }
        commands?.yield(.release(id, seq: seq))
    }

    func releaseDelivered(_ id: String, seq: Int) {
        sync.releaseDelivered(id, seq: seq)
    }
}

/// Holds the canvas's driver, made on first use.
@MainActor
private final class BrainCanvasDriverBox {
    private(set) lazy var driver = BrainCanvasDriver()
}

private struct BrainGraphCanvasSurface: View {
    /// The canvas's own inputs: graph, highlight, callbacks, fixed snapshot.
    let inputs: BrainGraphCanvas
    let scene: BrainCanvasScene
    let theme: BrainGraphTheme

    private var graph: VisibleBrainGraph { inputs.graph }
    private var highlight: BrainHighlight { inputs.highlight }
    private var fixedSnapshot: LayoutSnapshot? { inputs.fixedSnapshot }

    /// The box is all a re-render of the parent allocates; the driver, its
    /// layout actor and scratch are made once, on first use, for the life of
    /// this view. (Not `onAppear`, as the Constellation does: `ImageRenderer`
    /// never calls it, and the snapshot tests draw through it.)
    @State private var drivers = BrainCanvasDriverBox()
    private var driver: BrainCanvasDriver { drivers.driver }
    /// The newest accepted snapshot, and a count of them, so positions are
    /// aligned once per (snapshot, scene) pair rather than per body evaluation.
    @State private var snapshot: LayoutSnapshot?
    @State private var snapshotSerial = 0
    /// nil until there is a size to fit to: drawn as the automatic fit.
    @State private var viewport: BrainGraphViewport?
    @State private var motion: BrainViewportMotion?
    @State private var size: CGSize = .zero
    /// Bumps on every touch-down, restarting the long-press timer.
    @State private var pressCount = 0
    @State private var longPresses = 0
    /// The app notifications rather than `scenePhase`: a hosting controller
    /// outside a SwiftUI scene reports `.background` for good.
    @State private var inForeground = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Double taps within this long open the point (web `DOUBLE_CLICK_MS`).
    private static let doubleTapSeconds: TimeInterval = 0.4
    /// A press held longer than this is not a tap (web `CLICK_MS`).
    private static let tapSeconds: TimeInterval = 0.5

    init(inputs: BrainGraphCanvas, scene: BrainCanvasScene, theme: BrainGraphTheme) {
        self.inputs = inputs
        self.scene = scene
        self.theme = theme
        _snapshot = State(initialValue: inputs.fixedSnapshot)
        _viewport = State(initialValue: inputs.fixedViewport)
    }

    var body: some View {
        // Here, where the current scene is known; never in the layout task.
        let points = driver.positionCache.positions(snapshot: snapshot, serial: snapshotSerial, scene: scene)
        TimelineView(.animation(paused: motion == nil)) { timeline in
            Canvas { context, canvasSize in
                let frame = BrainCanvasFrame(
                    scene: scene,
                    positions: points,
                    viewport: shownViewport(at: timeline.date, positions: points, size: canvasSize),
                    highlight: highlight,
                    theme: theme,
                    typeSize: typeSize
                )
                let draw = canvasSignposter.beginInterval("draw")
                BrainCanvasPainter.paint(&context, size: canvasSize, frame: frame, scratch: driver.scratch)
                canvasSignposter.endInterval("draw", draw)
            }
        }
        .background(theme.background)
        .contentShape(Rectangle())
        .gesture(pressGesture(positions: points))
        .simultaneousGesture(pinchGesture(positions: points))
        .onGeometryChange(for: CGSize.self, of: \.size) { resized(to: $0, positions: points) }
        .task(id: fixedSnapshot == nil && inForeground) {
            guard fixedSnapshot == nil, inForeground else { return }
            await runLayout()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            inForeground = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            inForeground = true
        }
        .onChange(of: scene.layoutKey, initial: true) {
            driver.latestGraph = graph
            if driver.sync.graphChanged(key: scene.layoutKey) { driver.send(.graph(graph)) }
        }
        .onChange(of: reduceMotion, initial: true) { _, quiet in
            driver.reduceMotion = quiet
            driver.send(.quiet(quiet))
        }
        .onChange(of: inputs.centreOn) { _, request in centre(on: request, positions: points) }
        .onChange(of: snapshotSerial) {
            if let pending = driver.pendingCentre { centre(on: pending, positions: points) }
        }
        .task(id: motion) { await finish(motion) }
        .task(id: pressCount) { await longPressTimer(pressCount) }
        .sensoryFeedback(.selection, trigger: longPresses)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BrainGraphCanvasLogic.accessibilityLabel(itemCount: scene.itemCount))
        // VoiceOver's double tap would otherwise arrive as a tap at the
        // element's centre and clear or change the selection; selection is
        // made from the list there.
        .accessibilityAction {}
        #if DEBUG
        .preference(key: BrainUITestProbeKey.self, value: probe(positions: points))
        #endif
    }

    #if DEBUG
    /// Where the UI tests' probe point is on screen, when one was asked for.
    private func probe(positions: [CGPoint]) -> CGPoint? {
        guard let id = BrainUITestProbeKey.probedID, size != .zero, positions.count == scene.ids.count,
              let i = scene.ids.firstIndex(of: id), positions[i].x.isFinite else { return nil }
        return currentViewport(positions: positions).screen(positions[i])
    }
    #endif

    // MARK: View

    private func shownViewport(at date: Date, positions: [CGPoint], size: CGSize) -> BrainGraphViewport {
        if let motion { return motion.viewport(at: date) }
        return viewport ?? BrainGraphCanvasLogic.fittedView(points: positions, size: size)
    }

    /// The view now, a running motion included.
    private func currentViewport(positions: [CGPoint]) -> BrainGraphViewport {
        shownViewport(at: .now, positions: positions, size: size)
    }

    /// Stops any motion where it is: the user has taken hold of the view.
    private func takeHold(positions: [CGPoint]) {
        guard motion != nil else { return }
        viewport = currentViewport(positions: positions)
        motion = nil
    }

    private var isAutomatic: Bool { viewport?.isAutomatic ?? true }

    private func fit(animated: Bool) {
        guard size != .zero, let snapshot, !snapshot.points.isEmpty else { return }
        let target = BrainGraphCanvasLogic.fittedView(points: snapshot.points, size: size)
        if animated, !driver.reduceMotion, let from = viewport {
            motion = .ease(from: from, to: target, start: .now)
        } else {
            motion = nil
            viewport = target
        }
    }

    /// Search's centring. Leaves the zoom alone and ends the automatic fit, so
    /// the next snapshot does not frame the graph back over it.
    private func centre(on request: BrainCentreRequest?, positions: [CGPoint]) {
        guard let request else { return }
        // Not in this graph at all: nothing to wait for.
        guard scene.ids.contains(request.id) else {
            driver.pendingCentre = nil
            return
        }
        let current = currentViewport(positions: positions)
        guard let target = BrainCentreRequest.view(
            centring: request.id, ids: scene.ids, positions: positions, current: current, size: size,
            bottomInset: inputs.bottomInset
        ) else {
            driver.pendingCentre = request
            return
        }
        driver.pendingCentre = nil
        viewport = target
        motion = driver.reduceMotion ? nil : .ease(from: current, to: target, start: .now)
    }

    private func resized(to new: CGSize, positions: [CGPoint]) {
        let old = size
        size = new
        guard old != .zero, old != new, let current = viewport else { return }
        motion = nil
        let action = BrainGraphCanvasLogic.resizeAction(
            autoView: current.isAutomatic && !positions.isEmpty, dragging: driver.isDraggingPoint
        )
        switch action {
        case .refit: fit(animated: false)
        case .recentre: viewport = current.recentred(from: old, to: new)
        }
    }

    private func finish(_ running: BrainViewportMotion?) async {
        guard let running else { return }
        let left = running.duration - Date.now.timeIntervalSince(running.start)
        if left > 0 {
            do { try await Task.sleep(for: .seconds(left)) } catch { return }
        }
        guard motion == running else { return }
        viewport = running.end
        motion = nil
    }

    // MARK: Layout

    /// One run. Everything it reads from the view after the gate is `@State`
    /// or the driver, never the inputs of the view copy this task captured.
    private func runLayout() async {
        await driver.beginRun()
        defer { driver.endRun() }
        guard !Task.isCancelled else { return }
        let driver = driver
        let layout = driver.layout
        await layout.setQuiet(driver.reduceMotion)
        let updates = await layout.updates()
        let (commands, sink) = AsyncStream.makeStream(of: BrainCanvasDriver.Command.self)
        let start = driver.sync.startRun()
        driver.commands = sink
        for send in start.sends {
            switch send {
            case let .release(id, seq): sink.yield(.release(id, seq: seq))
            case .graph: if let graph = driver.latestGraph { sink.yield(.graph(graph)) }
            }
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await command in commands {
                    switch command {
                    case let .graph(graph):
                        await layout.setGraph(graph)
                    case let .pin(id, point):
                        await layout.pin(id, at: point)
                    case let .release(id, seq):
                        await layout.pin(id, at: nil)
                        await driver.releaseDelivered(id, seq: seq)
                    case let .quiet(quiet):
                        await layout.setQuiet(quiet)
                    }
                }
            }
            for await next in updates {
                received(next)
            }
            group.cancelAll()
        }
        sink.finish()
        // Only the live run's channel; dropping `updates` already paused the
        // layout, and a late `pause()` here could pause a newer subscriber.
        if driver.sync.endRun(start.token) { driver.commands = nil }
    }

    private func received(_ next: LayoutSnapshot) {
        let facts = BrainCanvasSync.ViewFacts(
            automatic: isAutomatic, dragging: driver.isDraggingPoint, reduceMotion: driver.reduceMotion
        )
        let outcome = driver.sync.receive(next, view: facts)
        guard outcome.accept else { return }
        // Raw: aligned in `body`, against whatever the scene is by then.
        snapshot = next
        snapshotSerial += 1
        if outcome.resetAutomatic, var current = viewport {
            current.isAutomatic = true
            viewport = current
        }
        switch outcome.fit {
        case .now: fit(animated: false)
        case .eased: fit(animated: true)
        case .none: break
        }
        if viewport == nil, size != .zero, !next.points.isEmpty { fit(animated: false) }
    }

    // MARK: Gestures

    private func hit(at location: CGPoint, positions: [CGPoint]) -> String? {
        let v = currentViewport(positions: positions)
        guard positions.count == scene.ids.count else { return nil }
        return BrainGraphCanvasLogic.hitTest(
            points: positions, radii: scene.radius, at: v.world(location), scale: v.scale
        ).map { scene.ids[$0] }
    }

    private func pressGesture(positions: [CGPoint]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                // A drag cancelled without `onEnded` left its press behind.
                if case let .restart(release) = BrainPressTracker.recovery(
                    current: driver.press, gestureStart: value.startLocation
                ) {
                    if let release { driver.release(release) }
                    driver.press = nil
                    driver.pinchBase = nil
                }
                guard var press = driver.press else {
                    takeHold(positions: positions)
                    driver.press = BrainPressTracker(start: value.startLocation, hitID: hit(at: value.startLocation, positions: positions))
                    driver.pressBegan = .now
                    driver.lastLocation = value.startLocation
                    pressCount += 1
                    return
                }
                let before = press.phase
                let phase = press.move(to: value.location)
                driver.press = press
                defer { driver.lastLocation = value.location }
                switch phase {
                case .panning:
                    let from = before == .panning ? driver.lastLocation : value.startLocation
                    var next = currentViewport(positions: positions)
                        .panned(by: CGSize(width: value.location.x - from.x, height: value.location.y - from.y))
                    next.isAutomatic = BrainGraphCanvasLogic.nextAutoView(next.isAutomatic, .userPan)
                    viewport = next
                case .draggingPoint:
                    guard let id = press.hitID else { return }
                    if before != .draggingPoint {
                        // The view itself does not move: still automatic, but
                        // no refit may move the camera under the finger.
                        takeHold(positions: positions)
                        if viewport == nil { viewport = currentViewport(positions: positions) }
                    }
                    let world = currentViewport(positions: positions).world(value.location)
                    driver.send(.pin(id, world))
                case .pending, .longPressed, .pinching:
                    break
                }
            }
            .onEnded { value in
                guard let press = driver.press else { return }
                driver.press = nil
                switch press.phase {
                case .draggingPoint:
                    if let id = press.hitID { driver.release(id) }
                case .panning:
                    let from = currentViewport(positions: positions)
                    let v = CGSize(width: value.velocity.width, height: value.velocity.height)
                    if let glide = BrainViewportMotion.fling(from: from, velocity: v, start: .now) {
                        viewport = from
                        motion = glide
                    }
                case .pending:
                    guard Date.now.timeIntervalSince(driver.pressBegan) <= Self.tapSeconds else { return }
                    tapped(press.hitID)
                case .longPressed, .pinching:
                    break
                }
            }
    }

    private func tapped(_ id: String?) {
        let now = Date.now
        guard let id else {
            driver.lastTap = nil
            inputs.onBackgroundTap()
            return
        }
        if let last = driver.lastTap, last.id == id, now.timeIntervalSince(last.at) <= Self.doubleTapSeconds {
            driver.lastTap = nil
            inputs.onOpen(id)
            return
        }
        driver.lastTap = (id, now)
        inputs.onTap(id, false)
    }

    private func longPressTimer(_ count: Int) async {
        guard count > 0, driver.press != nil else { return }
        do { try await Task.sleep(for: .seconds(BrainPressTracker.longPressSeconds)) } catch { return }
        guard count == pressCount, var press = driver.press, press.longPressElapsed(), let id = press.hitID else { return }
        driver.press = press
        driver.lastTap = nil
        longPresses += 1
        inputs.onTap(id, true)
    }

    private func pinchGesture(positions: [CGPoint]) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                if driver.pinchBase == nil {
                    takeHold(positions: positions)
                    driver.pinchBase = currentViewport(positions: positions)
                    if driver.isDraggingPoint, let id = driver.press?.hitID {
                        // A second finger: a pinch, not a drag.
                        driver.release(id)
                    }
                    driver.press?.pinchBegan()
                }
                guard let base = driver.pinchBase else { return }
                var next = base.zoomed(by: value.magnification, around: value.startLocation)
                next.isAutomatic = BrainGraphCanvasLogic.nextAutoView(base.isAutomatic, .userZoom)
                viewport = next
            }
            .onEnded { _ in
                driver.pinchBase = nil
            }
    }
}

#if DEBUG
#Preview("25 points, light") {
    BrainGraphCanvasFixtureHost(fixture: .small)
        .environment(\.lvPalette, LVTheme.cyanGold.palette(for: .light))
        .preferredColorScheme(.light)
}

#Preview("25 points, dark, selected") {
    BrainGraphCanvasFixtureHost(fixture: .small, selected: [BrainGraphCanvasFixture.small.heaviestItem])
        .environment(\.lvPalette, LVTheme.cyanGold.palette(for: .dark))
        .preferredColorScheme(.dark)
}

#Preview("600 points, light") {
    BrainGraphCanvasFixtureHost(fixture: .large)
        .environment(\.lvPalette, LVTheme.cyanGold.palette(for: .light))
        .preferredColorScheme(.light)
}

#Preview("600 points, dark") {
    BrainGraphCanvasFixtureHost(fixture: .large)
        .environment(\.lvPalette, LVTheme.cyanGold.palette(for: .dark))
        .preferredColorScheme(.dark)
}
#endif
