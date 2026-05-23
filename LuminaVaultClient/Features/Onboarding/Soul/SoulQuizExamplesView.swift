// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizExamplesView.swift
//
// HER-100 step 4 — paste 1-3 voice samples so Hermes mirrors voice.
// Empty samples are allowed (skip-friendly) but the next button is
// disabled until at least one non-empty sample exists, matching the
// "1-3 messages" acceptance criterion.

import SwiftUI

struct SoulQuizExamplesView: View {
    @Bindable var state: SoulQuizState
    let onNext: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        SoulQuizStepScaffold(
            number: 4,
            title: "How do you talk?",
            subtitle: "Paste 1–3 messages you've sent recently. Hermes will mirror your voice."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(0..<3, id: \.self) { index in
                    sampleEditor(index: index)
                }
            }
        } footer: {
            LVButton("Next") { onNext() }
                .disabled(!hasAtLeastOneSample)
                .opacity(hasAtLeastOneSample ? 1 : 0.5)
        }
    }

    private var hasAtLeastOneSample: Bool {
        state.answers.voiceSamples.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @ViewBuilder
    private func sampleEditor(index: Int) -> some View {
        let binding = Binding(
            get: {
                state.answers.voiceSamples.indices.contains(index)
                    ? state.answers.voiceSamples[index]
                    : ""
            },
            set: { newValue in
                while state.answers.voiceSamples.count <= index {
                    state.answers.voiceSamples.append("")
                }
                state.answers.voiceSamples[index] = newValue
            }
        )
        VStack(alignment: .leading, spacing: 6) {
            Text("Sample \(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            TextEditor(text: binding)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(palette.surfaceStroke, lineWidth: 1)
                }
        }
    }
}
