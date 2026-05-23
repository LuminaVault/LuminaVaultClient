// LuminaVaultClient/LuminaVaultClient/Features/DailyReview/DailyReviewViewModel.swift
//
// HER-154 scaffold — drives the daily review surface. Pull-to-refresh
// triggers `refresh()`; first appear triggers `loadIfNeeded()` (no-op
// if already loaded).
//
// Phase machine: empty → loading → loaded(digest) | failed(message).
// Mascot state: idle when empty/loaded, thinking when loading.
import Foundation

@Observable
@MainActor
final class DailyReviewViewModel {
    enum Phase: Equatable, Sendable {
        case empty
        case loading
        case loaded(DailyReviewDigest)
        case failed(message: String)
    }

    var phase: Phase = .empty

    private let client: any DailyReviewClientProtocol

    init(client: any DailyReviewClientProtocol) {
        self.client = client
    }

    var mascotState: HermieMascotState {
        switch phase {
        case .loading: .thinking
        case .loaded: .happy
        case .empty, .failed: .idle
        }
    }

    /// First-appear load. Honors any already-loaded digest so pulling
    /// the view in/out (e.g. tab switch) doesn't trigger redundant
    /// fetches.
    func loadIfNeeded() async {
        if case .loaded = phase { return }
        await fetch()
    }

    /// Pull-to-refresh handler. Always re-fetches; preserves prior data
    /// in `phase` only on success (a refresh failure surfaces the error
    /// but doesn't blank the screen if a previous load succeeded).
    func refresh() async {
        await fetch(preservePriorOnFailure: true)
    }

    private func fetch(preservePriorOnFailure: Bool = false) async {
        let priorLoaded: DailyReviewDigest? = {
            if case let .loaded(d) = phase { return d }
            return nil
        }()
        if priorLoaded == nil { phase = .loading }
        do {
            let digest = try await client.fetchToday()
            phase = .loaded(digest)
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            if preservePriorOnFailure, let priorLoaded {
                phase = .loaded(priorLoaded)
            } else {
                phase = .failed(message: message)
            }
        }
    }
}
