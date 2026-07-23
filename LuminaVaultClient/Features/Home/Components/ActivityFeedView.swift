// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/ActivityFeedView.swift
//
// Command Center — unified recent-activity feed fed by
// GET /v1/dashboard/activity: conversations, memories, achievements,
// and skill runs in one reverse-chronological stream.

import LuminaVaultShared
import SwiftUI

struct ActivityFeedView: View {

    @Environment(\.lvPalette) private var palette

    let items: [ActivityFeedItemDTO]
    let isLoading: Bool

    var body: some View {
        DashboardCardShell(title: "Recent Activity", icon: "clock.arrow.circlepath") {
            if items.isEmpty {
                Text(isLoading ? "Loading…" : "Nothing yet — capture a note or start a chat and it lands here.")
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item)
                        if index < items.count - 1 {
                            Divider()
                                .overlay(palette.textSecondary.opacity(0.15))
                                .padding(.leading, 32)
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: ActivityFeedItemDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: item.kind))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint(for: item.kind))
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(item.occurredAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func icon(for kind: ActivityFeedItemKind) -> String {
        switch kind {
        case .conversation: "bubble.left.and.bubble.right.fill"
        case .memory: "sparkles"
        case .achievement: "trophy.fill"
        case .skillRun: "bolt.fill"
        }
    }

    private func tint(for kind: ActivityFeedItemKind) -> Color {
        switch kind {
        case .conversation: palette.accent
        case .memory: palette.glowPrimary
        case .achievement: .yellow
        case .skillRun: palette.secondary
        }
    }
}
