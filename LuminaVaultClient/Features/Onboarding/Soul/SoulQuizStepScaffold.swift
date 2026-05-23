// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulQuizStepScaffold.swift
//
// HER-100 — visual shell every quiz step renders into: step header
// (1/5, 2/5, …), title + subtitle, scrollable content area, sticky
// footer for the CTA. Keeps the per-step views focused on the
// answer-capture widget.

import SwiftUI

struct SoulQuizStepScaffold<Content: View, Footer: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Step \(number) of 5")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                    Text(title)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                    content()
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            footer()
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
