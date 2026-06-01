// LuminaVaultClient/LuminaVaultClient/Features/Achievements/AchievementsViewModel.swift
//
// Drives the Achievements screen. Loads the catalog+progress and the recent
// unlocks in parallel, surfacing each independently so one failure doesn't
// blank the screen. After the catalog loads it diffs against the seen-store to
// queue any freshly-unlocked badges for the celebration overlay.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class AchievementsViewModel {
    enum CardState<T: Sendable>: Sendable {
        case loading
        case loaded(T)
        case failed(message: String)

        var value: T? {
            if case .loaded(let v) = self { return v }
            return nil
        }
    }

    var list: CardState<AchievementsListResponse> = .loading
    var recent: CardState<AchievementsRecentResponse> = .loading
    /// Freshly-unlocked subs awaiting the celebration overlay. Drained by the
    /// view via `dismissCelebrations()` once shown.
    var pendingCelebrations: [AchievementSub] = []

    private let client: AchievementsClientProtocol
    private var seenStore: AchievementsSeenStore

    init(client: AchievementsClientProtocol, seenStore: AchievementsSeenStore = AchievementsSeenStore()) {
        self.client = client
        self.seenStore = seenStore
    }

    func refresh() async {
        list = .loading
        recent = .loading
        async let listTask: Void = loadList()
        async let recentTask: Void = loadRecent()
        _ = await (listTask, recentTask)
    }

    func dismissCelebrations() {
        pendingCelebrations = []
    }

    private func loadList() async {
        do {
            let response = try await client.list()
            list = .loaded(response)
            let fresh = seenStore.newlyUnlocked(in: response)
            if !fresh.isEmpty { pendingCelebrations = fresh }
        } catch {
            list = .failed(message: friendlyMessage(error))
        }
    }

    private func loadRecent() async {
        do {
            recent = .loaded(try await client.recent(limit: 10))
        } catch {
            recent = .failed(message: friendlyMessage(error))
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load achievements."
            }
        }
        return "Couldn't load achievements."
    }
}
