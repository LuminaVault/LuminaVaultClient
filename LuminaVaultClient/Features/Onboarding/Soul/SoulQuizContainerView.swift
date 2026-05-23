// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizContainerView.swift
//
// HER-100 — root container for the SOUL.md 5-step onboarding quiz.
// Owns the `NavigationStack` path and resumes on whatever step the
// persisted snapshot last parked the user on. Drives transitions by
// observing `state.step` so a single source of truth (the view-model)
// dictates which view renders.

import SwiftUI
import LuminaVaultShared

struct SoulQuizContainerView: View {
    @State private var state: SoulQuizState
    @State private var path = NavigationPath()

    private let soulClient: any SoulClientProtocol
    private let onboardingClient: any OnboardingClientProtocol
    private let onCompleted: (OnboardingStateDTO) -> Void

    init(
        state: SoulQuizState,
        soulClient: any SoulClientProtocol,
        onboardingClient: any OnboardingClientProtocol,
        onCompleted: @escaping (OnboardingStateDTO) -> Void
    ) {
        self._state = State(initialValue: state)
        self.soulClient = soulClient
        self.onboardingClient = onboardingClient
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationStack(path: $path) {
            // Step 1 is the root — it's never pushed, only popped back to.
            SoulQuizToneView(state: state, onNext: pushNext)
                .navigationDestination(for: SoulQuizStep.self) { step in
                    destination(for: step)
                }
        }
        .lvBackground()
        .onAppear { syncPathToState() }
    }

    @ViewBuilder
    private func destination(for step: SoulQuizStep) -> some View {
        switch step {
        case .tone:
            // `.tone` is the root, never pushed.
            EmptyView()
        case .priorities:
            SoulQuizPrioritiesView(state: state, onNext: pushNext)
        case .style:
            SoulQuizStyleView(state: state, onNext: pushNext)
        case .examples:
            SoulQuizExamplesView(state: state, onNext: pushNext)
        case .confirm:
            SoulQuizConfirmView(
                state: state,
                soulClient: soulClient,
                onboardingClient: onboardingClient,
                onSaved: onCompleted
            )
        case .done:
            EmptyView()
        }
    }

    /// Persist the next step + push the corresponding destination so a
    /// back-swipe pops the user to the previous answer for editing.
    private func pushNext() {
        state.advance()
        path.append(state.step)
    }

    /// Resume-on-launch: if the persisted state put the user past step 1,
    /// rebuild the path so the right view is on top of the stack.
    private func syncPathToState() {
        var rebuilt = NavigationPath()
        for case let step in [SoulQuizStep.priorities, .style, .examples, .confirm]
        where stepOrder(step) <= stepOrder(state.step) {
            rebuilt.append(step)
        }
        path = rebuilt
    }

    private func stepOrder(_ step: SoulQuizStep) -> Int {
        switch step {
        case .tone: 0
        case .priorities: 1
        case .style: 2
        case .examples: 3
        case .confirm: 4
        case .done: 5
        }
    }
}
