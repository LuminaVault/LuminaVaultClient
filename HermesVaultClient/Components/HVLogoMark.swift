// HermesVaultClient/HermesVaultClient/Components/HVLogoMark.swift
import SwiftUI

struct HVLogoMark: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.hvCyan.opacity(0.08))
                    .frame(width: 60, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.hvCyan.opacity(0.35), lineWidth: 1.5)
                    )
                    .shadow(color: Color.hvCyan.opacity(0.12), radius: 12)
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [.hvCyan, .hvAmber],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                    .opacity(0.9)
            }
            Text("HERMESVAULT")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(Color.hvCyan.opacity(0.65))
        }
    }
}

#Preview {
    HVLogoMark()
        .hvBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
