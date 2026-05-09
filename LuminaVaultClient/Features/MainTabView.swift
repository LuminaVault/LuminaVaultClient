// LuminaVaultClient/LuminaVaultClient/Features/MainTabView.swift
import SwiftUI

struct MainTabView: View {
    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()

            VStack(spacing: 20) {
                Image("OnboardingMascot")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220)
                    .shadow(color: Color.lvCyan.opacity(0.45), radius: 30)
                    .shadow(color: Color.lvAmber.opacity(0.20), radius: 50)

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
