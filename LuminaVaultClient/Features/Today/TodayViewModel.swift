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
            let response = try await client.outputs(since: since, limit: 50)
            outputs = response.outputs.sorted { $0.createdAt > $1.createdAt }
            streakDays = response.streakDays
            activeRun = response.activeRun
            if let newest = outputs.first?.createdAt {
                lastSeenISO = ISO8601DateFormatter().string(from: newest)
            }
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
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
