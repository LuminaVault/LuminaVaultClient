// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesRunsListViewModel.swift
//
// Hermes Companion Phase 1 — every run this tenant has started, newest
// first. LuminaVault persists runs because the Hermes gateway forgets one
// 300 s after it finishes, so this list is history, not a live view of
// Hermes.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class HermesRunsListViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(HermesRunsFailure)
    }

    private(set) var state: LoadState = .loading
    private(set) var runs: [HermesRunDTO] = []

    private let client: any HermesRunsClientProtocol
    private let limit: Int

    init(client: any HermesRunsClientProtocol, limit: Int = 30) {
        self.client = client
        self.limit = limit
    }

    /// Seeds a loaded list. Used by previews and snapshot tests, which render
    /// synchronously and so never see the result of `load()`.
    convenience init(client: any HermesRunsClientProtocol, runs: [HermesRunDTO], limit: Int = 30) {
        self.init(client: client, limit: limit)
        self.runs = runs
        state = .loaded
    }

    /// Runs sitting on an approval prompt. Surfaced at the top of the screen
    /// because they are the only rows that need the user right now.
    var waitingForApproval: [HermesRunDTO] {
        runs.filter { $0.status == .waitingForApproval }
    }

    var active: [HermesRunDTO] {
        runs.filter { !$0.status.isTerminal && $0.status != .waitingForApproval }
    }

    var finished: [HermesRunDTO] {
        runs.filter(\.status.isTerminal)
    }

    func load() async {
        if runs.isEmpty { state = .loading }
        do {
            runs = try await client.list(limit: limit)
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            let failure = HermesRunsFailure(error)
            // Keep whatever is on screen if a refresh fails; only a cold load
            // is allowed to show the failure state.
            if runs.isEmpty {
                state = .failed(failure)
            } else {
                state = .loaded
            }
        }
    }
}
