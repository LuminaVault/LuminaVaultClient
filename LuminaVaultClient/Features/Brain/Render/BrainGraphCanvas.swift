// The 2D Brain graph: a SwiftUI `Canvas` fed by the `GraphLayout2D` actor.
// Behaves as the web 2D renderer: points filled by colour, hubs as rings, the
// selection ringed in the highlight colour, everything outside the lit set
// dimmed with its labels hidden, the view fitted automatically until the user
// pans or zooms.
//
// How it uses the layout: one `.task` holds one `updates()` stream for as long
// as the canvas is on screen and the app is in the foreground. Leaving
// (another tab, the background) cancels the task, which drops the stream and
// pauses the layout (the task also says `pause()` on its way out); coming back
// subscribes again, which resumes it. Commands (new graph,
// pins, Reduce Motion) go through one ordered stream drained inside the same
// task. Snapshots of an older `generation` than the last graph sent are
// dropped. The actor is owned here and released with the canvas; its own
// `deinit` ends the run loop, so nothing calls `stop()`.
//
// Redraws: the canvas draws when a snapshot, the view, the highlight or the
// theme changes. The `TimelineView` runs only while the view is easing to a
// fit or gliding after a fling; at rest it is paused and nothing is drawn.

import LuminaVaultShared
import SwiftUI

struct BrainGraphCanvas: View {
    let graph: VisibleBrainGraph
    let highlight: BrainHighlight
    let colourOf: (BrainGraphNodeDTO) -> Color
    /// A tap on a point; `additive` for a long press.
    let onTap: (_ id: String, _ additive: Bool) -> Void
    let onBackgroundTap: () -> Void
    /// A double tap on a point.
    let onOpen: (_ id: String) -> Void
    /// Tests and previews: draw this snapshot and never start a layout.
    var fixedSnapshot: LayoutSnapshot?
    /// Tests and previews: this view instead of the automatic fit.
    var fixedViewport: BrainGraphViewport?

    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        BrainGraphCanvasSurface(
            inputs: self,
            scene: BrainCanvasScene(graph: graph, colourOf: colourOf),
            theme: BrainGraphTheme(palette: palette, scheme: scheme)
        )
    }
}

/// Everything that lives across frames but must not redraw the canvas when it
/// changes: the layout actor, the command stream, the press in progress.
@MainActor
private final class BrainCanvasDriver {
    enum Command: Sendable {
        case graph(VisibleBrainGraph)
        case pin(String, CGPoint?)
        case quiet(Bool)
    }

    let layout = GraphLayout2D()
    let scratch = BrainCanvasScratch()
    /// Set while the layout task runs.
    var commands: AsyncStream<Command>.Continuation?
    /// The scene key last sent to the layout, and how many graphs were sent.
    var sentKey: Int?
    var sentGenerations = 0
    /// Every id ever laid out, so a graph made only of new ids counts as fresh.
    var known: Set<String> = []
    var current: Set<String> = []
    /// Frame on every snapshot (a fresh graph is laying itself out).
    var fitEachStep = false
    /// Frame once the layout settles (the set of points changed).
    var refitOnSettle = false

    var press: BrainPressTracker?
    var pressBegan = Date.distantPast
    var lastLocation = CGPoint.zero
    var pinchBase: BrainGraphViewport?
    var lastTap: (id: String, at: Date)?

    var isDraggingPoint: Bool { press?.phase == .draggingPoint }
}

private struct BrainGraphCanvasSurface: View {
    /// The canvas's own inputs: graph, highlight, callbacks, fixed snapshot.
    let inputs: BrainGraphCanvas
    let scene: BrainCanvasScene
    let theme: BrainGraphTheme

    private var graph: VisibleBrainGraph { inputs.graph }
    private var highlight: BrainHighlight { inputs.highlight }
    private var fixedSnapshot: LayoutSnapshot? { inputs.fixedSnapshot }

