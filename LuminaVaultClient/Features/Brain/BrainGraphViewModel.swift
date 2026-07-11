// LuminaVaultClient/LuminaVaultClient/Features/Brain/BrainGraphViewModel.swift
//
// HER-235 — view-model for the Brain tab. Owns the in-flight fetch state
// for `GET /v1/memory/graph` and the currently-selected node for the
// detail sheet. Pure data layer; rendering lives in `BrainGraphCanvas`.

import Foundation
import LuminaVaultShared

@MainActor
@Observable
final class BrainGraphViewModel {
    enum LoadState {
        case idle
        case loading
        case loaded(MemoryGraphResponse)
        case failed(String)

        var graph: MemoryGraphResponse? {
            if case .loaded(let g) = self { return g }
            return nil
        }
    }

    private let client: any MemoryGraphClientProtocol
    private(set) var state: LoadState = .idle

    /// Currently-selected node id; drives the detail sheet. Reset to nil
    /// whenever the graph is re-fetched so stale selections don't survive
    /// a vault that has rotated its top-N memories.
    var selectedNodeID: UUID?

    init(client: any MemoryGraphClientProtocol) {
        self.client = client
    }

    func load(
        limit: Int? = nil,
        similarityThreshold: Double? = nil,
        maxEdgesPerNode: Int? = nil,
        includeWikiPages: Bool? = nil,
        kinds: [MemoryEdgeKindDTO]? = nil,
    ) async {
        state = .loading
        selectedNodeID = nil
        do {
            let response = try await client.fetchGraph(
                limit: limit,
                similarityThreshold: similarityThreshold,
                maxEdgesPerNode: maxEdgesPerNode,
                includeWikiPages: includeWikiPages,
                kinds: kinds,
            )
            state = .loaded(response)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func node(for id: UUID) -> MemoryGraphNodeDTO? {
        state.graph?.nodes.first { $0.id == id }
    }
}
