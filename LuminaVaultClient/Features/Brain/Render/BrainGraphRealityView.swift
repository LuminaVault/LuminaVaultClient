// The 3D Constellation: the same inputs and callbacks as the 2D canvas, drawn
// as a RealityKit sky. This file wires the scene to SwiftUI and nothing more:
// `ConstellationScene` owns the entities, `ConstellationCamera` the camera,
// `ConstellationRules` every decision, `ConstellationLayoutRunner` the layout.
//
// Lifetime: the scene is made in RealityView's `make` closure, once, when the
// user picks the Constellation; every later change (graph, colours,
// highlight, theme) is applied in `update`, so the camera and the entities
// survive them. Leaving the view (2D, another tab) releases it all.
//
// What runs: the layout, off the main actor, when the visible graph changes
// (its task is cancelled when the view goes away, and only a run the view
// accepts is remembered); a centre ease of 0.4 s after search; the idle turn.
// Nothing else: at rest no SwiftUI state changes. The idle turn runs only
// while the view is on screen, the app is in the foreground, no sheet covers
// it, nothing is selected, Reduce Motion is off and no finger is down, 5 s
// after the last touch; every step asks `ConstellationIdleTurn.allowed`, at
// most 30 a second, for at most 90 s. Labels (at most 24) are a SwiftUI
// overlay with its own observable store, placed when the camera stops and
// carried along by the turn. The driver (scene, runner, labels) is made once
// per appearance of the view, not on every re-render of its parent.

import LuminaVaultShared
import RealityKit
import SwiftUI
import UIKit

struct BrainGraphRealityView: View {
    let graph: VisibleBrainGraph
    let highlight: BrainHighlight
    let colourOf: (BrainGraphNodeDTO) -> Color
    /// A tap on a star; `additive` for a long press.
    let onTap: (_ id: String, _ additive: Bool) -> Void
    let onBackgroundTap: () -> Void
    /// A double tap on a star.
    let onOpen: (_ id: String) -> Void
    /// Put this star in the middle (search's one explicit camera move).
    var centreOn: BrainCentreRequest?
    /// A sheet covers the screen (list, filters, detail, reasoning, capture):
    /// the idle turn stops.
    var covered = false
    /// What covers the bottom of the sky (the selection tray, overlaid so the
    /// view never resizes when it comes and goes). Used only to centre a
    /// searched star in the part above it.
    var bottomInset: CGFloat = 0
    /// The model built by the screen when its inputs change (graph, colours,
    /// theme). Nil (tests, previews): built here from `graph` and `colourOf`.
    var model: ConstellationModel?

    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    /// Made once, when the view first appears, and kept for its lifetime: a
    /// default value here would build (and throw away) a scene on every
    /// re-render of the parent.
    @State private var driver: ConstellationDriver?

    var body: some View {
        let theme = BrainGraphTheme(palette: palette, scheme: scheme)
        Group {
            if let driver {
                ConstellationSurface(
                    inputs: self,
                    driver: driver,
                    model: model ?? ConstellationModel(graph: graph, colourOf: colourOf),
                    theme: theme,
                    dark: scheme == .dark
                )
            } else {
                theme.background
            }
        }
        .onAppear {
            if driver == nil { driver = ConstellationDriver() }
        }
    }
}

/// Everything that lives across frames but must not update the view when it
/// changes: the scene, the layout runner, the press in progress, the camera a
/// gesture started from, measured label sizes.
@MainActor
private final class ConstellationDriver {
    let scene = ConstellationScene()
    let runner = ConstellationLayoutRunner()
    let labels = ConstellationLabelStore()
    /// The memory the sky on screen was laid out from.
    var layoutState = ConstellationLayoutState()
    /// What the idle turn checks on every step: kept current by the view.
    var idleInputs = ConstellationIdleInputs()
    var press: BrainPressTracker?
    var pressBegan = Date.distantPast
    /// The camera and finger position an orbit started from.
    var orbit: (camera: ConstellationCamera, at: CGPoint)?
    var pinchBase: ConstellationCamera?
    var lastTap: (id: String, at: Date)?
    var lastActivity = ContinuousClock.now
    /// A centre request whose star had no position yet; tried again when the layout lands.
    var pendingCentre: BrainCentreRequest?
    private var textSizes: [String: CGSize] = [:]
    private var measuredFor: DynamicTypeSize?

    var pressing: Bool { press != nil || pinchBase != nil }

