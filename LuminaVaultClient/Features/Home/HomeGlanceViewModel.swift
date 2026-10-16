// LuminaVaultClient/LuminaVaultClient/Features/Home/HomeGlanceViewModel.swift
//
// The three numbers the Dashboard was worth keeping, and the one thing to do
// next.
//
// The Dashboard asked six endpoints to draw a report about a vault most people
// have barely filled. Home asks three, for three numbers on one row, and never
// polls: it loads when Home appears and when the user pulls to refresh.
//
// Each call settles into its own state so a dead endpoint costs one tile
// rather than the strip.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class HomeGlanceViewModel {
    /// Ported from the Dashboard's `HomeViewModel` when that screen was
    /// deleted: per-item state is what keeps one failure local.
    enum CardState<T: Sendable>: Sendable {
        case loading
        case loaded(T)
        case failed(message: String)

        var value: T? {
            if case .loaded(let v) = self { return v }
            return nil
        }

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    /// The one row Home offers under the strip. Only ever one: two rows of
    /// suggestions is a to-do list nobody asked for.
    enum Recommendation: Equatable, Sendable {
        /// Captures are in the vault but not yet in the brain.
        case syncAndLearn(Int)
        /// Memos from the last few days worth re-reading.
        case dailyReview(Int)
    }

    /// Two tiles off one call: the summary endpoint answers both, so they
    /// settle together and fail together.
    private(set) var memoriesToday: CardState<Int> = .loading
    private(set) var streakDays: CardState<Int> = .loading
    private(set) var toRevisit: CardState<Int> = .loading
    private(set) var pendingFiles: CardState<Int> = .loading
    /// The last seven days, for the "Your week" strip. Independent of the
    /// three tiles: it hides on failure and never counts towards `allFailed`,
    /// because the strip above it is the glance and this is a way into more.
    private(set) var recap: CardState<MeRecapResponse>

    /// Nothing loaded at all — the strip hides rather than showing three
    /// dashes and pretending it is a report.
    var allFailed: Bool {
        memoriesToday.isFailed && toRevisit.isFailed && pendingFiles.isFailed
    }

    var recommendation: Recommendation? {
        if let pending = pendingFiles.value, pending > 0 { return .syncAndLearn(pending) }
        if let revisit = toRevisit.value, revisit > 0 { return .dailyReview(revisit) }
        return nil
    }

    private let homeClient: any HomeSummaryClientProtocol
    private let dailyReviewClient: any DailyReviewClientProtocol
    private let pendingClient: any KBCompileClientProtocol
    /// Nil leaves the week strip off entirely — previews and snapshot suites
    /// that predate it render Home exactly as before.
    private let recapClient: (any RecapClientProtocol)?

    init(
        homeClient: any HomeSummaryClientProtocol,
        dailyReviewClient: any DailyReviewClientProtocol,
        pendingClient: any KBCompileClientProtocol,
        recapClient: (any RecapClientProtocol)? = nil
    ) {
        self.homeClient = homeClient
        self.dailyReviewClient = dailyReviewClient
        self.pendingClient = pendingClient
        self.recapClient = recapClient
        recap = recapClient == nil ? .failed(message: "Not configured") : .loading
    }

    func load() async {
        async let summaryState = loadSummary()
        async let toRevisitState = loadToRevisit()
        async let pendingState = loadPending()
        let (summary, revisit, pending) = await (summaryState, toRevisitState, pendingState)

        switch summary {
        case .loading:
            break
        case .loaded(let response):
            memoriesToday = .loaded(response.memoriesToday)
            streakDays = .loaded(response.streakDays)
        case .failed(let message):
            memoriesToday = .failed(message: message)
            streakDays = .failed(message: message)
        }
        toRevisit = revisit
        pendingFiles = pending

        // After the tiles rather than beside them: the strip sits below them,
        // so it settling a beat later is invisible.
        let newRecap = await loadRecap()
        // A refresh keeps the strip that is on screen if the new call fails:
        // last week's numbers do not stop being true because a pull dropped.
        if case .failed = newRecap, recap.value != nil { return }
        recap = newRecap
    }

    private func loadRecap() async -> CardState<MeRecapResponse> {
        guard let recapClient else { return .failed(message: "Not configured") }
        do {
            return .loaded(try await recapClient.recap(range: .week))
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    private func loadSummary() async -> CardState<HomeSummaryResponse> {
        do {
            return .loaded(try await homeClient.summary(period: .today))
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    private func loadToRevisit() async -> CardState<Int> {
        do {
            return .loaded(try await dailyReviewClient.fetchToday().memories.count)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    private func loadPending() async -> CardState<Int> {
        do {
            return .loaded(try await pendingClient.pending().pendingFiles)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}
