// LuminaVaultClient/LuminaVaultClient/Features/Brain/BrainTabView.swift
//
// HER-235 — root view for the Brain tab. Owns the view-model, runs the
// initial fetch on appear, and routes graph node taps through the detail
// sheet. The sci-fi background (nebula + star field) comes from the
// existing `.lvBackground()` modifier so the graph sits naturally inside
// the app's visual identity.

import LuminaVaultShared
import SwiftUI

struct BrainTabView: View {

    @Environment(\.lvPalette) private var palette

    @State private var vm: BrainGraphViewModel

    init(client: any MemoryGraphClientProtocol) {
        self._vm = State(initialValue: BrainGraphViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Brain")
                .navigationBarTitleDisplayMode(.inline)
                .lvNavBrand(position: .topLeading)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await vm.load() }
                        } label: {
                            LVIconView(.arrowClockwise)
                        }
                        .disabled(isLoading)
                    }
                }
                .task { await vm.load() }
                .sheet(item: selectedBinding) { node in
                    BrainNodeDetailSheet(node: node)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .loading:
            loadingState
        case .loaded(let graph) where graph.nodes.isEmpty:
            emptyState
        case .loaded(let graph):
            BrainGraphCanvas(graph: graph) { id in
                vm.selectedNodeID = id
            }
            .lvBackground()
        case .failed(let message):
            errorState(message)
        }
    }

    // MARK: - States

    private var isLoading: Bool {
        if case .loading = vm.state { return true }
        return false
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(palette.primary)
            Text("Building your brain…")
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    private var emptyState: some View {
        LVEmptyState(
            mascot: .thinking,
            headline: "No memory graph yet.",
            supporting: "Capture or save memories to grow your brain.",
            backgroundImage: "Lumina/Backgrounds/neural-network"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            LVIconView(.exclamationmarkTriangleFill, size: 42, tint: palette.accent)
            Text("Couldn't load your brain")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 32)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(palette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    // MARK: - Sheet binding

    /// Bridges `selectedNodeID` + the current graph into an `Identifiable`
    /// node for the sheet API.
    private var selectedBinding: Binding<MemoryGraphNodeDTO?> {
        Binding(
            get: { vm.selectedNodeID.flatMap(vm.node(for:)) },
            set: { node in vm.selectedNodeID = node?.id },
        )
    }
}
