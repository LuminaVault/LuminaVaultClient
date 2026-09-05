// LuminaVaultClient/LuminaVaultClient/Features/Today/TodayViewModel.swift
//
// HER-177 — Today tab. Pulls from GET /v1/skills/outputs since the
// last seen ISO timestamp. Empty until SkillRunner dispatches outputs
// (HER-169 server work).

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class TodayViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var state: LoadState = .loading
    var outputs: [SkillOutputDTO] = []
    var streakDays: Int = 0
    var activeRun: Bool = false
    var highlightedOutputID: UUID?
    /// Phase 2 — the server's `before` cursor for the page behind the one on
    /// screen. `nil` means there is nothing older to fetch.
    private(set) var nextCursor: String?
    private(set) var isLoadingMore = false

    private let client: TodayClientProtocol
    private let lastSeenKey = "lv.today.lastSeenISO"

    init(client: TodayClientProtocol) {
        self.client = client
    }

    private var lastSeenISO: String {
        get { UserDefaults.standard.string(forKey: lastSeenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: lastSeenKey) }
    }

    var mascotState: HermieMascotState {
        activeRun ? .thinking : .idle
    }

    func refresh() async {
        state = .loading
        do {
            let since = ISO8601DateFormatter().date(from: lastSeenISO)
            let response = try await client.outputs(since: since, before: nil, limit: 50)
            outputs = response.outputs.sorted { $0.createdAt > $1.createdAt }
            streakDays = response.streakDays
            activeRun = response.activeRun
            nextCursor = response.nextCursor
            if let newest = outputs.first?.createdAt {
                lastSeenISO = ISO8601DateFormatter().string(from: newest)
            }
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// Fetches the page behind the oldest row on screen. A no-op once the
    /// server stops handing back a cursor, which it does as soon as a page
    /// comes back short — only a full page can have more behind it.
    func loadMore() async {
        guard !isLoadingMore, let cursor = nextCursor,
              let before = ISO8601DateFormatter().date(from: cursor)
        else {
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await client.outputs(since: nil, before: before, limit: 50)
            // Older rows only; the cursor is an exclusive bound but a
            // concurrent write could still overlap.
            let known = Set(outputs.map(\.id))
            outputs += response.outputs.filter { !known.contains($0.id) }
            outputs.sort { $0.createdAt > $1.createdAt }
            nextCursor = response.nextCursor
        } catch {
            // Paging failure is not worth blanking the feed for — the rows
            // already on screen are still valid.
            nextCursor = nil
        }
    }

    func celebrate(highlightOutputID: UUID?) {
        highlightedOutputID = highlightOutputID
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load today's feed."
            }
        }
        return "Couldn't load today's feed."
    }
}
