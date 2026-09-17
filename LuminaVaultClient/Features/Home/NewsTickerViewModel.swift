// LuminaVaultClient/LuminaVaultClient/Features/Home/NewsTickerViewModel.swift
//
// The breaking-news strip under the glance row, for the first-party
// news-ticker plugin. Cache first for an instant paint, then the network,
// written through. Not installed (404) or switched off (409) hide the strip;
// a failed refresh keeps what is on screen and says it is old.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class NewsTickerViewModel {
    typealias State = HomeGlanceViewModel.CardState<[NewsTickerItemDTO]>

    private(set) var state: State = .loading
    /// False once the server said the plugin is not installed or is off.
    private(set) var installed = true
    private(set) var isStale = false
    private(set) var lastFetchedAt: Date?

    private let client: any NewsTickerClientProtocol
    private let store: NewsTickerLocalStore?
    private let limit: Int
    private var hasLoadedCache = false

    init(client: any NewsTickerClientProtocol, store: NewsTickerLocalStore?, limit: Int = 20) {
        self.client = client
        self.store = store
        self.limit = limit
    }

    var items: [NewsTickerItemDTO] { state.value ?? [] }

    /// Nothing to show: not installed, off, or empty with no cache.
    var isHidden: Bool {
        if !installed { return true }
        if case .loading = state { return false }
        return items.isEmpty
    }

    func loadFromCache() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        guard let snapshot = try? store?.load(), !snapshot.items.isEmpty else { return }
        state = .loaded(snapshot.items)
        isStale = true
        lastFetchedAt = snapshot.fetchedAt
    }

    func refresh() async {
        do {
            let response = try await client.ticker(limit: limit)
            installed = true
            state = .loaded(response.items)
            isStale = response.stale
            lastFetchedAt = Date()
            try? store?.replace(with: response.items, stale: response.stale, fetchedAt: lastFetchedAt ?? Date())
        } catch APIError.httpError(let code, _) where code == 404 || code == 409 {
            installed = false
            state = .loaded([])
            try? store?.replace(with: [], stale: false, fetchedAt: Date())
        } catch {
            // Keep the cached strip and say it is old rather than blank it.
            if case .loaded = state {
                isStale = true
            } else {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func refreshIfStale(maxAge: TimeInterval) async {
        if let lastFetchedAt, Date().timeIntervalSince(lastFetchedAt) < maxAge, !isStale { return }
        await refresh()
    }
}
