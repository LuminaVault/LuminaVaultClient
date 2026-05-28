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
            HStack(spacing: LVSpacing.sm) {
                LVIconView(.docOnClipboard, size: 12, tint: palette.primary, weight: .semibold)
                Text("Paste \(code)")
                    .font(LVTypography.caption.font.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("Tap")
                    .font(LVTypography.microTag.font)
                    .foregroundStyle(palette.primary.opacity(0.7))
            }
            .padding(.horizontal, LVSpacing.base)
            .padding(.vertical, LVSpacing.md)
            .background(Color.lvGlass)
            .overlay(
                RoundedRectangle(cornerRadius: LVRadius.md)
                    .stroke(palette.primary.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste code \(code) from clipboard")
    }
}
