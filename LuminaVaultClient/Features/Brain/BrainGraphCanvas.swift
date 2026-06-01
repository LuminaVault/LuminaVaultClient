// LuminaVaultClient/LuminaVaultClient/Features/Brain/BrainGraphCanvas.swift
//
// HER-235 — Grape `ForceDirectedGraph` view configured for the LuminaVault
// sci-fi theme. Nodes encode three signals at once: radius ← importance
// (`score`), hue ← kind (memory = cyan, wiki page = gold), brightness ←
// recency (recent nodes glow brighter). Edges are coloured + weighted per
// derivation kind so the five connection types read as distinct signals.
//
// "Glow" here is SwiftUI-only: brightness/saturation + the `.lvBackground()`
// nebula behind the graph. Pixel-perfect additive bloom is a future Metal
// pass (tracked in the service header).

import Foundation
import Grape
import LuminaVaultShared
import SwiftUI

struct BrainGraphCanvas: View {

    @Environment(\.lvPalette) private var palette

    let graph: MemoryGraphResponse
    let onSelect: (UUID) -> Void

    @State private var graphStates = ForceDirectedGraphState()
    @State private var draggingID: UUID?

    /// Captured once per render so every node's recency is measured against
    /// the same "now" — keeps the glow stable within a frame.
    private let renderedAt = Date()

    var body: some View {
        ForceDirectedGraph(states: graphStates) {
            Series(graph.nodes) { node in
                NodeMark(id: node.id)
                    .symbolSize(radius: radius(for: node))
                    .foregroundStyle(nodeFill(for: node))
                    .stroke(
                        strokeColor(for: node),
                        Self.nodeStroke(for: node, dragging: draggingID == node.id),
                    )
            }
            Series(graph.edges) { edge in
                LinkMark(from: edge.from, to: edge.to)
                    .stroke(edgeStyle(for: edge), Self.edgeStroke(for: edge))
            }
        } force: {
            // Empirically tuned for ~500 nodes on iPhone 14 Pro. Tighten
            // `originalLength` and increase `manyBody` repulsion if the
            // graph collapses into the centre on small viewports.
            .manyBody(strength: -22)
            .link(originalLength: 28.0, stiffness: .weightedByDegree { _, _ in 3.0 })
            .center()
            .collide()
        }
        .graphOverlay { proxy in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .withGraphDragGesture(proxy, action: handleDrag)
                .withGraphMagnifyGesture(proxy)
                .onTapGesture { location in
                    // Grape's proxy returns the nearest node id under the
                    // tap point; nil = empty space (deselect).
                    if let any = proxy.locateNode(at: location),
                       let id = any as? UUID
                    {
                        onSelect(id)
                    }
                }
        }
    }

    // MARK: - Node geometry

    /// Maps `score` (loosely `[0, ∞)`) to a base radius in `[4, 13]`, with a
    /// small recency boost so fresh nodes read slightly larger. `log1p` keeps
    /// high-score outliers from blowing up the dot.
    private func radius(for node: MemoryGraphNodeDTO) -> CGFloat {
        let normalized = min(1.0, log1p(max(0, node.score)) / log1p(100))
        let base = 4 + CGFloat(normalized) * 9
        let recencyBoost = 1.5 * CGFloat(recency(of: node))
        return base + recencyBoost
    }

    // MARK: - Node colour

    /// Recency in `[0, 1]` where 1 = captured now, decaying to ~0 over 90
    /// days. Drives node brightness so the graph reads as "alive" — recent
    /// thoughts glow, old ones cool down.
    private func recency(of node: MemoryGraphNodeDTO) -> Double {
        let ageDays = renderedAt.timeIntervalSince(node.createdAt) / 86_400
        return max(0.0, min(1.0, 1.0 - ageDays / 90.0))
    }

    /// Memory nodes ride the cool channel (`lvBlue` → `lvCyan` by importance);
    /// wiki pages ride the warm channel (gold) so the two node kinds read as
    /// distinct at a glance. Recency lifts brightness within each channel.
    private func nodeFill(for node: MemoryGraphNodeDTO) -> Color {
        let t = min(1.0, log1p(max(0, node.score)) / log1p(100))
        let glow = 0.55 + 0.45 * recency(of: node) // [0.55, 1.0] opacity
        switch node.kind {
        case .wikiPage:
            return palette.accent.opacity(glow)
        case .memory:
            return palette.primary.mix(with: palette.secondary, by: 1 - t).opacity(glow)
        }
    }

    /// Wiki pages always carry a faint gold ring so they're identifiable even
    /// at rest; the drag highlight overrides with the bright accent stroke.
    private func strokeColor(for node: MemoryGraphNodeDTO) -> Color {
        if draggingID == node.id { return palette.accent }
        return node.kind == .wikiPage ? palette.accent.opacity(0.7) : .clear
    }

    private static func nodeStroke(for node: MemoryGraphNodeDTO, dragging: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: dragging ? 2.0 : (node.kind == .wikiPage ? 1.5 : 1.0), lineCap: .round)
    }

    // MARK: - Edge colour + weight

    /// Each derivation kind gets its own channel so the graph reads the five
    /// signals apart: wikilink = bright gold (explicit), tag = amber, space =
    /// teal, semantic = cyan, temporal = dim grey. Alpha scales with weight.
    private func edgeStyle(for edge: MemoryGraphEdgeDTO) -> Color {
        let w = edge.weight
        switch edge.kind {
        case .wikilink: return palette.accent.opacity(0.55 + 0.40 * w)
        case .tag: return palette.accent.opacity(0.25 + 0.45 * w)
        case .space: return palette.secondary.opacity(0.25 + 0.45 * w)
        case .semantic: return palette.primary.opacity(0.20 + 0.55 * w)
        case .temporal: return palette.textSecondary.opacity(0.12 + 0.25 * w)
        }
    }

    /// Explicit links draw thicker; inferred/temporal links stay hairline.
    /// Width also tracks weight so strong connections feel heavier.
    private static func edgeStroke(for edge: MemoryGraphEdgeDTO) -> StrokeStyle {
        let base: CGFloat
        switch edge.kind {
        case .wikilink: base = 1.8
        case .tag, .space: base = 1.2
        case .semantic: base = 1.0
        case .temporal: base = 0.6
        }
        let width = base + 0.8 * CGFloat(edge.weight)
        let dash: [CGFloat] = edge.kind == .temporal ? [3, 3] : []
        return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
    }

    // MARK: - Drag tracking

    private func handleDrag(_ state: GraphDragState?) {
        switch state {
        case .node(let anyHashable): draggingID = anyHashable as? UUID
        case .background, nil: draggingID = nil
        }
    }
}
