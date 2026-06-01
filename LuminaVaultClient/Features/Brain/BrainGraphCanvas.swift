// LuminaVaultClient/LuminaVaultClient/Features/Brain/BrainGraphCanvas.swift
//
// HER-235 — premium pure-SwiftUI knowledge graph. A `TimelineView` drives a
// `Canvas` at display rate; `BrainGraphEngine` owns the force simulation,
// view transform, and all drawing (volumetric glow, recency pulse, weight-
// glowed edges, breathing, drifting particles). Gestures provide pan with
// inertia, pinch-zoom, and tap-to-select with a highlight + scale animation.
//
// Public API (`init(graph:onSelect:)`) is unchanged so `BrainTabView` is
// untouched. Replaces the prior Grape renderer, which couldn't expose node
// positions or draw layered glow.

import Foundation
import LuminaVaultShared
import SwiftUI

struct BrainGraphCanvas: View {

    @Environment(\.lvPalette) private var palette

    let graph: MemoryGraphResponse
    let onSelect: (UUID) -> Void

    @State private var engine = BrainGraphEngine()
    @State private var lastDrag: CGSize = .zero
    @State private var zoomAnchor: CGFloat = 1

    /// Resync trigger: node/edge counts change on legend toggles. Surviving
    /// nodes keep their position inside the engine, so this never reshuffles.
    private var signature: String { "\(graph.nodes.count)-\(graph.edges.count)" }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                engine.advance(to: timeline.date)
                engine.draw(into: &ctx, size: size, style: style)
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(tapGesture)
        }
        .onAppear { engine.sync(graph: graph) }
        .onChange(of: signature) { _, _ in engine.sync(graph: graph) }
        .accessibilityLabel("Knowledge graph — \(graph.nodes.count) nodes")
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastDrag.width,
                    height: value.translation.height - lastDrag.height,
                )
                engine.pan(by: delta)
                lastDrag = value.translation
            }
            .onEnded { value in
                engine.endPan(velocity: value.velocity)
                lastDrag = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in engine.zoom(to: zoomAnchor * value.magnification) }
            .onEnded { _ in zoomAnchor = engine.scale }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                // Hit-test needs the view size; the engine stores the live
                // transform, and Canvas fills the whole view, so the gesture
                // location is already in that space.
                if let id = engine.hitTest(value.location, viewSize: lastViewSize) {
                    engine.selectedID = id
                    engine.reheat()
                    onSelect(id)
                }
            }
    }

    // SpatialTapGesture doesn't hand us the view size, so track it from the
    // Canvas via a geometry-free approximation: the engine centres on the
    // live view each draw, so we cache the most recent size there.
    private var lastViewSize: CGSize { engine.lastViewSize }

    // MARK: - Palette → Canvas colours

    private var style: BrainGraphStyle {
        BrainGraphStyle(
            memoryLow: palette.secondary,
            memoryHigh: palette.primary,
            wiki: palette.accent,
            space: Color(red: 0.20, green: 0.85, blue: 0.76),
            temporal: palette.textSecondary,
            selection: palette.accent,
            particle: palette.primary,
        )
    }
}
