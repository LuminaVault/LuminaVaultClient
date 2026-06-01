// LuminaVaultClient/LuminaVaultClient/Features/Brain/BrainGraphEngine.swift
//
// HER-235 — self-contained force-directed graph engine for the Brain view.
// Replaces the Grape renderer (which only exposes fill/size on its nodes and
// no node positions) so we can draw a fully bespoke, premium sci-fi graph in
// pure SwiftUI Canvas: layered volumetric glow, recency pulse, weight-glowed
// edges, breathing, drifting particles, pan/zoom/inertia, tap scale.
//
// The engine is a plain reference type (not @Observable): a `TimelineView`
// redraws every frame and calls `advance` + `draw`, so we never need SwiftUI
// to observe mutations. Physics runs on a fixed timestep with a settling
// `alpha` that reheats on interaction. Repulsion uses a uniform spatial hash
// so it stays ~O(n) for large vaults.

import Foundation
import LuminaVaultShared
import SwiftUI

/// Resolved palette colours handed to the engine at draw time (Canvas needs
/// concrete `Color`s, not the `@Environment` palette).
struct BrainGraphStyle {
    let memoryLow: Color   // low-importance memory (cool blue)
    let memoryHigh: Color  // high-importance memory (cyan)
    let wiki: Color        // wiki page (gold)
    let space: Color       // space edge (teal)
    let temporal: Color    // temporal edge (dim)
    let selection: Color   // selection ring
    let particle: Color
}

@MainActor
final class BrainGraphEngine {

    // MARK: Tunables

    private static let restLength: CGFloat = 64
    private static let repulsion: CGFloat = 7_000
    private static let springK: CGFloat = 0.045
    private static let centerK: CGFloat = 0.012
    private static let damping: CGFloat = 0.86
    private static let fixedDT: CGFloat = 1.0 / 60.0
    private static let maxStepsPerFrame = 3
    private static let minScale: CGFloat = 0.25
    private static let maxScale: CGFloat = 4.0
    private static let particleCount = 48

    // MARK: Sim state

    struct Node {
        let id: UUID
        let kind: GraphNodeKindDTO
        let importance: CGFloat   // 0…1, log-normalised score → radius/hue
        let recency: CGFloat      // 0…1, 1 = just now
        let phase: CGFloat        // per-node pulse offset
        var pos: CGPoint
        var vel: CGPoint = .zero
    }

    struct Edge {
        let a: Int
        let b: Int
        let kind: MemoryEdgeKindDTO
        let weight: CGFloat
    }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    private var indexByID: [UUID: Int] = [:]

    // PERF — reused per-frame scratch buffers. Previously `stepPhysics`
    // allocated a fresh force array + spatial-hash dictionary every step (up
    // to 3×/frame), churning the heap at display rate. Held here and cleared
    // in place instead.
    private var forceBuffer: [CGPoint] = []
    private var gridBuffer: [GridKey: [Int]] = [:]

    // MARK: View transform (owned here so inertia can animate it per frame)

    var scale: CGFloat = 1.0
    var offset: CGSize = .zero
    private var panVelocity: CGSize = .zero

    /// Most recent Canvas size, cached so the tap gesture (which isn't given
    /// a size) can hit-test in the same space the last frame drew in.
    private(set) var lastViewSize: CGSize = .zero

    // MARK: Selection

    var selectedID: UUID?
    /// 0…1 eased selection emphasis used for the highlight ring + scale.
    private var selectionPulse: CGFloat = 0

    // MARK: Clock

    private var lastTick: Date?
    private var accumulator: CGFloat = 0
    private(set) var time: CGFloat = 0
    private var alpha: CGFloat = 1.0   // settling temperature

    // MARK: Particles (view-space, normalised 0…1)

    private struct Particle { var base: CGPoint; var speed: CGFloat; var phase: CGFloat; var r: CGFloat }
    private var particles: [Particle] = []
    private var rng = SystemRandomNumberGenerator()

