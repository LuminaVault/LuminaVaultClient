// LuminaVaultClient/LuminaVaultClient/Features/MainTabView.swift
import SwiftUI

struct MainTabView: View {
    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()

            VStack(spacing: 20) {
                HermieMascotView(state: .idle, size: 220, fallbackImageName: "OnboardingMascot")

                Text("LuminaVault")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(LinearGradient(
                        colors: [.lvAmber, .lvCyan],
                        startPoint: .leading, endPoint: .trailing
                    ))

                Text("Your memories, illuminated.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.lvTextSub)
            }
        }
        .lvBackground()
    }
}
