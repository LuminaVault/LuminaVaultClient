// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizPrioritiesView.swift
//
// HER-100 step 2 — multi-select priority chip grid with optional
// free-text payload for the "other" chip.

import SwiftUI

struct SoulQuizPrioritiesView: View {
    @Bindable var state: SoulQuizState
    let onNext: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        SoulQuizStepScaffold(
            number: 2,
            title: "What matters most to you?",
            subtitle: "Pick as many as you want — Hermes will remember and surface what you care about."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                LVChipGrid(items: SoulPriority.allCases) { priority in
                    LVSelectionChip(
                        label: priority.label,
                        isSelected: state.answers.priorities.contains(priority)
                    ) {
                        toggle(priority)
                    }
                }
                if state.answers.priorities.contains(.other) {
                    TextField(
                        "What else?",
                        text: $state.answers.otherPriority,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                }
            }
        } footer: {
            LVButton("Next") { onNext() }
                .disabled(state.answers.priorities.isEmpty)
                .opacity(state.answers.priorities.isEmpty ? 0.5 : 1)
        }
    }

    private func toggle(_ priority: SoulPriority) {
        if state.answers.priorities.contains(priority) {
            state.answers.priorities.remove(priority)
        } else {
            state.answers.priorities.insert(priority)
        }
    }
}
