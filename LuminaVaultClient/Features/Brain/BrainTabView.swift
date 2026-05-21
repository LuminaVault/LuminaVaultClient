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
    @State private var vm: BrainGraphViewModel

    init(client: any MemoryGraphClientProtocol) {
        self._vm = State(initialValue: BrainGraphViewModel(client: client))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Brain")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await vm.load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
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
                .tint(.lvCyan)
            Text("Building your brain…")
                .font(.callout)
                .foregroundStyle(Color.lvTextSub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 56))
                .foregroundStyle(Color.lvCyan.opacity(0.6))
            Text("No memories yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.lvTextPrimary)
            Text("Capture or save memories to grow your brain.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.lvTextSub)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lvBackground()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.lvAmber)
            Text("Couldn't load your brain")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.lvTextPrimary)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.lvTextSub)
                .padding(.horizontal, 32)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.lvCyan)
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
