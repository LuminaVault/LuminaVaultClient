// LuminaVaultClient/LuminaVaultClient/Components/HVLogoMark.swift
import SwiftUI

struct LVLogoMark: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.lvCyan.opacity(0.08))
                    .frame(width: 64, height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.lvCyan.opacity(0.40), lineWidth: 1.5)
                    )
                    .shadow(color: Color.lvCyan.opacity(0.25), radius: 20)
                    .shadow(color: Color.lvCyan.opacity(0.10), radius: 40)
                // Glowing scroll mark
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [.lvCyan, .lvBlue, .lvAmber],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 34, height: 34)
                    .shadow(color: Color.lvCyan.opacity(0.5), radius: 10)
            }
            // Amber-to-cyan gradient wordmark (matches LuminaVault brand images)
            Text("LUMINAVAULT")
                .font(.system(size: 9, weight: .bold))
                .tracking(3.0)
                .foregroundStyle(LinearGradient(
                    colors: [.lvAmber, .lvCyan],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
        }
    }
}

#Preview {
    LVLogoMark()
        .lvBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