    // MARK: - Graph sync

    /// Diffs the incoming graph against the current sim: survivors keep their
    /// position (so legend toggles don't reshuffle the layout), new nodes are
    /// seeded on a deterministic spiral, removed nodes drop out. Reheats the
    /// simulation so it re-settles smoothly.
    func sync(graph: MemoryGraphResponse) {
        if particles.isEmpty { seedParticles() }

        var next: [Node] = []
        next.reserveCapacity(graph.nodes.count)
        var nextIndex: [UUID: Int] = [:]
        let count = max(1, graph.nodes.count)

        for (i, dto) in graph.nodes.enumerated() {
            let importance = Self.normalizedImportance(dto.score)
            let recency = Self.recency(of: dto.createdAt)
            let phase = CGFloat((abs(dto.id.hashValue) % 1000)) / 1000 * 2 * .pi
            let pos: CGPoint = indexByID[dto.id].map { nodes[$0].pos } ?? Self.seedPosition(index: i, count: count)
            let vel: CGPoint = indexByID[dto.id].map { nodes[$0].vel } ?? .zero
            nextIndex[dto.id] = next.count
            next.append(Node(
                id: dto.id, kind: dto.kind, importance: importance,
                recency: recency, phase: phase, pos: pos, vel: vel,
            ))
        }

        let resolvedEdges: [Edge] = graph.edges.compactMap { e in
            guard let a = nextIndex[e.from], let b = nextIndex[e.to] else { return nil }
            return Edge(a: a, b: b, kind: e.kind, weight: CGFloat(max(0, min(1, e.weight))))
        }

        nodes = next
        indexByID = nextIndex
        edges = resolvedEdges
        alpha = max(alpha, 0.9) // reheat
    }

    // MARK: - Per-frame update

    func advance(to date: Date) {
        defer { lastTick = date }
        guard let last = lastTick else { return }
        let elapsed = CGFloat(date.timeIntervalSince(last))
        guard elapsed > 0, elapsed < 1 else { return } // skip pauses / first frame
        time += elapsed
        accumulator += elapsed

        var steps = 0
        while accumulator >= Self.fixedDT, steps < Self.maxStepsPerFrame {
            stepPhysics(dt: Self.fixedDT)
            accumulator -= Self.fixedDT
            steps += 1
        }
        if steps == Self.maxStepsPerFrame { accumulator = 0 } // shed backlog

        // Inertial pan decay.
        if abs(panVelocity.width) > 0.1 || abs(panVelocity.height) > 0.1 {
            offset.width += panVelocity.width * elapsed
            offset.height += panVelocity.height * elapsed
            panVelocity.width *= 0.90
            panVelocity.height *= 0.90
        } else {
            panVelocity = .zero
        }

        // Ease the selection emphasis toward its target.
        let target: CGFloat = selectedID == nil ? 0 : 1
        selectionPulse += (target - selectionPulse) * min(1, elapsed * 8)
    }

