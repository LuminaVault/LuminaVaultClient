// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/BrainPreviewCard.swift
//
// Command Center — miniature, non-interactive 3D preview of the memory
// graph on Home. Maps `HomeSummaryResponse.graphPreview` (normalized
// [-1, 1] coordinates) into a minimal `MemoryGraphResponse` and embeds
// the existing `BrainGraphRealityView`. Tapping anywhere opens the full
// Brain tab.
//
// PERF: `BrainGraphRealityView` has no per-frame loop (RealityKit only
// re-renders on state change, and all gestures are disabled here), so
// this card costs ~0% CPU when idle or offscreen — unlike the old
// TimelineView-driven canvas (see brain_tab_perf_idle_loop).

import LuminaVaultShared
import SwiftUI

struct BrainPreviewCard: View {

    @Environment(\.lvPalette) private var palette

    let nodes: [GraphPreviewNodeDTO]
    let isLoading: Bool
    /// Opens the full Brain tab.
    let onOpen: () -> Void

    /// `MemoryGraphNodeDTO.position` lives in a ±60 cube server-side
    /// (see `BrainGraphRealityView.layoutScale`); preview coords are
    /// normalized to [-1, 1], so scale up to match.
    private static let cubeScale: Double = 60

    var body: some View {
        DashboardCardShell(title: "Neural Map", icon: "brain") {
            ZStack {
                if nodes.isEmpty {
                    placeholder
                } else {
                    BrainGraphRealityView(graph: previewGraph) { _ in }
                        .allowsHitTesting(false)
                        // Rebuild the RealityKit scene when the preview set
                        // changes (RealityView's `make` runs once per identity).
                        .id(signature)
                }

                // Whole card is one tap target → Brain tab.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Neural map preview — \(nodes.count) nodes. Opens the Brain tab.")
            .accessibilityAddTraits(.isButton)
        }
    }

    private var signature: String { "\(nodes.count)-\(nodes.first?.id.uuidString ?? "")" }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .tint(palette.accent)
            } else {
                LVIconView(.brainPremium, size: 28, tint: palette.textSecondary, weight: .regular)
                Text("Your memory graph appears here as you capture.")
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var previewGraph: MemoryGraphResponse {
        MemoryGraphResponse(
            nodes: nodes.map { node in
                MemoryGraphNodeDTO(
                    id: node.id,
                    title: node.label,
                    tags: [],
                    createdAt: Date(),
                    score: node.activity,
                    kind: node.kind == .concept ? .wikiPage : .memory,
                    activity: node.activity,
                    position: GraphPosition3D(
                        x: node.x * Self.cubeScale,
                        y: node.y * Self.cubeScale,
                        z: node.z * Self.cubeScale
                    )
                )
            },
            edges: [],
            generatedAt: Date()
        )
    }
}
