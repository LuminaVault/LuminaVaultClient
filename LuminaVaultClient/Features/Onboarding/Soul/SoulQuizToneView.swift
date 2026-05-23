// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizToneView.swift
//
// HER-100 step 1 — single-select tone chip grid.

import SwiftUI

struct SoulQuizToneView: View {
    @Bindable var state: SoulQuizState
    let onNext: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        SoulQuizStepScaffold(
            number: 1,
            title: "How should Hermes speak to you?",
            subtitle: "Pick the tone Lumina will mirror in every reply."
        ) {
            LVChipGrid(items: SoulTone.allCases) { tone in
                LVSelectionChip(
                    label: tone.label,
                    isSelected: state.answers.tone == tone
                ) {
                    state.answers.tone = tone
                }
            }
        } footer: {
            LVButton("Next") { onNext() }
                .disabled(state.answers.tone == nil)
                .opacity(state.answers.tone == nil ? 0.5 : 1)
        }
    }
}
