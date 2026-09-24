// LuminaVaultClient/LuminaVaultClient/Services/Intents/LuminaAppIntents.swift
//
// Siri / Shortcuts / Spotlight entry points.
//
// Both intents reuse the paths the in-app UI already uses rather than talking
// to the network directly:
//
//   * Capture → `CaptureQueue.enqueue` + `CaptureDrainer.kick`, the same
//     offline-first queue `TextCaptureViewModel.save()` writes to. A capture
//     made with no connectivity is persisted and drains later, exactly like one
//     typed in the app.
//   * Ask → opens the app on the Think tab with the question pre-filled.
//     Deliberately NOT answered inline: a chat turn needs auth, streaming, and
//     the routing stack, none of which belong in an intent's short execution
//     budget.
//   * Watch this → the same two calls the chat's standing-task card makes
//     (`POST /v1/jobs/detect`, then `POST /v1/jobs`), answered inline: two
//     short requests fit the budget, and the answer is the point.

import AppIntents
import Foundation
import LuminaVaultShared
import SwiftUI

/// Capture a thought without opening the app.
struct CaptureToLuminaIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture to LuminaVault"
    static var description = IntentDescription(
        "Save a note straight to your vault. Works offline — it syncs when you're back online.",
        categoryName: "Capture"
    )
    /// Runs without foregrounding the app: the whole point is a frictionless
    /// capture from Siri or the lock screen.
    static var openAppWhenRun = false

    @Parameter(title: "Note", requestValueDialog: "What do you want to remember?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return .result(dialog: "Nothing to save.")
        }

        // Own container: intents run in the app process but outside the
        // SwiftUI lifecycle, so there is no AppState to borrow a queue from.
        let container = try CaptureQueue.makeProductionContainer()
        let queue = CaptureQueue(container: container)
        try await queue.enqueue(CaptureSnapshot.text(body: body))

        return .result(dialog: "Saved to your vault.")
    }
}

/// Jump into a chat with the question already typed.
struct AskLuminaIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask my brain"
    static var description = IntentDescription(
        "Open LuminaVault and ask your second brain a question.",
        categoryName: "Chat"
    )
    // Answering needs auth + streaming + routing; hand off to the app instead
    // of trying to do it inside the intent's execution budget.
    static var openAppWhenRun = true

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            PendingIntentRequest.shared.askQuestion = trimmed
        }
        return .result()
    }
}

/// Muse Stage D — "watch this": set up a standing task by voice.
///
/// "Hey Siri, watch this in LuminaVault" → "What should I watch?" → "check
/// the weather each morning and tell me when it's dry five days running".
/// The text goes through the same classifier as a chat turn; a job is
/// created straight away (saying it *is* the confirmation), anything else is
/// declined in words rather than silently turned into a chat.
struct WatchThisIntent: AppIntent {
    static let title: LocalizedStringResource = "Watch this"
    static let description = IntentDescription(
        "Ask Hermie to keep an eye on something on a schedule and ping you when it matters.",
        categoryName: "Chat"
    )
    static let openAppWhenRun = false

    @Parameter(title: "What to watch", requestValueDialog: "What should I watch?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Own client off the keychain, like the lock-screen approval path:
        // an intent can run with no SwiftUI scene and so no `AppState`.
        let client = JobsHTTPClient(client: HermesApprovalResponder.backgroundHTTPClient())
        let outcome = await WatchThisFlow(client: client).run(text)
        return .result(dialog: IntentDialog(stringLiteral: WatchThisFlow.dialog(for: outcome)))
    }
}

/// The intent's work, separated from `AppIntent` so it can be tested with a
/// stubbed `JobsClientProtocol`.
struct WatchThisFlow {
    enum Outcome: Equatable {
        case created(title: String, sentence: String, scheduleHuman: String?)
        case notAJob
        case empty
        case signedOut
        case failed
    }

    let client: any JobsClientProtocol

    func run(_ raw: String) async -> Outcome {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        do {
            let proposal = try await client.detect(text: text)
            // A job with no schedule or no spec cannot be created — the chat
            // card treats it the same way (`createProposedJob`).
            guard proposal.isJob, let cron = proposal.cron, let spec = proposal.spec else {
                return .notAJob
            }
            let title = proposal.title ?? "Standing task"
            _ = try await client.create(JobCreateRequest(
                title: title,
                cron: cron,
                domain: proposal.domain,
                spec: spec,
                spaceId: nil
            ))
            return .created(
                title: title,
                sentence: StandingTaskConfirmation.text(
                    title: proposal.title,
                    spec: proposal.spec,
                    scheduleHuman: proposal.scheduleHuman
                ),
                scheduleHuman: proposal.scheduleHuman
            )
        } catch APIError.unauthorized {
            return .signedOut
        } catch {
            return .failed
        }
    }

    /// What Siri says. The created case is the chat's own confirmation
    /// sentence plus the schedule, unless the sentence already said it.
    static func dialog(for outcome: Outcome) -> String {
        switch outcome {
        case let .created(_, sentence, scheduleHuman):
            guard let schedule = scheduleHuman?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !schedule.isEmpty,
                  !sentence.localizedCaseInsensitiveContains(schedule)
            else { return sentence }
            return "\(sentence) \(schedule)."
        case .notAJob:
            return "That doesn't sound like something to watch on a schedule. Try something like \"every morning, check the weather\"."
        case .empty:
            return "Tell me what to watch."
        case .signedOut:
            return "Open LuminaVault and sign in first."
        case .failed:
            return "I couldn't set that up just now. Try again in a moment."
        }
    }
}

/// Hand-off slot between an intent and the SwiftUI tree.
///
/// `openAppWhenRun` launches the app but gives the intent no way to pass a
/// payload into the view hierarchy, so the request is parked here and consumed
/// once on the next render.
@MainActor
@Observable
final class PendingIntentRequest {
    static let shared = PendingIntentRequest()

    /// Set by `AskLuminaIntent`, consumed by the Think tab.
    var askQuestion: String?

    private init() {}

    /// Reads and clears in one step so a question is never replayed on a later
    /// launch.
    func consumeAskQuestion() -> String? {
        defer { askQuestion = nil }
        return askQuestion
    }
}

/// Surfaces the intents as ready-made Shortcuts with spoken phrases.
///
/// `applicationName` resolves to the app's display name, so the phrases read
/// naturally ("Capture to LuminaVault") without hardcoding the brand.
struct LuminaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureToLuminaIntent(),
            phrases: [
                "Capture to \(.applicationName)",
                "Save a note in \(.applicationName)",
                "Remember this in \(.applicationName)",
            ],
            shortTitle: "Capture",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SaveAppleNoteIntent(),
            phrases: [
                "Save a note to \(.applicationName)",
                "Copy my notes to \(.applicationName)",
            ],
            shortTitle: "Save Note",
            systemImageName: "note.text"
        )
        AppShortcut(
            intent: AskLuminaIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask my brain in \(.applicationName)",
            ],
            shortTitle: "Ask",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: WatchThisIntent(),
            phrases: [
                "Watch this in \(.applicationName)",
                "Keep an eye on something in \(.applicationName)",
                "Set up a standing task in \(.applicationName)",
            ],
            shortTitle: "Watch This",
            systemImageName: "binoculars"
        )
    }
}
