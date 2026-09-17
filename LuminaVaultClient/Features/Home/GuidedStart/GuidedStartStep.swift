// LuminaVaultClient/LuminaVaultClient/Features/Home/GuidedStart/GuidedStartStep.swift
//
// The three steps of "Get started with Hermie", per `docs/guided-start.md`.
//
// The contract doc is the cross-platform source of truth: iOS, web, and
// later Android ship the same ids, the same copy, and the same latches.
// The raw values are load-bearing three times over — they are the
// analytics `step` property, the `data-guide` spotlight target names, and
// the shared PostHog funnel's grouping key — so they are decoupled from
// the display copy on purpose. Changing a `title` is a copy edit;
// changing a `rawValue` breaks a dashboard on three platforms.
//
// Nothing here talks to the network or holds state. Completion is read
// out of a snapshot the caller already has; a client never latches these
// flags itself (see "Completion is the server's word" in the doc).

import Foundation
import LuminaVaultShared

// MARK: - Spotlight targets

/// Where a step points. The overlay/anchor plumbing that consumes these
/// is being designed in a parallel spike; this enum is the vocabulary it
/// will resolve against, and the raw values match the `data-guide` target
/// names the web uses.
enum GuidedTarget: String, Sendable, CaseIterable {
    case composer
    case sync
    case chat
}

// MARK: - Steps

/// The loop the wizard teaches: save a memory, let Hermes learn it, ask
/// about it. Declaration order is the loop order and `GuidedStartProgress`
/// depends on it.
enum GuidedStartStep: String, CaseIterable, Identifiable, Sendable {
    case saveMemory = "save_memory"
    case syncLearn = "sync_learn"
    case ask = "ask"

    var id: String { rawValue }

    /// The card row label.
    var title: String {
        switch self {
        case .saveMemory: "Save a memory"
        case .syncLearn:  "Sync & Learn"
        case .ask:        "Ask about it"
        }
    }

    /// What Hermie says while the step is open. Doubles as the accessible
    /// label on the speech bubble, so it reads as a full sentence.
    var hermieLine: String {
        switch self {
        case .saveMemory: "Type anything you want to remember, then Save."
        case .syncLearn:  "Now let me read it — tap Sync & Learn."
        case .ask:        "Ask me anything about what you just saved."
        }
    }

    var target: GuidedTarget {
        switch self {
        case .saveMemory: .composer
        case .syncLearn:  .sync
        case .ask:        .chat
        }
    }

    /// The server-owned latch that means this step actually happened.
    /// "Saved" on a client is not "saved" on the server — captures queue
    /// offline and drain later — so this is the only signal worth reading.
    func isComplete(in state: OnboardingStateDTO) -> Bool {
        switch self {
        case .saveMemory: state.firstCaptureCompleted
        case .syncLearn:  state.firstKBCompileCompleted
        case .ask:        state.firstQueryCompleted
        }
    }
}

// MARK: - Progress

/// The card's read of a snapshot: what is done, what is next, and whether
/// the whole loop is finished.
///
/// `next` is the first incomplete step in declaration order rather than
/// "the one after the last completed one", because latches can flip out
/// of order — a chat reply on the web latches `firstQueryCompleted`
/// without anything having been compiled here.
struct GuidedStartProgress: Equatable, Sendable {
    let completed: Set<GuidedStartStep>
    let next: GuidedStartStep?

    var isAllDone: Bool { next == nil }
    var completedCount: Int { completed.count }

    /// `nil` means "no snapshot in hand". It yields an empty progress so
    /// callers can compute without branching; whether to *render* on a
    /// missing snapshot is the visibility rule's job, not this type's.
    init(_ state: OnboardingStateDTO?) {
        guard let state else {
            completed = []
            next = GuidedStartStep.allCases.first
            return
        }
        completed = Set(GuidedStartStep.allCases.filter { $0.isComplete(in: state) })
        next = GuidedStartStep.allCases.first { !$0.isComplete(in: state) }
    }
}

// MARK: - Copy

/// Card chrome copy that is not attached to a single step. Kept beside
/// the steps so the whole contract's wording lives in one file.
enum GuidedStartCopy {
    static let headline = "Get started with Hermie"
    static let skip = "Skip"
    static let completion = "That's the whole loop. Everything you save, I learn."

    /// Shown instead of starting step 2 when there is nothing unprocessed
    /// in the vault. An empty compile returns early server-side and never
    /// latches, so starting the step would strand the user in a spotlight
    /// that can't finish.
    static let nothingPending = "Save something first — then I'll have something to learn."

    /// Shown when the dismiss PATCH fails and the card un-hides.
    static let dismissFailed = "Couldn't hide that just now — try again in a moment."

    static func progress(completed: Int) -> String {
        "\(completed) of \(GuidedStartStep.allCases.count)"
    }
}
