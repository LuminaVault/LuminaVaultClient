// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/DashboardGreetingView.swift
//
// HER-244 — mascot + greeting line at the top of the Dashboard.
// SOUL.md-personalised copy lands later in HER-250 (server settings).

import SwiftUI

struct DashboardGreetingView: View {
    let displayName: String

    var body: some View {
        VStack(spacing: 8) {
            HermieMascotView(state: .idle, size: 160, fallbackImageName: "OnboardingMascot")

            Text(greeting)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.lvAmber, .lvCyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)

            Text("Your second brain is online.")
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextSub)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        guard !displayName.isEmpty else { return "Hey there" }
        return "Hey \(displayName)"
    }
}
