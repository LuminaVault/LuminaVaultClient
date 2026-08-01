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

import AppIntents
import Foundation
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

/// Surfaces both intents as ready-made Shortcuts with spoken phrases.
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
            intent: AskLuminaIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask my brain in \(.applicationName)",
            ],
            shortTitle: "Ask",
            systemImageName: "brain.head.profile"
        )
    }
}