    func textSize(_ text: String, typeSize: DynamicTypeSize) -> CGSize {
        if measuredFor != typeSize {
            measuredFor = typeSize
            textSizes.removeAll()
        }
        if let known = textSizes[text] { return known }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let font = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        let raw = (text as NSString).size(withAttributes: [.font: font])
        let size = CGSize(width: raw.width.rounded(.up), height: raw.height.rounded(.up))
        textSizes[text] = size
        return size
    }
}

/// The idle turn's inputs that change while it runs.
private struct ConstellationIdleInputs: Equatable {
    var selected = 0
    var foreground = true
    var covered = false
    var reduceMotion = false
}

/// The labels on screen. Observed only by the overlay, so moving them with
/// the idle turn redraws the labels and nothing else.
@MainActor @Observable
private final class ConstellationLabelStore {
    private(set) var labels: [ConstellationLabel] = []
    #if DEBUG
    /// The UI tests' probe star on screen, placed and carried with the labels.
    private(set) var probe: CGPoint?
    @ObservationIgnored var probeStar: Int?

    private func placeProbe(_ p: ConstellationProjection) {
        guard let i = probeStar, i < p.count, p.x[i].isFinite, p.y[i].isFinite else {
            probe = nil
            return
        }
        probe = CGPoint(x: p.x[i], y: p.y[i])
    }
    #endif
    /// Each label's plate origin relative to its star, for following.
    @ObservationIgnored private var offsets: [CGPoint] = []

    func show(_ next: [ConstellationLabel], projection p: ConstellationProjection) {
        offsets = next.map { CGPoint(x: $0.rect.minX - p.x[$0.star], y: $0.rect.minY - p.y[$0.star]) }
        labels = next
        #if DEBUG
        placeProbe(p)
        #endif
    }

    func hide() {
        guard !labels.isEmpty else { return }
        labels = []
        offsets = []
    }

    /// The same labels, moved with their stars.
    func follow(_ p: ConstellationProjection) {
        #if DEBUG
        placeProbe(p)
        #endif
        guard !labels.isEmpty else { return }
        var next: [ConstellationLabel] = []
        var nextOffsets: [CGPoint] = []
        for (label, offset) in zip(labels, offsets) where label.star < p.count {
            let x = p.x[label.star], y = p.y[label.star]
            guard x.isFinite, y.isFinite else { continue }
            var moved = label
            moved.rect.origin = CGPoint(x: x + offset.x, y: y + offset.y)
            next.append(moved)
            nextOffsets.append(offset)
        }
        labels = next
        offsets = nextOffsets
    }
}

/// An eased move of the camera to a searched star.
private struct ConstellationCentring: Equatable {
    var from: ConstellationCamera
    var to: ConstellationCamera
    var start: Date
}

private struct ConstellationSurface: View {
    let inputs: BrainGraphRealityView
    let driver: ConstellationDriver
    let model: ConstellationModel
    let theme: BrainGraphTheme
    let dark: Bool

    private var labelStore: ConstellationLabelStore { driver.labels }
    @State private var placement: ConstellationPlacement?
    @State private var centring: ConstellationCentring?
    /// Bumps on every touch, restarting the idle timer.
    @State private var activity = 0
    /// Bumps on every touch-down, restarting the long-press timer.
    @State private var pressCount = 0
    @State private var longPresses = 0
    /// The app notifications rather than `scenePhase`, as the 2D canvas.
    @State private var inForeground = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Double taps within this long open the star (web `DOUBLE_CLICK_MS`).
    private static let doubleTapSeconds: TimeInterval = 0.4
    /// A press held longer than this is not a tap (web `CLICK_MS`).
    private static let tapSeconds: TimeInterval = 0.5
    /// A centre ease steps about once a display frame.
    private static let centreStep: Duration = .milliseconds(16)

    private struct IdleKey: Equatable {
        var activity: Int
        var inputs: ConstellationIdleInputs
        var placed: Bool
    }

    private var idleInputs: ConstellationIdleInputs {
        ConstellationIdleInputs(
            selected: inputs.highlight.selected.count, foreground: inForeground,
            covered: inputs.covered, reduceMotion: reduceMotion
        )
    }

    private struct LabelKey: Equatable {
        var model: Int
        var serial: Int?
        var highlight: BrainHighlight
        var typeSize: DynamicTypeSize
    }

