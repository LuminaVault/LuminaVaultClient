// LuminaVaultClient/LuminaVaultClient/Services/Review/ReviewPromptPresenter.swift
//
// `requestReview()` only works from a view that is on screen, but the
// success moments that make a prompt due mostly happen in the background
// (`CaptureDrainer`). So the request is made here, from the app shell
// (`MainTabView`), once the prompt is due AND the app is active, after a
// short beat so it doesn't land on top of whatever just happened.
//
// `.task(id:)` cancels the pending sleep if the app leaves `.active`
// before it fires; the prompt stays pending for the next activation.

import StoreKit
import SwiftUI

private struct ReviewPromptPresenter: ViewModifier {
    let prompter: ReviewPrompter

    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: prompter.hasPendingPrompt && scenePhase == .active) {
                guard prompter.hasPendingPrompt, scenePhase == .active else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, prompter.consumePendingPrompt() else { return }
                requestReview()
            }
    }
}

extension View {
    /// Attach once, at a root view that is always on screen in the main app.
    func reviewPromptPresenter(_ prompter: ReviewPrompter = .shared) -> some View {
        modifier(ReviewPromptPresenter(prompter: prompter))
    }
}
