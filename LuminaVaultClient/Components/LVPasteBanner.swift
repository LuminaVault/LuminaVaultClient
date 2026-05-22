// LuminaVaultClient/LuminaVaultClient/Components/LVPasteBanner.swift
import SwiftUI

/// HER-142 smart-paste affordance for OTP screens. Surfaces the 6-digit code
/// on the clipboard and lets the user one-tap fill it.
struct LVPasteBanner: View {
    @Environment(\.lvPalette) private var palette

    let code: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text("Paste \(code)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("Tap")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.primary.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.lvGlass)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.primary.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste code \(code) from clipboard")
    }
}
