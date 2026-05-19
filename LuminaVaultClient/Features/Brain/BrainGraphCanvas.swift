// LuminaVaultClient/LuminaVaultClient/Features/Brain/BrainGraphCanvas.swift
//
// HER-235 — Grape `ForceDirectedGraph` view configured for the LuminaVault
// theme. Node radius scales with `score`; node fill interpolates from
// `lvBlue` (low) to `lvCyan` (high). Edges: semantic = `lvCyan` weighted
// alpha; tag = `lvAmber` weighted alpha. Tap → onSelect callback.

import Foundation
import Grape
import LuminaVaultShared
import SwiftUI

struct BrainGraphCanvas: View {
    let graph: MemoryGraphResponse
    let onSelect: (UUID) -> Void

    @State private var graphStates = ForceDirectedGraphState()
    @State private var draggingID: UUID?

    private static let edgeStroke = StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)

    var body: some View {
        ForceDirectedGraph(states: graphStates) {
            Series(graph.nodes) { node in
                NodeMark(id: node.id)
                    .symbolSize(radius: Self.radius(for: node.score))
                    .foregroundStyle(Self.nodeFill(for: node.score))
                    .stroke(
                        draggingID == node.id ? Color.lvAmber : .clear,
                        Self.edgeStroke,
                    )
            }
            Series(graph.edges) { edge in
                LinkMark(from: edge.from, to: edge.to)
                    .stroke(Self.edgeStyle(for: edge), Self.edgeStroke)
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

    // MARK: - Styling

    /// Maps `memories.score` (loosely `[0, ∞)`) to a node radius in `[4, 14]`.
    /// `log1p` keeps high-score outliers from blowing up the dot.
    private static func radius(for score: Double) -> CGFloat {
        let normalized = min(1.0, log1p(max(0, score)) / log1p(100))
        return 4 + CGFloat(normalized) * 10
    }

    /// Interpolates `lvBlue` → `lvCyan` along the same score curve as the
    /// radius so size and hue track together.
    private static func nodeFill(for score: Double) -> Color {
        let t = min(1.0, log1p(max(0, score)) / log1p(100))
        // SwiftUI doesn't expose RGB blending on `Color`, so we layer a
        // gradient by overlaying `lvCyan.opacity(t)` on `lvBlue`. Good
        // enough at node scale (4–14 px); we can swap to a Metal shader
        // when we need pixel-perfect bloom.
        return Color.lvCyan.mix(with: .lvBlue, by: 1 - t)
    }

    /// Semantic edges use the cool channel (`lvCyan`); tag edges use the
    /// warm channel (`lvAmber`) so the two derivation paths read as
    /// distinct signals on the graph.
    private static func edgeStyle(for edge: MemoryGraphEdgeDTO) -> Color {
        switch edge.kind {
        case .semantic: return Color.lvCyan.opacity(0.25 + 0.55 * edge.weight)
        case .tag: return Color.lvAmber.opacity(0.30 + 0.50 * edge.weight)
        }
    }

    // MARK: - Drag tracking

    private func handleDrag(_ state: GraphDragState?) {
        switch state {
        case .node(let anyHashable): draggingID = anyHashable as? UUID
        case .background, nil: draggingID = nil
        }
    }
}

