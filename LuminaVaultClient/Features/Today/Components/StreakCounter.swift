// LuminaVaultClient/LuminaVaultClient/Features/Today/Components/StreakCounter.swift
//
// HER-177 — top-right streak counter on the Today tab.

import SwiftUI

struct StreakCounter: View {

    @Environment(\.lvPalette) private var palette

    let days: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(palette.accent)
            Text("\(days) day\(days == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.backgroundBase.opacity(0.6))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(palette.accent.opacity(0.3), lineWidth: 1)
        )
        .accessibilityLabel("\(days)-day streak")
    }
}
