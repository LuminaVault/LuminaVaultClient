// LuminaVaultClient/LuminaVaultClient/Features/Brief/BriefHomeRow.swift
//
// "Your brief · 4 cards" — Home's way into today's brief. The top row of the
// Today section, only in the morning and only once the brief exists (see
// `HomeGlanceViewModel.briefCardCount(at:)`).

import SwiftUI

struct BriefHomeRow: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        HomeRecommendationRow(
            title: "Your brief · ^[\(count) card](inflect: true)",
            systemImage: "sun.horizon",
            action: onOpen
        )
        .accessibilityHint("Opens today's brief")
    }
}
