// LuminaVaultClient/LuminaVaultClient/Features/Community/HomeDailyPostViewModel.swift
//
// Home's "Today" row for the AI Daily Post. Asks `/me` first: when the board
// is off the row never appears. A 204 from `daily/today` (no post yet) and any
// failure both leave the row hidden — it is a doorway, not a status report.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class HomeDailyPostViewModel {
    private(set) var post: CommunityPostDTO?
    private(set) var isEnabled = false

    let client: any CommunityClientProtocol

    init(client: any CommunityClientProtocol) {
        self.client = client
    }

    var isHidden: Bool { !isEnabled || post == nil }

    func load() async {
        do {
            let me = try await client.me()
            isEnabled = me.enabled
            guard me.enabled else {
                post = nil
                return
            }
            post = try await client.dailyToday()
        } catch {
            // Keep whatever was showing on a cancelled refresh; hide on a
            // real failure rather than show a row that cannot open.
            guard !APIError.isBenignCancellation(error) else { return }
            if post == nil { isEnabled = false }
        }
    }
}