    var body: some View {
        let scene = driver.scene
        RealityView { content in
            scene.install(into: &content)
        } update: { _ in
            applyScene()
        }
        .overlay { ConstellationLabelsOverlay(store: labelStore, theme: theme) }
        .background(theme.background)
        .contentShape(Rectangle())
        .gesture(pressGesture)
        .simultaneousGesture(pinchGesture)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            applyScene()
            _ = driver.scene.resize(size)
            rerank()
        }
        .task(id: model.layoutKey) { await layout() }
        .onChange(of: idleInputs, initial: true) { _, now in driver.idleInputs = now }
        .task(id: IdleKey(activity: activity, inputs: idleInputs, placed: placement != nil)) { await idleTurn() }
        .task(id: centring) { await runCentring(centring) }
        .task(id: pressCount) { await longPressTimer(pressCount) }
        .onChange(of: LabelKey(model: model.key, serial: placement?.serial, highlight: inputs.highlight, typeSize: typeSize)) {
            rerank()
        }
        .onChange(of: placement?.serial) {
            if let pending = driver.pendingCentre { centre(on: pending) }
        }
        .onChange(of: inputs.centreOn) { _, request in centre(on: request) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            inForeground = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            inForeground = true
        }
        .sensoryFeedback(.selection, trigger: longPresses)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ConstellationRules.accessibilityLabel(itemCount: model.itemCount))
        // VoiceOver's double tap would otherwise arrive as a tap at the
        // element's centre and clear or change the selection; selection is
        // made from the list there.
        .accessibilityAction {}
    }

    // MARK: Scene

    /// The scene brought up to date with the inputs. Idempotent: `update`
    /// calls it on every view update, and anything that reads the scene calls
    /// it first so it never reads a stale one.
    private func applyScene() {
        driver.scene.apply(
            model: model, placement: placement, highlight: inputs.highlight, theme: theme, dark: dark
        )
    }

    /// Lays the graph out off the main actor, from the memory the sky on
    /// screen came from; the new memory is kept only if this task is still
    /// wanted when the run comes back.
    private func layout() async {
        guard let run = await driver.runner.layout(inputs.graph, from: driver.layoutState.memory) else { return }
        guard let next = driver.layoutState.accept(run, cancelled: Task.isCancelled) else { return }
        placement = next
    }

    /// Chooses and places the labels for where the camera is now. Not while
    /// a finger or an ease is moving the camera: they come back when it stops.
    private func rerank() {
        applyScene()
        guard driver.orbit == nil, driver.pinchBase == nil, centring == nil else { return }
        let scene = driver.scene
        let p = scene.projection()
        let labels = ConstellationRules.placeLabels(
            p, tiers: scene.look.tiers, weights: scene.model.labelWeight, texts: scene.model.text
        ) { driver.textSize($0, typeSize: typeSize) }
        #if DEBUG
        labelStore.probeStar = BrainUITestProbeKey.probedID.flatMap { scene.model.index[$0] }
        #endif
        labelStore.show(labels, projection: p)
    }

    private func noteActivity() {
        driver.lastActivity = .now
        activity += 1
    }

    // MARK: Camera moves

    /// Search's centring: the star in the middle, from the same direction.
    private func centre(on request: BrainCentreRequest?) {
        guard let request else { return }
        applyScene()
        guard model.index[request.id] != nil else {
            driver.pendingCentre = nil
            return
        }
        guard let point = driver.scene.position(of: request.id) else {
            driver.pendingCentre = request
            return
        }
        driver.pendingCentre = nil
        let from = driver.scene.camera
        let to = from.centred(on: point, bottomInset: inputs.bottomInset, size: driver.scene.size)
        if reduceMotion {
            centring = nil
            driver.scene.setCamera(to)
            rerank()
        } else {
            labelStore.hide()
            centring = ConstellationCentring(from: from, to: to, start: .now)
        }
    }

    private func runCentring(_ running: ConstellationCentring?) async {
        guard let running else { return }
        while true {
            let t = Date.now.timeIntervalSince(running.start) / ConstellationRules.centreSeconds
            if t >= 1 { break }
            driver.scene.setCamera(running.from.interpolated(to: running.to, fraction: ConstellationRules.easeInOutCubic(t)))
            do { try await Task.sleep(for: Self.centreStep) } catch { return }
        }
        guard centring == running else { return }
        driver.scene.setCamera(running.to)
        centring = nil
        rerank()
    }

    /// Stops an ease where it is: the user has taken hold of the camera.
    private func takeHold() {
        if centring != nil { centring = nil }
    }

    /// The idle turn. Every step asks `ConstellationIdleTurn.allowed` with
    /// the current inputs (the driver's copy, kept current by the view), so a
    /// selection, a sheet, Reduce Motion, a finger or the 90 s cap stops it at
    /// the next step whatever the task id does.
    private func idleTurn() async {
        do { try await Task.sleep(for: ConstellationIdleTurn.idleDelay) } catch { return }
        let driver = driver
        func allowed(turned: Duration) -> Bool {
            let now = driver.idleInputs
            return ConstellationIdleTurn.allowed(.init(
                selected: now.selected,
                idle: ContinuousClock.now - driver.lastActivity,
                visible: now.foreground,
                covered: now.covered,
                reduceMotion: now.reduceMotion,
                pressing: driver.pressing,
                turned: turned
            ))
        }
        guard placement != nil, allowed(turned: .zero) else { return }
        var last = ContinuousClock.now
        var turned = Duration.zero
        var sinceRank = Duration.zero
        while true {
            do { try await Task.sleep(for: ConstellationIdleTurn.stepInterval) } catch { return }
            let now = ContinuousClock.now
            let step = now - last
            last = now
            guard centring == nil, allowed(turned: turned) else { return }
            turned += step
            sinceRank += step
            // One projection per step: the scene draws with it and the labels follow it.
            let p = driver.scene.setCamera(driver.scene.camera.turned(by: ConstellationIdleTurn.angle(after: step)))
            if sinceRank >= ConstellationIdleTurn.rerankInterval {
                sinceRank = .zero
                rerank()
            } else {
                labelStore.follow(p)
            }
        }
    }

    // MARK: Gestures

    private func hit(at location: CGPoint) -> String? {
        applyScene()
        let scene = driver.scene
        return ConstellationRules.pickStar(scene.projection(), at: location).map { scene.model.ids[$0] }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                // A drag cancelled without `onEnded` left its press (and with
                // it `pressing`, which holds the idle turn) behind.
                if case .restart = BrainPressTracker.recovery(
                    current: driver.press, gestureStart: value.startLocation
                ) {
                    driver.press = nil
                    driver.pinchBase = nil
                    driver.orbit = nil
                }
                guard var press = driver.press else {
                    takeHold()
                    driver.press = BrainPressTracker(start: value.startLocation, hitID: hit(at: value.startLocation))
                    driver.pressBegan = .now
                    pressCount += 1
                    noteActivity()
                    return
                }
                switch press.move(to: value.location) {
                case .panning, .draggingPoint:
                    // A drag orbits, whether it started on a star or not.
                    if driver.orbit == nil {
                        driver.orbit = (driver.scene.camera, value.location)
                        labelStore.hide()
                    }
                    if let orbit = driver.orbit {
                        let moved = CGSize(width: value.location.x - orbit.at.x, height: value.location.y - orbit.at.y)
                        driver.scene.setCamera(driver.scene.camera.orbited(
                            from: orbit.camera, by: moved, height: driver.scene.size.height
                        ))
                    }
                case .pending, .longPressed, .pinching:
                    break
                }
                driver.press = press
            }
            .onEnded { _ in
                guard let press = driver.press else { return }
                driver.press = nil
                let orbited = driver.orbit != nil
                driver.orbit = nil
                noteActivity()
                if orbited { rerank() }
                guard press.phase == .pending,
                      Date.now.timeIntervalSince(driver.pressBegan) <= Self.tapSeconds else { return }
                tapped(press.hitID)
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

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                if driver.pinchBase == nil {
                    takeHold()
                    driver.pinchBase = driver.scene.camera
                    driver.orbit = nil
                    driver.press?.pinchBegan()
                    labelStore.hide()
                    noteActivity()
                }
                guard let base = driver.pinchBase else { return }
                driver.scene.setCamera(driver.scene.camera.zoomed(from: base, by: value.magnification))
            }
            .onEnded { _ in
                driver.pinchBase = nil
                noteActivity()
                rerank()
            }
    }
}

/// Up to 24 labels on plates, as the 2D canvas draws them. Never hit-tested:
/// a tap goes through to the star.
private struct ConstellationLabelsOverlay: View {
    let store: ConstellationLabelStore
    let theme: BrainGraphTheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(store.labels) { label in
                Text(verbatim: label.text)
                    .font(BrainCanvasPainter.labelFont)
                    .foregroundStyle(theme.label)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: label.rect.width, height: label.rect.height)
                    .background(
                        theme.background.opacity(BrainGraphCanvasLogic.labelPlateAlpha),
                        in: RoundedRectangle(cornerRadius: BrainGraphCanvasLogic.labelPlateRadius)
                    )
                    .position(x: label.rect.midX, y: label.rect.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        #if DEBUG
        .preference(key: BrainUITestProbeKey.self, value: store.probe)
        #endif
    }
}
