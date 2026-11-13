// The pure rules behind the 2D Brain canvas: viewport maths and the automatic
// fit, hit testing, which points get a label and where it goes, how a press
// turns into a tap, a pan or a point drag, and the eased and inertial motions
// of the view. A port of the web app's `render-2d-helpers.ts`, with the same
// numbers except the hit floor (22 pt for a finger, web 10 px for a cursor).
// No SwiftUI, no state: `BrainGraphCanvas` calls these and draws.

import CoreGraphics
import Foundation

// MARK: - Viewport

/// Where the camera is. A world point `p` is drawn at `p * scale + offset`.
/// `isAutomatic` means the view is still the fitted one: it refits when the
/// canvas resizes or a new layout settles, until the user pans or zooms.
nonisolated struct BrainGraphViewport: Equatable, Sendable {
    var scale: CGFloat
    var offset: CGPoint
    var isAutomatic: Bool

    static let minScale: CGFloat = 0.15
    static let maxScale: CGFloat = 6
    /// Before anything is measured: automatic, so the first draw fits.
    static let initial = BrainGraphViewport(scale: 1, offset: .zero, isAutomatic: true)

    func screen(_ world: CGPoint) -> CGPoint {
        CGPoint(x: world.x * scale + offset.x, y: world.y * scale + offset.y)
    }

    func world(_ screen: CGPoint) -> CGPoint {
        CGPoint(x: (screen.x - offset.x) / scale, y: (screen.y - offset.y) / scale)
    }

    /// Zooms by `factor`, clamped to the limits, keeping the world point under
    /// the screen point `anchor` where it is.
    func zoomed(by factor: CGFloat, around anchor: CGPoint) -> BrainGraphViewport {
        guard factor.isFinite, factor > 0 else { return self }
        let next = min(Self.maxScale, max(Self.minScale, scale * factor))
        let held = world(anchor)
        return BrainGraphViewport(
            scale: next,
            offset: CGPoint(x: anchor.x - held.x * next, y: anchor.y - held.y * next),
            isAutomatic: isAutomatic
        )
    }

    func panned(by delta: CGSize) -> BrainGraphViewport {
        BrainGraphViewport(
            scale: scale, offset: CGPoint(x: offset.x + delta.width, y: offset.y + delta.height), isAutomatic: isAutomatic
        )
    }

    /// The view after the canvas changes size: the world point at the old
    /// centre stays at the centre, at the same scale (web `recentreOnResize`).
    func recentred(from old: CGSize, to new: CGSize) -> BrainGraphViewport {
        panned(by: CGSize(width: (new.width - old.width) / 2, height: (new.height - old.height) / 2))
    }

    /// The view with `world` in the middle of a canvas of `size`, at this scale.
    /// An explicit request: no longer automatic.
    func centred(on world: CGPoint, in size: CGSize) -> BrainGraphViewport {
        BrainGraphViewport(
            scale: scale,
            offset: CGPoint(x: size.width / 2 - world.x * scale, y: size.height / 2 - world.y * scale),
            isAutomatic: false
        )
    }

    /// The canvas rectangle in world units.
    func visibleWorldRect(in size: CGSize) -> CGRect {
        let origin = world(.zero)
        return CGRect(x: origin.x, y: origin.y, width: size.width / scale, height: size.height / scale)
    }

    /// The view that frames `bounds` (world units, padded by `pad`) in a
    /// canvas of `size`, leaving `fitMargin` of the smaller side clear on each
    /// side, at a scale between `minScale` and `cap` (web `fitView`).
    static func fit(
        bounds: CGRect, in size: CGSize, cap: CGFloat, pad: CGFloat = BrainGraphCanvasLogic.maxRadius
    ) -> BrainGraphViewport {
        let margin = BrainGraphCanvasLogic.fitMargin * min(size.width, size.height)
        let w = max(1, size.width - 2 * margin)
        let h = max(1, size.height - 2 * margin)
        let bw = bounds.width + 2 * pad
        let bh = bounds.height + 2 * pad
        let k = max(minScale, min(cap, w / bw, h / bh))
        return BrainGraphViewport(
            scale: k,
            offset: CGPoint(x: size.width / 2 - bounds.midX * k, y: size.height / 2 - bounds.midY * k),
            isAutomatic: true
        )
    }

    /// Linear blend; `isAutomatic` is the destination's.
    func interpolated(to other: BrainGraphViewport, fraction t: CGFloat) -> BrainGraphViewport {
        BrainGraphViewport(
            scale: scale + (other.scale - scale) * t,
            offset: CGPoint(x: offset.x + (other.offset.x - offset.x) * t, y: offset.y + (other.offset.y - offset.y) * t),
            isAutomatic: other.isAutomatic
        )
    }
}

