// LuminaVaultClient/LuminaVaultClient/Components/StepIcon.swift
import SwiftUI

struct StepIcon: View {
    let systemName: String
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Pulse ring behind icon
            Circle()
                .stroke(color.opacity(0.22), lineWidth: 1.5)
                .frame(width: pulse ? 84 : 52, height: pulse ? 84 : 52)
                .opacity(pulse ? 0 : 0.9)
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)

            // Existing icon container
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.08))
                .frame(width: 52, height: 52)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.3), lineWidth: 1.5))
            // HER-291: kept as Image — runtime symbol name
            Image(systemName: systemName)
                .font(.system(size: 22))
                .foregroundStyle(color.opacity(0.9))
        }
        .padding(.bottom, 12)
        .onAppear { pulse = true }
    }
}
