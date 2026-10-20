// LuminaVaultClient/LuminaVaultClient/Features/Learned/LearnedHomeRow.swift
//
// "Confirm what I learned · 3 new" — Home's way into "What I learned this
// week". Shown in the Today section only while something is waiting.

import SwiftUI

struct LearnedHomeRow: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        HomeRecommendationRow(
            title: "Confirm what I learned · \(count) new",
            systemImage: "brain.head.profile",
            action: onOpen
        )
        .accessibilityHint("Shows what Lumina learned about you this week")
    }
}
