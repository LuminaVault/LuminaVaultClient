// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/DashboardGreetingView.swift
//
// HER-244 — mascot + greeting line at the top of the Dashboard.
// SOUL.md-personalised copy lands later in HER-250 (server settings).

import SwiftUI

struct DashboardGreetingView: View {

    @Environment(\.lvPalette) private var palette

    let displayName: String

    var body: some View {
        VStack(spacing: 8) {
            HermieMascotView(state: .idle, size: 160, fallbackImageName: "OnboardingMascot")

            Text(greeting)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.accent, palette.primary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)

            Text(BrandCopy.brainOnline)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        guard !displayName.isEmpty else { return "Hey there" }
        return "Hey \(displayName)"
    }
}