    @State private var driver = BrainCanvasDriver()
    @State private var snapshot: LayoutSnapshot?
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
        let positions = snapshot.map(scene.aligned) ?? []
        TimelineView(.animation(paused: motion == nil)) { timeline in
            Canvas { context, canvasSize in
                let frame = BrainCanvasFrame(
                    scene: scene,
                    positions: positions,
                    viewport: shownViewport(at: timeline.date, positions: positions, size: canvasSize),
                    highlight: highlight,
                    theme: theme,
                    typeSize: typeSize
                )
                BrainCanvasPainter.paint(&context, size: canvasSize, frame: frame, scratch: driver.scratch)
            }
        }
        .background(theme.background)
        .contentShape(Rectangle())
        .gesture(pressGesture(positions: positions))
        .simultaneousGesture(pinchGesture(positions: positions))
        .onGeometryChange(for: CGSize.self, of: \.size) { resized(to: $0, positions: positions) }
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
        .onChange(of: scene.layoutKey) { sendGraph() }
        .onChange(of: reduceMotion) { _, quiet in driver.commands?.yield(.quiet(quiet)) }
        .task(id: motion) { await finish(motion) }
        .task(id: pressCount) { await longPressTimer(pressCount) }
        .sensoryFeedback(.selection, trigger: longPresses)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BrainGraphCanvasLogic.accessibilityLabel(itemCount: scene.itemCount))
    }

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
        if animated, !reduceMotion, let from = viewport {
            motion = .ease(from: from, to: target, start: .now)
        } else {
            motion = nil
            viewport = target
        }
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

    private func runLayout() async {
        let layout = driver.layout
        await layout.setQuiet(reduceMotion)
        let updates = await layout.updates()
        let (commands, sink) = AsyncStream.makeStream(of: BrainCanvasDriver.Command.self)
        driver.commands = sink
        if driver.sentKey != scene.layoutKey { sendGraph() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await command in commands {
                    switch command {
                    case let .graph(graph): await layout.setGraph(graph)
                    case let .pin(id, point): await layout.pin(id, at: point)
                    case let .quiet(quiet): await layout.setQuiet(quiet)
                    }
                }
            }
            for await next in updates {
                received(next)
            }
            group.cancelAll()
        }
        sink.finish()
        driver.commands = nil
        // Dropping the stream pauses the layout already; say so plainly too.
        await layout.pause()
    }

    /// Sends the current graph to the layout, noting whether it is fresh (frame
    /// it on every step) or changes which points are shown (frame it once it
    /// settles, while the view is still automatic).
    private func sendGraph() {
        guard let commands = driver.commands, driver.sentKey != scene.layoutKey else { return }
        let ids = Set(scene.ids)
        if BrainGraphCanvasLogic.isFreshGraph(scene.ids, known: driver.known) {
            driver.known = []
            driver.fitEachStep = true
            if let current = viewport {
                var next = current
                next.isAutomatic = BrainGraphCanvasLogic.nextAutoView(current.isAutomatic, .freshGraph)
                viewport = next
            }
        } else if ids != driver.current, isAutomatic {
            driver.refitOnSettle = true
        }
        driver.known.formUnion(ids)
        driver.current = ids
        driver.sentKey = scene.layoutKey
        driver.sentGenerations += 1
        commands.yield(.graph(graph))
    }

    private func received(_ next: LayoutSnapshot) {
        // The actor counts `setGraph` calls from 1; anything older is stale.
        guard next.generation >= driver.sentGenerations else { return }
        snapshot = next
        let dragging = driver.isDraggingPoint
        if driver.fitEachStep, isAutomatic, !dragging, !next.settled { fit(animated: false) }
        if next.settled {
            if driver.fitEachStep || driver.refitOnSettle, isAutomatic, !dragging {
                // Framed every step already: finish exactly. A reheat moved
                // points under a still view: glide to the new fit.
                fit(animated: !driver.fitEachStep)
            }
            driver.fitEachStep = false
            driver.refitOnSettle = false
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
                    driver.commands?.yield(.pin(id, world))
                case .pending, .longPressed, .pinching:
                    break
                }
            }
            .onEnded { value in
                guard let press = driver.press else { return }
                driver.press = nil
                switch press.phase {
                case .draggingPoint:
                    if let id = press.hitID { driver.commands?.yield(.pin(id, nil)) }
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
                        driver.commands?.yield(.pin(id, nil))
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
