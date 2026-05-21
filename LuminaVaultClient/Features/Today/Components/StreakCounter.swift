// LuminaVaultClient/LuminaVaultClient/Features/Today/Components/StreakCounter.swift
//
// HER-177 — top-right streak counter on the Today tab.

import SwiftUI

struct StreakCounter: View {
    let days: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color.lvAmber)
            Text("\(days) day\(days == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.lvTextPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.lvNavy.opacity(0.6))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.lvAmber.opacity(0.3), lineWidth: 1)
        )
        .accessibilityLabel("\(days)-day streak")
    }
}