/// What can happen to the view, as far as "is it still the automatic fit" goes.
nonisolated enum BrainViewEvent: Sendable {
    case freshGraph, userZoom, userPan, centreOn, pointDrag
}

nonisolated enum BrainResizeAction: Sendable, Equatable {
    case refit, recentre
}

// MARK: - Rules

nonisolated enum BrainGraphCanvasLogic {
    /// A graph this small labels every point from zoom 0.5, may zoom in to 2.2
    /// when fitted, and keeps labels off every point.
    static let smallGraph = 80
    static let maxLabels = 160
    static let labelMaxChars = 28
    /// Share of the smaller canvas side left clear around a fitted graph.
    static let fitMargin: CGFloat = 0.12
    /// Largest radius a point can have (`ForceSimulation2D.maxRadius`).
    static let maxRadius: CGFloat = ForceSimulation2D.maxRadius
    /// Smallest hit radius on screen, in points: a fingertip.
    static let hitFloor: CGFloat = 22
    /// Below about a point and a half a point stops reading as a point.
    static let minDrawnRadius: CGFloat = 1.5
    /// How far outside a selected point its ring reaches, in screen points.
    static let selectedRingGap: CGFloat = 3
    static let selectedRingWidth: CGFloat = 2
    static let hubRingWidth: CGFloat = 1.5
    static let edgeWidth: CGFloat = 1
    static let edgeAlpha: CGFloat = 0.35
    static let litEdgeAlpha: CGFloat = 0.9
    static let dimAlpha: CGFloat = 0.12
    static let labelPlateAlpha: CGFloat = 0.78
    static let labelPlateRadius: CGFloat = 3
    /// A label plate pads its text this much either side.
    static let labelSidePadding: CGFloat = 2

    static func fitZoomCap(pointCount: Int) -> CGFloat {
        pointCount <= smallGraph ? 2.2 : 1
    }

    /// Whether the view is still the automatic fit after `event` (web
    /// `nextAutoView`): a fresh graph returns to it; the user zooming or
    /// panning, or an explicit centre, leaves it; dragging a point does not.
    static func nextAutoView(_ autoView: Bool, _ event: BrainViewEvent) -> Bool {
        switch event {
        case .freshGraph: true
        case .pointDrag: autoView
        case .userZoom, .userPan, .centreOn: false
        }
    }

    /// Refit while automatic, else keep the centre. Never refit under a point
    /// being dragged: the camera would move under the finger.
    static func resizeAction(autoView: Bool, dragging: Bool) -> BrainResizeAction {
        autoView && !dragging ? .refit : .recentre
    }

    /// The automatic view of `points` in a canvas of `size`: the whole graph
    /// framed, with the zoom cap of its point count. With nothing to frame, the
    /// world origin in the middle at scale 1.
    static func fittedView(points: [CGPoint], size: CGSize) -> BrainGraphViewport {
        guard let bounds = bounds(of: points) else {
            return BrainGraphViewport(
                scale: 1, offset: CGPoint(x: size.width / 2, y: size.height / 2), isAutomatic: true
            )
        }
        return BrainGraphViewport.fit(bounds: bounds, in: size, cap: fitZoomCap(pointCount: points.count))
    }

    /// Whether incoming ids make a fresh graph (laid out from scratch, framed on
    /// every step) rather than an update of the current one (web
    /// `isFreshGraph`). An empty graph is never fresh.
    static func isFreshGraph(_ ids: [String], known: Set<String>) -> Bool {
        !ids.isEmpty && !ids.contains(where: known.contains)
    }

    /// The canvas is one VoiceOver element; the list is the way to browse.
    static func accessibilityLabel(itemCount: Int) -> String {
        "Graph of \(itemCount) notes and memories. Use the list to browse."
    }

    /// The bounding box of the finite points, or nil when there are none.
    static func bounds(of points: [CGPoint]) -> CGRect? {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for p in points where p.x.isFinite && p.y.isFinite {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The nearest point whose hit radius, `max(radius, hitFloor / scale)` in
    /// world units, covers `at`, or nil. A linear scan: it runs once per tap or
    /// drag start, never per frame, and a thousand points cost microseconds.
    static func hitTest(points: [CGPoint], radii: [CGFloat], at: CGPoint, scale: CGFloat) -> Int? {
        let floor = hitFloor / max(scale, .leastNonzeroMagnitude)
        var best: Int?
        var bestD2 = CGFloat.infinity
        for i in points.indices where i < radii.count {
            let p = points[i]
            guard p.x.isFinite, p.y.isFinite else { continue }
            let dx = p.x - at.x, dy = p.y - at.y
            let d2 = dx * dx + dy * dy
            let hit = max(radii[i], floor)
            if d2 <= hit * hit, d2 < bestD2 {
                best = i
                bestD2 = d2
            }
        }
        return best
    }

    // MARK: Labels

    /// The weight a point needs to be among the heaviest tenth (ties
    /// included). Never below 1, so weightless points have no top tenth.
    static func topTenthWeight(_ weights: [Int]) -> Int {
        guard !weights.isEmpty else { return 1 }
        let sorted = weights.sorted(by: >)
        return max(1, sorted[(sorted.count + 9) / 10 - 1])
    }

    /// Whether a point that is not selected is offered a label. `lit` is nil
    /// when nothing is lit; otherwise only lit points are. With nothing lit:
    /// every point from zoom 1.6, every point of a small graph from 0.5, the
    /// heaviest tenth from 0.9.
    static func offerLabel(lit: Bool?, weight: Int, zoom: CGFloat, topTenth: Int, small: Bool) -> Bool {
        if let lit { return lit }
        if zoom >= 1.6 { return true }
        if small, zoom >= 0.5 { return true }
        return zoom >= 0.9 && weight >= topTenth
    }

    /// A small graph has the room to keep labels off every point; a large one
    /// keeps them off hub rings and selected points only.
    static func labelsAvoidEveryPoint(pointCount: Int) -> Bool {
        pointCount <= smallGraph
    }

    /// Where a forced label goes when no free spot lies wholly on the canvas:
    /// below the point if that fits the canvas height, else above, else
    /// whichever is nearer to fitting, slid sideways (and, failing that,
    /// vertically) to lie inside the canvas. Wider than the canvas, it starts
    /// at the left edge; the caller truncates the text (`truncateLabel(_:toFit:measuredWidth:)`).
    static func forcedSpot(_ spots: BrainLabelSpots, canvas: CGSize) -> BrainLabelSpot {
        let fitsHeight = { (s: BrainLabelSpot) in s.rect.minY >= 0 && s.rect.maxY <= canvas.height }
        var spot: BrainLabelSpot
        if fitsHeight(spots.below) {
            spot = spots.below
        } else if fitsHeight(spots.above) {
            spot = spots.above
        } else {
            spot = spots.below.rect.maxY - canvas.height <= -spots.above.rect.minY ? spots.below : spots.above
        }
        var dx: CGFloat = 0
        if spot.rect.width >= canvas.width || spot.rect.minX < 0 {
            dx = -spot.rect.minX
        } else if spot.rect.maxX > canvas.width {
            dx = canvas.width - spot.rect.maxX
        }
        var dy: CGFloat = 0
        if spot.rect.minY < 0 {
            dy = -spot.rect.minY
        } else if spot.rect.maxY > canvas.height {
            dy = canvas.height - spot.rect.maxY
        }
        spot.rect = spot.rect.offsetBy(dx: dx, dy: dy)
        spot.text = CGPoint(x: spot.text.x + dx, y: spot.text.y + dy)
        return spot
    }

    /// `label` cut with an ellipsis so text measured `measuredWidth` wide fits
    /// `width`, by its average character width. Unchanged when it fits.
    static func truncateLabel(_ label: String, toFit width: CGFloat, measuredWidth: CGFloat) -> String {
        guard measuredWidth > width, width > 0, !label.isEmpty else { return label }
        let keep = Int((CGFloat(label.count) * width / measuredWidth).rounded(.down)) - 1
        return truncateLabel(label, max: Swift.max(1, keep))
    }

    static func truncateLabel(_ label: String, max: Int = labelMaxChars) -> String {
        guard label.count > max else { return label }
        var cut = String(label.prefix(max))
        while let last = cut.last, last.isWhitespace { cut.removeLast() }
        return cut + "…"
    }

    /// Where a label may sit around a point at screen `centre` of screen
    /// `radius`, in the order tried: below, above, right. None touches the
    /// point. Each box pads the text 2 pt either side and 1 pt above and below.
    static func labelSpots(centre: CGPoint, radius r: CGFloat, text: CGSize) -> BrainLabelSpots {
        let half = text.width / 2 + labelSidePadding
        let h = text.height + 2
        func spot(_ x0: CGFloat, _ y0: CGFloat) -> BrainLabelSpot {
            BrainLabelSpot(rect: CGRect(x: x0, y: y0, width: half * 2, height: h), text: CGPoint(x: x0 + half, y: y0 + 1))
        }
        return BrainLabelSpots(
            below: spot(centre.x - half, centre.y + r + 2.5),
            above: spot(centre.x - half, centre.y - r - 2.5 - h),
            right: spot(centre.x + r + 4, centre.y - h / 2)
        )
    }

    /// Whether every spot a label could take lies off the canvas: plain
    /// arithmetic over their union, so off-screen candidates are dropped
    /// before any box is touched.
    static func labelOffscreen(centre: CGPoint, radius r: CGFloat, text: CGSize, canvas: CGSize) -> Bool {
        let half = text.width / 2 + labelSidePadding
        let h = text.height + 2
        let left = centre.x - half
        let right = centre.x + r + 4 + half * 2
        let top = centre.y - r - 2.5 - h
        let bottom = centre.y + r + 2.5 + h
        return right <= 0 || left >= canvas.width || bottom <= 0 || top >= canvas.height
    }
}

// MARK: - Label boxes

nonisolated struct BrainLabelSpot: Equatable, Sendable {
    /// The plate, in screen points.
    var rect: CGRect
    /// Where the text goes: its top centre.
    var text: CGPoint
}

/// The three candidate spots of one label, by value so trying them allocates nothing.
nonisolated struct BrainLabelSpots: Equatable, Sendable {
    var below: BrainLabelSpot
    var above: BrainLabelSpot
    var right: BrainLabelSpot
}

/// Screen boxes claimed this frame (label plates, and the circles labels keep
/// off), bucketed on a grid over the canvas so a new box is checked only
/// against its neighbours. Boxes past the edges fall into the border cells.
/// `clear` keeps every buffer's storage, so a canvas reuses one per frame.
nonisolated struct BrainLabelBoxes: Sendable {
    static let cell: CGFloat = 64

    private var rects: [CGRect] = []
    private var cells: [[Int32]] = []
    private var columns = 0
    private var rows = 0

    init(canvas: CGSize) {
        clear(canvas: canvas)
    }

    /// Forgets every box. Regrids only when the canvas size needs other cells.
    mutating func clear(canvas: CGSize) {
        rects.removeAll(keepingCapacity: true)
        let c = max(1, Int((max(0, canvas.width) / Self.cell).rounded(.up)))
        let r = max(1, Int((max(0, canvas.height) / Self.cell).rounded(.up)))
        if c != columns || r != rows {
            columns = c
            rows = r
            cells = Array(repeating: [], count: c * r)
        } else {
            for i in cells.indices where !cells[i].isEmpty { cells[i].removeAll(keepingCapacity: true) }
        }
    }

    private func span(_ rect: CGRect) -> (c0: Int, c1: Int, r0: Int, r1: Int) {
        func clamp(_ v: CGFloat, _ n: Int) -> Int {
            guard v.isFinite else { return v > 0 ? n - 1 : 0 }
            return min(n - 1, max(0, Int((v / Self.cell).rounded(.down))))
        }
        return (clamp(rect.minX, columns), clamp(rect.maxX, columns), clamp(rect.minY, rows), clamp(rect.maxY, rows))
    }

    /// Whether `rect` overlaps nothing claimed so far (touching edges is fine).
    func isFree(_ rect: CGRect) -> Bool {
        let s = span(rect)
        for row in s.r0 ... s.r1 {
            for column in s.c0 ... s.c1 {
                for at in cells[row * columns + column] {
                    let o = rects[Int(at)]
                    if rect.minX < o.maxX, rect.maxX > o.minX, rect.minY < o.maxY, rect.maxY > o.minY { return false }
                }
            }
        }
        return true
    }

    /// Claims `rect` without checking.
    mutating func occupy(_ rect: CGRect) {
        let at = Int32(rects.count)
        rects.append(rect)
        let s = span(rect)
        for row in s.r0 ... s.r1 {
            for column in s.c0 ... s.c1 { cells[row * columns + column].append(at) }
        }
    }

    /// Claims `rect` if it is free; returns whether it did.
    mutating func claim(_ rect: CGRect) -> Bool {
        guard isFree(rect) else { return false }
        occupy(rect)
        return true
    }

    /// Claims and returns the first of the spots that lies wholly on the
    /// canvas and is free. When none is, a forced label (a selected point's)
    /// takes `forcedSpot`, slid onto the canvas; any other is skipped, so labels are never cut by the edge (the web keeps spots
    /// that only touch the canvas; a phone's narrow edges cut too many). A
    /// label with no spot on the canvas is never placed.
    mutating func place(_ spots: BrainLabelSpots, canvas: CGSize, force: Bool) -> BrainLabelSpot? {
        let bounds = CGRect(origin: .zero, size: canvas)
        var firstOnCanvas: BrainLabelSpot?
        for spot in [spots.below, spots.above, spots.right] where spot.rect.intersects(bounds) {
            if firstOnCanvas == nil { firstOnCanvas = spot }
            if bounds.contains(spot.rect), isFree(spot.rect) {
                occupy(spot.rect)
                return spot
            }
        }
        guard force, firstOnCanvas != nil else { return nil }
        let spot = BrainGraphCanvasLogic.forcedSpot(spots, canvas: canvas)
        occupy(spot.rect)
        return spot
    }
}

// MARK: - Presses

/// One finger on the canvas, from touch-down to lift. Decides whether the press
/// is still a tap, has become a pan (started on empty space) or a point drag
/// (started on a point), was a long press, or turned into a pinch. Once it has
/// moved past `slop`, been long-pressed or pinched, it never becomes a tap.
nonisolated struct BrainPressTracker: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case pending, longPressed, panning, draggingPoint, pinching
    }

    /// Movement that turns a press into a drag, in screen points.
    static let slop: CGFloat = 8
    static let longPressSeconds: Double = 0.4

    let start: CGPoint
    /// The point under the finger at touch-down, if any.
    let hitID: String?
    private(set) var phase: Phase = .pending

    init(start: CGPoint, hitID: String?) {
        self.start = start
        self.hitID = hitID
    }

    /// A tap may fire for this press.
    var allowsTap: Bool { phase == .pending }

    mutating func move(to location: CGPoint) -> Phase {
        switch phase {
        case .pending, .longPressed:
            if hypot(location.x - start.x, location.y - start.y) > Self.slop {
                phase = hitID == nil ? .panning : .draggingPoint
            }
        case .panning, .draggingPoint, .pinching:
            break
        }
        return phase
    }

    /// The long-press time has passed with the finger still down. Returns
    /// whether a long press fires now: once, on a point, before any movement.
    mutating func longPressElapsed() -> Bool {
        guard phase == .pending, hitID != nil else { return false }
        phase = .longPressed
        return true
    }

    mutating func pinchBegan() {
        phase = .pinching
    }

    /// What to do with the press on record when a drag reports a change.
    enum Recovery: Equatable, Sendable {
        /// Nothing on record, or the same gesture: carry on.
        case none
        /// The press on record belongs to a gesture that was cancelled
        /// without `onEnded` (a second finger, the system): drop it and start
        /// a new one, letting go of the point it held, if any.
        case restart(release: String?)
    }

    /// `DragGesture.onEnded` is not called when a drag is cancelled, so the
    /// first change of the next gesture finds the old press still recorded.
    /// A drag's start never moves while it lasts: a press recorded with
    /// another start is stale.
    static func recovery(current: BrainPressTracker?, gestureStart: CGPoint) -> Recovery {
        guard let current, current.start != gestureStart else { return .none }
        return .restart(release: current.phase == .draggingPoint ? current.hitID : nil)
    }
}

