// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/VaultHealthCardView.swift
//
// HER-244 — surfaces memories-today + total + last-compile in one card.

import LuminaVaultShared
import SwiftUI

struct VaultHealthCardView: View {
    let state: HomeViewModel.CardState<DashboardStatsResponse>

    var body: some View {
        DashboardCardShell(title: "Vault Health", icon: "books.vertical.fill") {
            switch state {
            case .loading:
                Self.skeleton
            case .failed(let message):
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.lvTextMuted)
            case .loaded(let stats):
                HStack(alignment: .top, spacing: 24) {
                    metric(value: "\(stats.memoriesToday)", label: "today")
                    metric(value: "\(stats.memoriesTotal)", label: "total")
                    metric(value: Self.relativeCompile(stats.lastCompileAt), label: "last compile")
                }
            }
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.lvTextPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.lvTextSub)
        }
    }

    private static let skeleton: some View = HStack(spacing: 24) {
        ForEach(0..<3, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.lvGlass)
                .frame(width: 60, height: 32)
        }
    }

    private static func relativeCompile(_ date: Date?) -> String {
        guard let date else { return "never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
