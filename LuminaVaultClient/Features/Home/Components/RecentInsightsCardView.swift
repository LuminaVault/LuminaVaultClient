// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/RecentInsightsCardView.swift
//
// HER-244 — surfaces the 2–3 most recent proactive findings. Empty by
// default until HER-248 wires skill-backed insight generation.

import LuminaVaultShared
import SwiftUI

struct RecentInsightsCardView: View {
    let state: HomeViewModel.CardState<[InsightDTO]>

    var body: some View {
        DashboardCardShell(title: "Recent Insights", icon: "sparkles") {
            switch state {
            case .loading:
                placeholder(text: "Loading…")
            case .failed(let message):
                placeholder(text: message)
            case .loaded(let items) where items.isEmpty:
                placeholder(text: "Lumina is still listening. Insights will land here when she spots patterns.")
            case .loaded(let items):
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items.prefix(3)) { insight in
                        row(insight)
                    }
                }
            }
        }
    }

    private func placeholder(text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.lvTextMuted)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ insight: InsightDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(insight.headline)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.lvTextPrimary)
                .lineLimit(2)
            Text(insight.summary)
                .font(.system(size: 12))
                .foregroundStyle(Color.lvTextSub)
                .lineLimit(2)
        }
    }
}
