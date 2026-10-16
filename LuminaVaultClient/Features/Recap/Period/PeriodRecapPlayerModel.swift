// LuminaVaultClient/LuminaVaultClient/Features/Recap/Period/PeriodRecapPlayerModel.swift
//
// The story player's state: one loaded recap, which card is showing, how far
// through it is, and whether it is held. Time only moves through
// `tick(_:)`, so the view drives it from a `.task` loop and tests drive it
// by hand.

import Foundation
import LuminaVaultShared
import Observation

@MainActor
@Observable
final class PeriodRecapPlayerModel {
    enum LoadState: Equatable {
        case loading
        case unavailable(PeriodRecapResponse)
        case ready(PeriodRecapResponse)
        case failed(String)
    }

    /// How long to wait before asking again for a themes card still being written.
    static let themesRetry: Duration = .seconds(6)

    private(set) var request: PeriodRecapRequest
    private(set) var state: LoadState = .loading
    private(set) var cards: [RecapCardKind] = []
    private(set) var index = 0
    private(set) var elapsed: Double = 0
    private(set) var isPaused = false
    private(set) var isFinished = false

    private let client: any PeriodRecapClientProtocol
    private let telemetry: any TelemetryProtocol
    private let sleep: @Sendable (Duration) async throws -> Void
    private var generation = 0

    init(
        client: any PeriodRecapClientProtocol,
        request: PeriodRecapRequest = .current(.year),
        telemetry: any TelemetryProtocol = NoopTelemetry(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.client = client
        self.request = request
        self.telemetry = telemetry
        self.sleep = sleep
    }

    var recap: PeriodRecapResponse? {
        if case let .ready(recap) = state { return recap }
        return nil
    }

    var current: RecapCardKind? {
        cards.indices.contains(index) ? cards[index] : nil
    }

    var duration: Double {
        current.map(PeriodRecapDeck.duration(of:)) ?? 0
    }

    /// 0…1 through the current card.
    var progress: Double {
        duration == 0 ? 0 : min(1, elapsed / duration)
    }

    /// 0…1 for segment `i` of the progress bar.
    func segmentProgress(_ i: Int) -> Double {
        if i < index { return 1 }
        if i > index { return 0 }
        return progress
    }

    // MARK: - Loading

    func select(_ newRequest: PeriodRecapRequest) async {
        request = newRequest
        await load()
    }

    func load() async {
        generation += 1
        let mine = generation
        let requested = request
        state = .loading
        do {
            let recap = try await client.periodRecap(requested)
            guard mine == generation else { return }
            guard recap.available else {
                cards = []
                state = .unavailable(recap)
                return
            }
            state = .ready(recap)
            start(PeriodRecapDeck.cards(for: recap))
            telemetry.track("recap_opened", properties: ["period": recap.period.rawValue])
            if recap.themes?.status == .pending {
                await refreshThemes(generation: mine)
            }
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation else { return }
            state = .failed("Couldn't load your recap.")
        }
    }

    /// One more ask for a `pending` themes card. Only the themes card is
    /// replaced, so the deck keeps its place.
    private func refreshThemes(generation mine: Int) async {
        do {
            try await sleep(Self.themesRetry)
            guard mine == generation, case let .ready(recap) = state else { return }
            let fresh = try await client.periodRecap(request)
            guard mine == generation, let themes = fresh.themes else { return }
            state = .ready(recap.replacingThemes(themes))
        } catch {
            // The counted fallback sentence is already on the card.
        }
    }

    // MARK: - Playback

    func tick(_ seconds: Double) {
        guard !isPaused, !isFinished, current != nil else { return }
        elapsed += seconds
        if elapsed >= duration { next() }
    }

    func next() {
        guard !isFinished, !cards.isEmpty else { return }
        if index < cards.count - 1 {
            show(index + 1)
        } else {
            // The summary waits for the viewer.
            elapsed = duration
            isFinished = true
            telemetry.track("recap_completed", properties: ["period": request.period.rawValue])
        }
    }

    /// Back one card, or to the start of the first.
    func previous() {
        isFinished = false
        if index > 0 {
            show(index - 1)
        } else {
            elapsed = 0
        }
    }

    func restart() {
        isFinished = false
        isPaused = false
        show(0)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    func recordShare() {
        telemetry.track("recap_shared", properties: ["period": request.period.rawValue])
    }

    private func start(_ deck: [RecapCardKind]) {
        cards = deck
        isFinished = false
        isPaused = false
        if deck.isEmpty { return }
        show(0)
    }

    private func show(_ i: Int) {
        index = i
        elapsed = 0
        telemetry.track("recap_card_viewed", properties: [
            "period": request.period.rawValue,
            "kind": cards[i].rawValue,
            "index": String(i),
        ])
    }
}

nonisolated extension PeriodRecapResponse {
    func replacingThemes(_ themes: RecapThemesCardDTO) -> PeriodRecapResponse {
        PeriodRecapResponse(
            period: period,
            year: year,
            month: month,
            start: start,
            end: end,
            timezone: timezone,
            isComplete: isComplete,
            available: available,
            unavailableReason: unavailableReason,
            order: order,
            captures: captures,
            peak: peak,
            rhythm: rhythm,
            topics: topics,
            chats: chats,
            skills: skills,
            streak: streak,
            achievements: achievements,
            themes: themes,
            shareText: shareText,
            generatedAt: generatedAt
        )
    }
}
