// HermesVaultClient/HermesVaultClient/Components/StepIcon.swift
import SwiftUI

struct StepIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.08))
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1.5)
                )
            Image(systemName: systemName)
                .font(.system(size: 22))
                .foregroundStyle(color.opacity(0.9))
        }
        .padding(.bottom, 12)
    }
}