// MARK: - Motion

/// A timed change of the view, evaluated per display frame while it runs: an
/// eased move to a fitted or centred view, or the glide after a fling. `end`
/// is where it comes to rest; the canvas commits that once `duration` is over.
nonisolated struct BrainViewportMotion: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case ease(from: BrainGraphViewport)
        case fling(from: BrainGraphViewport, velocity: CGSize)
    }

    /// Web `CENTRE_MS`.
    static let easeDuration: TimeInterval = 0.3
    /// Exponential decay of a fling's speed: it travels `velocity * τ` in all.
    /// Between UIScrollView's fast (0.1 s) and normal (0.5 s) rates.
    static let flingTimeConstant: CGFloat = 0.3
    static let maxFlingSpeed: CGFloat = 2400
    /// A release slower than this just stops.
    static let minFlingSpeed: CGFloat = 80
    /// A fling ends when less than this distance is left to travel.
    static let restDistance: CGFloat = 0.5

    let kind: Kind
    let end: BrainGraphViewport
    let start: Date
    let duration: TimeInterval

    static func ease(from: BrainGraphViewport, to: BrainGraphViewport, start: Date) -> BrainViewportMotion {
        BrainViewportMotion(kind: .ease(from: from), end: to, start: start, duration: easeDuration)
    }

    /// The glide after a pan released at `velocity` (points per second), or
    /// nil when the release was too slow to glide.
    static func fling(from: BrainGraphViewport, velocity: CGSize, start: Date) -> BrainViewportMotion? {
        guard velocity.width.isFinite, velocity.height.isFinite else { return nil }
        let speed = hypot(velocity.width, velocity.height)
        guard speed >= minFlingSpeed else { return nil }
        let k = min(1, maxFlingSpeed / speed)
        let v = CGSize(width: velocity.width * k, height: velocity.height * k)
        let tau = flingTimeConstant
        let travel = speed * k * tau
        let duration = Double(tau * log(max(1, travel / restDistance)))
        var end = from.panned(by: CGSize(width: v.width * tau, height: v.height * tau))
        end.isAutomatic = false
        return BrainViewportMotion(kind: .fling(from: from, velocity: v), end: end, start: start, duration: duration)
    }

    func isFinished(at date: Date) -> Bool {
        date.timeIntervalSince(start) >= duration
    }

    func viewport(at date: Date) -> BrainGraphViewport {
        let t = max(0, date.timeIntervalSince(start))
        guard t < duration else { return end }
        switch kind {
        case let .ease(from):
            let u = CGFloat(t / duration)
            // Cubic in-out, as the web's fit and centre.
            let e = u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
            return from.interpolated(to: end, fraction: e)
        case let .fling(from, velocity):
            let tau = Self.flingTimeConstant
            let gone = tau * (1 - exp(-CGFloat(t) / tau))
            var v = from.panned(by: CGSize(width: velocity.width * gone, height: velocity.height * gone))
            v.isAutomatic = false
            return v
        }
    }
}
