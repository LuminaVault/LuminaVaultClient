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
        /// Memories the resurface queue says are worth seeing again.
        case dailyReview(Int)
    }

    /// Two tiles off one call: the summary endpoint answers both, so they
    /// settle together and fail together.
    private(set) var memoriesToday: CardState<Int> = .loading
    private(set) var streakDays: CardState<Int> = .loading
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

    /// The resurface queue's length, live: answering the Home card takes
    /// one off this count straight away rather than at the next refresh.
    var toRevisit: CardState<Int> {
        guard let resurface else { return .failed(message: "Not configured") }
        switch resurface.phase {
        case .loading: return .loading
        case .loaded: return .loaded(resurface.items.count)
        case .failed(let message): return .failed(message: message)
        }
    }

    var recommendation: Recommendation? {
        if let pending = pendingFiles.value, pending > 0 { return .syncAndLearn(pending) }
        if let revisit = toRevisit.value, revisit > 0 { return .dailyReview(revisit) }
        return nil
    }

    private let homeClient: any HomeSummaryClientProtocol
    /// The "to revisit" queue behind the tile, the Home card and the Daily
    /// review list. Nil leaves all three off.
    let resurface: ResurfaceQueueViewModel?
    private let pendingClient: any KBCompileClientProtocol
    /// Nil leaves the week strip off entirely — previews and snapshot suites
    /// that predate it render Home exactly as before.
    private let recapClient: (any RecapClientProtocol)?
    /// "What I learned this week" — behind the "Confirm what I learned" row
    /// and the sheet it opens. Nil leaves the row off, as above.
    let learned: LearnedThisWeekViewModel?

    /// Unconfirmed things Lumina learned, live: answering one in the sheet
    /// takes it off the row at once. Zero hides the row.
    var learnedCount: Int {
        guard let learned, learned.phase == .loaded else { return 0 }
        return learned.count
    }

    /// Today's brief — behind the "Your brief" row and the sheet it opens.
    /// Nil leaves the row off, as above.
    let brief: BriefViewModel?
    private let calendar: Calendar

    /// The cards left in today's brief, while it is worth a row: before
    /// noon, local time, and only once the brief exists. Nil hides the row.
    /// Live, like `learnedCount`: a dismiss in the sheet takes one off.
    func briefCardCount(at now: Date) -> Int? {
        guard let brief, brief.phase == .loaded, brief.brief != nil, !brief.cards.isEmpty else { return nil }
        guard calendar.component(.hour, from: now) < Self.briefRowCutoffHour else { return nil }
        return brief.count
    }

    /// The row goes at 12:00: by the afternoon a morning brief is old news.
    nonisolated static let briefRowCutoffHour = 12

    init(
        homeClient: any HomeSummaryClientProtocol,
        resurface: ResurfaceQueueViewModel?,
        pendingClient: any KBCompileClientProtocol,
        recapClient: (any RecapClientProtocol)? = nil,
        learned: LearnedThisWeekViewModel? = nil,
        brief: BriefViewModel? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.homeClient = homeClient
        self.resurface = resurface
        self.pendingClient = pendingClient
        self.recapClient = recapClient
        self.learned = learned
        self.brief = brief
        self.calendar = calendar
        recap = recapClient == nil ? .failed(message: "Not configured") : .loading
    }

    func load() async {
        async let summaryState = loadSummary()
        async let pendingState = loadPending()
        // Its own call alongside the two above rather than a third `async
        // let`: the queue settles its own state, and the tile reads it live.
        async let revisitLoaded: Void = loadResurface()
        let (summary, pending, _) = await (summaryState, pendingState, revisitLoaded)

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
        pendingFiles = pending

        // After the tiles rather than beside them: the strip sits below them,
        // so it settling a beat later is invisible.
        let newRecap = await loadRecap()
        // A refresh keeps the strip that is on screen if the new call fails:
        // last week's numbers do not stop being true because a pull dropped.
        if !(newRecap.isFailed && recap.value != nil) {
            recap = newRecap
        }

        // Sequenced after the recap, not a fourth `async let` beside the
        // three above: the row sits further down still, and it keeps its own
        // state (a failed refresh leaves what is on screen).
        await learned?.load()

        // Last, for the same reason: one more `async let` up top crashed the
        // runtime before (see the recap above). Home only needs the count,
        // so the commitments behind Open loops wait for the sheet.
        await brief?.load(includeCommitments: false)
    }

    /// The rows a sheet presented outside Home can change — "What I
    /// learned" and the brief, opened from a deep link on their own view
    /// models. Re-read when such a sheet closes; the tiles are untouched.
    func refreshSheetBackedRows() async {
        await learned?.load()
        await brief?.load(includeCommitments: false)
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

    private func loadResurface() async {
        await resurface?.load()
    }

    private func loadPending() async -> CardState<Int> {
        do {
            return .loaded(try await pendingClient.pending().pendingFiles)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}