    private func stepPhysics(dt: CGFloat) {
        guard nodes.count > 1 else { return }
        alpha = max(0, alpha * 0.992) // cool toward rest
        let energy = 0.25 + 0.75 * alpha

        // Repulsion via uniform spatial hash (cell ≈ 2× rest length).
        // Reuses `gridBuffer`/`forceBuffer` (cleared in place) to avoid
        // per-step heap allocation.
        let cell = Self.restLength * 2
        for key in gridBuffer.keys { gridBuffer[key]?.removeAll(keepingCapacity: true) }
        for i in nodes.indices {
            gridBuffer[GridKey(nodes[i].pos, cell), default: []].append(i)
        }
        let grid = gridBuffer
        if forceBuffer.count == nodes.count {
            for i in forceBuffer.indices { forceBuffer[i] = .zero }
        } else {
            forceBuffer = [CGPoint](repeating: .zero, count: nodes.count)
        }
        for i in nodes.indices {
            let pi = nodes[i].pos
            let base = GridKey(pi, cell)
            for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    guard let bucket = grid[GridKey(gx: base.gx + dx, gy: base.gy + dy)] else { continue }
                    for j in bucket where j != i {
                        var d = CGPoint(x: pi.x - nodes[j].pos.x, y: pi.y - nodes[j].pos.y)
                        var dist2 = d.x * d.x + d.y * d.y
                        if dist2 < 0.01 { d = CGPoint(x: .random(in: -1 ... 1, using: &rng), y: .random(in: -1 ... 1, using: &rng)); dist2 = 1 }
                        let f = Self.repulsion / dist2
                        let inv = 1 / sqrt(dist2)
                        forceBuffer[i].x += d.x * inv * f
                        forceBuffer[i].y += d.y * inv * f
                    }
                }
            }
        }

        // Springs along edges (stronger edges pull tighter).
        for e in edges {
            let pa = nodes[e.a].pos, pb = nodes[e.b].pos
            let dx = pb.x - pa.x, dy = pb.y - pa.y
            let dist = max(0.01, sqrt(dx * dx + dy * dy))
            let rest = Self.restLength * (1.4 - 0.6 * e.weight)
            let f = Self.springK * (dist - rest) * (0.5 + e.weight)
            let ux = dx / dist, uy = dy / dist
            forceBuffer[e.a].x += ux * f; forceBuffer[e.a].y += uy * f
            forceBuffer[e.b].x -= ux * f; forceBuffer[e.b].y -= uy * f
        }

        // Centering + integrate.
        for i in nodes.indices {
            forceBuffer[i].x -= nodes[i].pos.x * Self.centerK
            forceBuffer[i].y -= nodes[i].pos.y * Self.centerK
            var v = nodes[i].vel
            v.x = (v.x + forceBuffer[i].x * dt * energy) * Self.damping
            v.y = (v.y + forceBuffer[i].y * dt * energy) * Self.damping
            nodes[i].vel = v
            nodes[i].pos.x += v.x * dt
            nodes[i].pos.y += v.y * dt
        }
    }

    func reheat() { alpha = max(alpha, 0.6) }

    /// PERF — true while anything is still visibly moving (physics settling,
    /// pan inertia, or a selection ring easing in/out). The Canvas uses this
    /// to pause its `TimelineView` once the graph comes to rest, so a settled
    /// graph costs ~0% CPU instead of redrawing 3 blur passes at display rate
    /// forever. A gesture or `sync`/`reheat` re-arms it.
    var needsContinuousRedraw: Bool {
        if alpha > 0.03 { return true }
        if abs(panVelocity.width) > 0.1 || abs(panVelocity.height) > 0.1 { return true }
        // Mid-transition only: a fully-eased ring (≈0 or ≈1) is static.
        if selectionPulse > 0.01, selectionPulse < 0.99 { return true }
        return false
    }

    // MARK: - Interaction

    func pan(by delta: CGSize) {
        offset.width += delta.width
        offset.height += delta.height
        panVelocity = .zero
    }

    func endPan(velocity: CGSize) {
        // Clamp fling speed so it feels weighty, not skittish.
        panVelocity = CGSize(
            width: max(-2400, min(2400, velocity.width)),
            height: max(-2400, min(2400, velocity.height)),
        )
    }

    func zoom(to newScale: CGFloat) {
        scale = max(Self.minScale, min(Self.maxScale, newScale))
    }

    /// Hit-tests a view-space point and selects the nearest node within its
    /// (scaled) radius. Returns the node id when one is hit.
    func hitTest(_ point: CGPoint, viewSize: CGSize) -> UUID? {
        let center = CGPoint(x: viewSize.width / 2 + offset.width, y: viewSize.height / 2 + offset.height)
        let model = CGPoint(x: (point.x - center.x) / scale, y: (point.y - center.y) / scale)
        var best: (id: UUID, d2: CGFloat)?
        for n in nodes {
            let dx = n.pos.x - model.x, dy = n.pos.y - model.y
            let d2 = dx * dx + dy * dy
            let hitR = baseRadius(n) + 10
            if d2 <= hitR * hitR, best == nil || d2 < best!.d2 { best = (n.id, d2) }
        }
        return best?.id
    }

    // MARK: - Rendering

    func draw(into ctx: inout GraphicsContext, size: CGSize, style: BrainGraphStyle) {
        lastViewSize = size
        drawParticles(into: &ctx, size: size, style: style)

        let center = CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
        func view(_ p: CGPoint) -> CGPoint { CGPoint(x: center.x + p.x * scale, y: center.y + p.y * scale) }

        // Volumetric glow is faked with a handful of *batched* blur layers
        // (one blur pass each, not per-element) so cost is O(1) in passes
        // regardless of node count — the key to holding 60fps at ~500 nodes.

        // 1 — edge glow (single wide blurred pass for every edge).
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            for e in edges {
                var path = Path(); path.move(to: view(nodes[e.a].pos)); path.addLine(to: view(nodes[e.b].pos))
                layer.stroke(path, with: .color(edgeColor(e, style: style).opacity(0.10 + 0.25 * e.weight)),
                             style: StrokeStyle(lineWidth: edgeWidth(e) * 3, lineCap: .round))
            }
        }
        // 2 — crisp edges on top.
        for e in edges {
            var path = Path(); path.move(to: view(nodes[e.a].pos)); path.addLine(to: view(nodes[e.b].pos))
            let dash: [CGFloat] = e.kind == .temporal ? [3, 5] : []
            ctx.stroke(path, with: .color(edgeColor(e, style: style).opacity(0.35 + 0.5 * e.weight)),
                       style: StrokeStyle(lineWidth: edgeWidth(e), lineCap: .round, dash: dash))
        }

        // 3 — outer halos (one big-blur pass for all nodes).
        let medianR = (nodes.isEmpty ? 10 : baseRadius(nodes[nodes.count / 2])) * scale
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: max(8, medianR * 1.4)))
            for n in nodes {
                let r = renderRadius(n)
                layer.fill(Self.circle(view(n.pos), r * 2.4),
                           with: .color(nodeColor(n, style: style).opacity(0.16 * (0.45 + 0.55 * n.recency) * glowFactor(n))))
            }
        }
        // 4 — mid bloom (one medium-blur pass for all nodes).
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: max(4, medianR * 0.6)))
            for n in nodes {
                let r = renderRadius(n)
                layer.fill(Self.circle(view(n.pos), r * 1.5),
                           with: .color(nodeColor(n, style: style).opacity(0.38 * (0.45 + 0.55 * n.recency) * glowFactor(n))))
            }
        }
        // 5 — crisp cores + rings (no blur).
        for n in nodes {
            let p = view(n.pos)
            let r = renderRadius(n)
            let core = nodeColor(n, style: style)
            ctx.fill(Self.circle(p, r), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.9), core, core.opacity(0.85)]),
                center: p, startRadius: 0, endRadius: r,
            ))
            if n.id == selectedID {
                ctx.stroke(Self.circle(p, r + 4), with: .color(style.selection.opacity(0.9 * selectionPulse)), lineWidth: 2)
            } else if n.kind == .wikiPage {
                ctx.stroke(Self.circle(p, r + 1.5), with: .color(style.wiki.opacity(0.7)), lineWidth: 1.2)
            }
        }
    }

    /// Live render radius incl. breathing pulse (amplitude ↑ with recency)
    /// and selection scale.
    private func renderRadius(_ n: Node) -> CGFloat {
        // Only memories breathe; sources stay quiet satellites.
        let pulse = n.kind == .wikiPage ? 1 : 1 + (0.06 + 0.10 * n.recency) * sin(time * 2.2 + n.phase)
        let selBoost = n.id == selectedID ? (1 + 0.25 * selectionPulse) : 1
        return baseRadius(n) * scale * pulse * selBoost
    }

    private func drawParticles(into ctx: inout GraphicsContext, size: CGSize, style: BrainGraphStyle) {
        for p in particles {
            let x = (p.base.x + 0.03 * sin(time * p.speed + p.phase)).truncatingRemainder(dividingBy: 1)
            let y = (p.base.y + 0.025 * cos(time * p.speed * 0.8 + p.phase)).truncatingRemainder(dividingBy: 1)
            let vp = CGPoint(x: (x < 0 ? x + 1 : x) * size.width, y: (y < 0 ? y + 1 : y) * size.height)
            let twinkle = 0.06 + 0.10 * (0.5 + 0.5 * sin(time * 1.5 + p.phase))
            ctx.fill(Self.circle(vp, p.r), with: .color(style.particle.opacity(twinkle)))
        }
    }

    // MARK: - Mapping helpers

    // Memory-centric reframe: sources are demoted to small, dim, static
    // satellites so the memory network reads as the primary object.
    private func baseRadius(_ n: Node) -> CGFloat {
        if n.kind == .wikiPage { return 6 }
        return 5 + n.importance * 10 + n.recency * 2
    }

    /// Glow emphasis multiplier — sources are dimmed so memories dominate.
    private func glowFactor(_ n: Node) -> Double { n.kind == .wikiPage ? 0.35 : 1 }

    private func nodeColor(_ n: Node, style: BrainGraphStyle) -> Color {
        switch n.kind {
        case .wikiPage: return style.wiki
        case .memory: return style.memoryLow.mix(with: style.memoryHigh, by: n.importance)
        }
    }

    private func edgeColor(_ e: Edge, style: BrainGraphStyle) -> Color {
        switch e.kind {
        case .wikilink: return style.wiki
        case .tag: return style.wiki.opacity(0.8)
        case .space: return style.space
        case .semantic: return style.memoryHigh
        case .temporal: return style.temporal
        }
    }

    private func edgeWidth(_ e: Edge) -> CGFloat {
        let base: CGFloat
        switch e.kind {
        case .wikilink: base = 1.8
        case .tag, .space: base = 1.2
        case .semantic: base = 1.0
        case .temporal: base = 0.6
        }
        return (base + 0.8 * e.weight) * max(0.6, min(1.6, scale))
    }

    // MARK: - Seeding

    private static func normalizedImportance(_ score: Double) -> CGFloat {
        CGFloat(min(1.0, log1p(max(0, score)) / log1p(100)))
    }

    private static func recency(of date: Date) -> CGFloat {
        let ageDays = Date().timeIntervalSince(date) / 86_400
        return CGFloat(max(0.0, min(1.0, 1.0 - ageDays / 90.0)))
    }

    /// Golden-angle spiral so initial layout is spread, not piled at origin.
    private static func seedPosition(index: Int, count: Int) -> CGPoint {
        let golden = CGFloat.pi * (3 - sqrt(5))
        let radius = restLength * 0.9 * sqrt(CGFloat(index) + 0.5)
        let angle = CGFloat(index) * golden
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }

    private func seedParticles() {
        particles = (0 ..< Self.particleCount).map { _ in
            Particle(
                base: CGPoint(x: .random(in: 0 ... 1, using: &rng), y: .random(in: 0 ... 1, using: &rng)),
                speed: .random(in: 0.15 ... 0.5, using: &rng),
                phase: .random(in: 0 ... (2 * .pi), using: &rng),
                r: .random(in: 0.6 ... 1.8, using: &rng),
            )
        }
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    // Uniform-grid bucket key.
    private struct GridKey: Hashable {
        let gx: Int; let gy: Int
        init(gx: Int, gy: Int) { self.gx = gx; self.gy = gy }
        init(_ p: CGPoint, _ cell: CGFloat) { gx = Int((p.x / cell).rounded(.down)); gy = Int((p.y / cell).rounded(.down)) }
    }
}
