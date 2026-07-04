// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizStyleView.swift
//
// HER-100 step 3 — three quick style controls: bullets vs prose,
// short vs long, emojis y/n.

import LuminaVaultShared
import SwiftUI

struct SoulQuizStyleView: View {
    @Bindable var state: SoulQuizState
    let onNext: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        SoulQuizStepScaffold(
            number: 3,
            title: "How should replies look?",
            subtitle: "Pick the shape of replies you like to read."
        ) {
            VStack(alignment: .leading, spacing: 24) {
                row(title: "Format") {
                    LVChipGrid(items: SoulFormat.allCases) { format in
                        LVSelectionChip(
                            label: format.label,
                            isSelected: state.answers.format == format
                        ) { state.answers.format = format }
                    }
                }
                row(title: "Length") {
                    LVChipGrid(items: SoulLength.allCases) { length in
                        LVSelectionChip(
                            label: length.label,
                            isSelected: state.answers.length == length
                        ) { state.answers.length = length }
                    }
                }
                row(title: "Emojis") {
                    Toggle(isOn: $state.answers.emojis) {
                        Text(state.answers.emojis ? "Yes, sprinkle them in" : "No, plain text only")
                            .font(.subheadline)
                            .foregroundStyle(palette.textPrimary)
                    }
                    .tint(palette.accent)
                }
            }
        } footer: {
            LVButton("Next") { onNext() }
        }
    }

    @ViewBuilder
    private func row<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            content()
        }
    }
}
