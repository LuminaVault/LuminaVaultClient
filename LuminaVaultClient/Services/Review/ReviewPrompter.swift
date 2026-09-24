// LuminaVaultClient/LuminaVaultClient/Services/Review/ReviewPrompter.swift
//
// Decides when the native App Store rating prompt may be requested. iOS
// still has the final say (it throttles to 3 per year and may show nothing),
// but asking at a bad moment wastes one of those three, so we only ask:
//
//   * after the 3rd success moment (a server-confirmed save to the vault),
//   * never in the first session (first seen at least 24 h ago),
//   * at most once per 120 days, counting the post-purchase prompt too,
//   * never when "Ask me to rate LuminaVault" is off in Settings → About.
//
// After a prompt the success count resets and `lastPromptAt` is recorded.
// State is local `UserDefaults` only; nothing crosses the wire.
//
// This type only decides. The request itself has to come from a view that
// is on screen — see `ReviewPromptPresenter`, attached to `MainTabView`.

import Foundation
import Observation

@MainActor
@Observable
final class ReviewPrompter {
    static let shared = ReviewPrompter()

    enum Keys {
        static let successCount = "lv.review.successCount"
        static let firstSeenAt = "lv.review.firstSeenAt"
        static let lastPromptAt = "lv.review.lastPromptAt"
        /// Read directly by the Settings toggle via `@AppStorage`.
        static let promptsEnabled = "lv.review.promptsEnabled"
    }

    static let successThreshold = 3
    static let minimumTimeSinceFirstSeen: TimeInterval = 24 * 60 * 60
    static let cooldown: TimeInterval = 120 * 24 * 60 * 60

    /// True once a success moment has made the prompt due. The presenter
    /// watches this and asks `consumePendingPrompt()` before requesting.
    private(set) var hasPendingPrompt = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if defaults.object(forKey: Keys.firstSeenAt) == nil {
            defaults.set(now(), forKey: Keys.firstSeenAt)
        }
    }

    // MARK: - State

    /// Defaults to on. Stored rather than cached so the `@AppStorage` toggle
    /// in About and this type can never disagree.
    var promptsEnabled: Bool {
        get { defaults.object(forKey: Keys.promptsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.promptsEnabled) }
    }

    var successCount: Int { defaults.integer(forKey: Keys.successCount) }
    var firstSeenAt: Date? { defaults.object(forKey: Keys.firstSeenAt) as? Date }
    var lastPromptAt: Date? { defaults.object(forKey: Keys.lastPromptAt) as? Date }

    // MARK: - Events

    /// A server-confirmed save to the vault. Callers own "once per item" —
    /// the capture drainer only calls this after the row is deleted, so a
    /// retried row is counted on the attempt that finally lands.
    func recordSuccess() {
        defaults.set(successCount + 1, forKey: Keys.successCount)
        if isPromptDue { hasPendingPrompt = true }
    }

    /// Called by the presenter right before `requestReview()`. Re-checks
    /// eligibility (the toggle may have flipped since the success moment)
    /// and records the prompt. Returns whether to go ahead.
    func consumePendingPrompt() -> Bool {
        guard hasPendingPrompt else { return false }
        hasPendingPrompt = false
        guard isPromptDue else { return false }
        recordPrompt()
        return true
    }

    /// HER-298 post-purchase prompt. Skips the success threshold and the
    /// first-session guard (a purchase is its own strong moment) but honours
    /// the opt-out and the cooldown, and counts as a prompt for the latter.
    func consumePurchasePrompt() -> Bool {
        guard promptsEnabled, isOutsideCooldown else { return false }
        recordPrompt()
        return true
    }

    // MARK: - Rules

    var isPromptDue: Bool {
        guard promptsEnabled, successCount >= Self.successThreshold, isOutsideCooldown else { return false }
        guard let firstSeenAt else { return false }
        return now().timeIntervalSince(firstSeenAt) >= Self.minimumTimeSinceFirstSeen
    }

    private var isOutsideCooldown: Bool {
        guard let lastPromptAt else { return true }
        return now().timeIntervalSince(lastPromptAt) >= Self.cooldown
    }

    private func recordPrompt() {
        hasPendingPrompt = false
        defaults.set(0, forKey: Keys.successCount)
        defaults.set(now(), forKey: Keys.lastPromptAt)
    }
}
