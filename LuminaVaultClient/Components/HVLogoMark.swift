// LuminaVaultClient/LuminaVaultClient/Components/HVLogoMark.swift
import SwiftUI

struct LVLogoMark: View {
    var body: some View {
        Image("OnboardingLogo1")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 72)
            .shadow(color: Color.lvCyan.opacity(0.35), radius: 16)
            .shadow(color: Color.lvAmber.opacity(0.15), radius: 30)
    }
}

#Preview {
    LVLogoMark()
        .lvBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
