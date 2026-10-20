// LuminaVaultClient/LuminaVaultClient/Features/Commitments/CommitmentsListViewModel.swift
//
// Every open loop, not just the three the brief has room for: open by
// default, with done and dropped one segment away.
//
// Done / Drop on an open one and Reopen on a closed one are a PATCH of its
// state. Any of them moves the commitment out of the segment on screen, so
// the row leaves at once and comes back, with an inline error, when the
// server says no — a 409 on Reopen says plainly that an open loop with the
// same words already exists.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class CommitmentsListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// The segments. `all` stays an endpoint option the UI does not offer.
    enum Segment: String, CaseIterable, Identifiable, Sendable {
        case open
        case done
        case dropped

        var id: String { rawValue }

        var title: String {
            switch self {
            case .open: "Open"
            case .done: "Done"
            case .dropped: "Dropped"
            }
        }

        var query: CommitmentsQueryState {
            switch self {
            case .open: .open
            case .done: .done
            case .dropped: .dropped
            }
        }
    }

    struct ActionFailure: Equatable {
        let commitmentID: UUID
        let message: String
    }

    private(set) var segment: Segment
    private(set) var phase: Phase = .loading
    private(set) var items: [CommitmentDTO] = []
    private(set) var pendingIDs: Set<UUID> = []
    var actionFailure: ActionFailure?

    var isEmpty: Bool {
        items.isEmpty
    }

    private let client: any CommitmentsClientProtocol

    init(client: any CommitmentsClientProtocol, segment: Segment = .open) {
        self.client = client
        self.segment = segment
    }

    /// The segment's commitments. A failed refresh of the same segment keeps
    /// what is on screen.
    func load() async {
        let asked = segment
        do {
            let response = try await client.commitments(state: asked.query)
            // A segment switched while this was in flight has its own load.
            guard asked == segment else { return }
            items = response.items
            phase = .loaded
        } catch {
            guard asked == segment else { return }
            if case .loaded = phase { return }
            phase = .failed("Couldn't load your open loops.")
        }
    }

    /// Shows a segment and reads it — also the first load, and "Try again".
    func select(_ newSegment: Segment) async {
        if newSegment != segment {
            segment = newSegment
            items = []
            actionFailure = nil
            phase = .loading
        }
        await load()
    }

    // MARK: - Answers

    func markDone(_ commitment: CommitmentDTO) async {
        await move(commitment, to: .done)
    }

    func drop(_ commitment: CommitmentDTO) async {
        await move(commitment, to: .dropped)
    }

    func reopen(_ commitment: CommitmentDTO) async {
        await move(commitment, to: .open)
    }

    private func move(_ commitment: CommitmentDTO, to state: CommitmentState) async {
        guard let index = items.firstIndex(where: { $0.id == commitment.id }),
              !pendingIDs.contains(commitment.id)
        else { return }
        pendingIDs.insert(commitment.id)
        if actionFailure?.commitmentID == commitment.id { actionFailure = nil }
        let asked = segment
        items.remove(at: index)
        defer { pendingIDs.remove(commitment.id) }
        do {
            _ = try await client.update(id: commitment.id, state: state)
        } catch {
            // Only back into the segment it left; a switch since then shows
            // another segment, which this commitment never belonged to.
            guard asked == segment else { return }
            items.insert(commitment, at: min(index, items.count))
            actionFailure = ActionFailure(
                commitmentID: commitment.id,
                message: CommitmentCopy.failureMessage(for: error)
            )
        }
    }

    func errorMessage(for id: UUID) -> String? {
        actionFailure?.commitmentID == id ? actionFailure?.message : nil
    }
}
