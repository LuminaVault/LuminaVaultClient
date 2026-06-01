// LuminaVaultClient/LuminaVaultClient/Features/Achievements/AchievementsSeenStore.swift
//
// Tracks which unlocked sub-achievements the user has already been shown a
// celebration for, so the in-app reveal fires exactly once per unlock. Backed
// by UserDefaults (a JSON Set<String> of sub keys).
//
// First-launch priming: the very first time we see a catalog we seed every
// already-unlocked sub as "seen" WITHOUT returning it, so opening the screen
// for the first time doesn't spray confetti over historical unlocks.

import Foundation
import LuminaVaultShared

struct AchievementsSeenStore: Sendable {
    private let defaults: UserDefaults
    private let seenKey = "achievements.seenUnlockedKeys"
    private let primedKey = "achievements.seenPrimed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var seen: Set<String> {
        guard let data = defaults.data(forKey: seenKey),
              let set = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return set
    }

    private func store(_ set: Set<String>) {
        guard let data = try? JSONEncoder().encode(set) else { return }
        defaults.set(data, forKey: seenKey)
    }

    private func markSeen(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        store(seen.union(keys))
    }

    /// Unlocked subs the user hasn't been celebrated for yet. On first ever
    /// call (catalog not yet primed) this seeds all current unlocks as seen
    /// and returns an empty array.
    mutating func newlyUnlocked(in response: AchievementsListResponse) -> [AchievementSub] {
        let unlocked = response.archetypes
            .flatMap(\.sub)
            .filter { $0.unlockedAt != nil }

        guard defaults.bool(forKey: primedKey) else {
            store(Set(unlocked.map(\.key)))
            defaults.set(true, forKey: primedKey)
            return []
        }

        let already = seen
        let fresh = unlocked.filter { !already.contains($0.key) }
        markSeen(fresh.map(\.key))
        return fresh
    }
}
