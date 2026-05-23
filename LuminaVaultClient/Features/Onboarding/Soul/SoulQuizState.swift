// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizState.swift
//
// HER-100 — `@Observable` view-model holding the in-progress quiz
// answers and active step. Reads + writes a JSON snapshot to
// `UserDefaults` on every mutation so the resumable acceptance
// criterion ("if user kills app on step 3, returns to step 3") holds
// without needing to round-trip per-step progress through the server.
// The server only tracks the terminal `soulConfiguredCompleted` flag.

import Foundation
import Observation

/// HER-100 — discrete step the quiz is currently parked on. Maps 1:1
/// to the views pushed onto the `NavigationStack`. `done` signals the
/// container view to dismiss the quiz; the app gate then routes the
/// user back to `MainTabView`.
enum SoulQuizStep: String, Codable, Hashable, CaseIterable, Sendable {
    case tone
    case priorities
    case style
    case examples
    case confirm
    case done

    var next: SoulQuizStep {
        switch self {
        case .tone: .priorities
        case .priorities: .style
        case .style: .examples
        case .examples: .confirm
        case .confirm: .done
        case .done: .done
        }
    }
}

@Observable
@MainActor
final class SoulQuizState {
    private(set) var step: SoulQuizStep
    var answers: SoulQuizAnswers {
        didSet { persist() }
    }
    /// `nil` while idle; set to a user-facing string on the confirm step
    /// when the server save fails so the view can surface a retry CTA
    /// without owning its own error state.
    var saveError: String?
    /// `true` while the PUT/PATCH chain on the confirm step is in flight.
    /// Drives the confirm button's progress indicator and disables the
    /// inline `TextEditor` to prevent further edits mid-save.
    private(set) var isSaving = false

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        userId: UUID?,
        defaults: UserDefaults = .standard,
        clock: @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        // Scope the persisted snapshot by user so re-signing in as a
        // different account doesn't resume the previous user's quiz.
        let scope = userId?.uuidString ?? "anon"
        self.storageKey = "her100.soulQuiz.\(scope)"
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.step = saved.step
            self.answers = saved.answers
        } else {
            self.step = .tone
            self.answers = SoulQuizAnswers()
        }
    }

    /// Advance to the next step in the ladder. Idempotent for `done`.
    func advance() {
        step = step.next
        persist()
    }

    /// Reset the active step to a specific case — used by the confirm
    /// step's "Edit" affordances that jump back to a particular screen.
    func goTo(_ newStep: SoulQuizStep) {
        step = newStep
        persist()
    }

    /// Set in-flight + clear any stale error before kicking off a save.
    func beginSave() {
        isSaving = true
        saveError = nil
    }

    /// Restore idle state after a save (success or failure). On failure,
    /// pass the user-facing message; on success, pass `nil`.
    func endSave(error: String?) {
        isSaving = false
        saveError = error
    }

    /// Wipe the persisted snapshot on successful save so a later
    /// "redo the quiz" flow (Settings → Edit SOUL.md) doesn't resurrect
    /// stale answers.
    func clearPersistence() {
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        let snapshot = Snapshot(step: step, answers: answers)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private struct Snapshot: Codable {
        var step: SoulQuizStep
        var answers: SoulQuizAnswers
    }
}
