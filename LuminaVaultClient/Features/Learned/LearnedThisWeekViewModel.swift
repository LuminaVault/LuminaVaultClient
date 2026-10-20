// LuminaVaultClient/LuminaVaultClient/Features/Learned/LearnedThisWeekViewModel.swift
//
// "What I learned this week": what Lumina picked up about the user and has
// not had confirmed — proposed SOUL.md changes and new preference / decision
// memories — with Keep and Forget on each.
//
// No endpoint of its own for the answers. A memory is kept or forgotten with
// the memory PATCH (`reviewState` "approved" / "rejected"); a SOUL change is
// approved or rejected through the self-improvement client Settings already
// uses. Answers are optimistic: the item leaves the list at once and comes
// back, with an inline error, if the server says no.
//
// One instance backs both Home's "Confirm what I learned" row and the sheet
// it opens, so an answer in the sheet takes one off the row's count too.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class LearnedThisWeekViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// An answer that did not land: which item, and why. Shown under that
    /// item once it is back in the list.
    struct ActionFailure: Equatable {
        let itemID: UUID
        let message: String
    }

    static let approvedReviewState = "approved"
    static let rejectedReviewState = "rejected"

    private(set) var phase: Phase = .loading
    private(set) var since: Date?
    private(set) var until: Date?
    private(set) var soulChanges: [LearnedSoulChangeDTO] = []
    private(set) var memories: [LearnedMemoryDTO] = []
    /// Items whose answer is in flight.
    private(set) var pendingIDs: Set<UUID> = []
    var actionFailure: ActionFailure?

    /// What is still waiting for an answer — the Home row's "N new".
    var count: Int {
        soulChanges.count + memories.count
    }

    var isEmpty: Bool {
        soulChanges.isEmpty && memories.isEmpty
    }

    /// "Oct 9 – Oct 16", in the user's locale and timezone.
    var rangeText: String? {
        guard let since, let until else { return nil }
        return Self.rangeText(since: since, until: until)
    }

    private let client: any LearnedClientProtocol
    private let memoryClient: any MemoryClientProtocol
    private let improvementClient: any SelfImprovementClientProtocol

    init(
        client: any LearnedClientProtocol,
        memoryClient: any MemoryClientProtocol,
        improvementClient: any SelfImprovementClientProtocol
    ) {
        self.client = client
        self.memoryClient = memoryClient
        self.improvementClient = improvementClient
    }

    /// First load, pull-to-refresh, and after the editor closes. A failed
    /// refresh keeps what is on screen: an unconfirmed preference does not
    /// stop being one because a pull dropped.
    func load() async {
        do {
            let digest = try await client.learned(since: nil)
            since = digest.since
            until = digest.until
            soulChanges = digest.soulChanges
            memories = digest.memories
            phase = .loaded
        } catch {
            if case .loaded = phase { return }
            phase = .failed("Couldn't load what I learned.")
        }
    }

    // MARK: - Memories

    func keep(_ memory: LearnedMemoryDTO) async {
        await answer(memory, reviewState: Self.approvedReviewState)
    }

    func forget(_ memory: LearnedMemoryDTO) async {
        await answer(memory, reviewState: Self.rejectedReviewState)
    }

    private func answer(_ memory: LearnedMemoryDTO, reviewState: String) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }),
              !pendingIDs.contains(memory.id)
        else { return }
        begin(memory.id)
        memories.remove(at: index)
        defer { pendingIDs.remove(memory.id) }
        do {
            _ = try await memoryClient.patch(id: memory.id, MemoryPatchRequest(reviewState: reviewState))
        } catch {
            memories.insert(memory, at: min(index, memories.count))
            actionFailure = ActionFailure(itemID: memory.id, message: Self.failureMessage)
        }
    }

    // MARK: - SOUL changes

    func keep(_ change: LearnedSoulChangeDTO) async {
        await decide(change, approve: true)
    }

    func forget(_ change: LearnedSoulChangeDTO) async {
        await decide(change, approve: false)
    }

    private func decide(_ change: LearnedSoulChangeDTO, approve: Bool) async {
        guard let index = soulChanges.firstIndex(where: { $0.id == change.id }),
              !pendingIDs.contains(change.id)
        else { return }
        begin(change.id)
        soulChanges.remove(at: index)
        defer { pendingIDs.remove(change.id) }
        do {
            _ = try await improvementClient.decide(changeID: change.id, approve: approve)
        } catch {
            soulChanges.insert(change, at: min(index, soulChanges.count))
            actionFailure = ActionFailure(itemID: change.id, message: Self.failureMessage)
        }
    }

    private func begin(_ id: UUID) {
        pendingIDs.insert(id)
        if actionFailure?.itemID == id { actionFailure = nil }
    }

    func errorMessage(for id: UUID) -> String? {
        actionFailure?.itemID == id ? actionFailure?.message : nil
    }

    // MARK: - Copy

    nonisolated static let failureMessage = "Couldn't save that. Try again."

    nonisolated static func rangeText(
        since: Date,
        until: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let style = Date.FormatStyle(locale: locale, timeZone: timeZone)
            .month(.abbreviated)
            .day()
        return "\(since.formatted(style)) – \(until.formatted(style))"
    }
}
