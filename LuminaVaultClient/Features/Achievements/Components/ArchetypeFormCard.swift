// LuminaVaultClient/LuminaVaultClient/Features/Achievements/Components/ArchetypeFormCard.swift
//
// One "Form" — a server archetype (Lightbringer / Shadowlord / Reignmaker /
// Soulseeker) and its grid of sub-achievement badges. When every sub in the
// set is unlocked the card lights its "true form" header (gold aurora ring).

import LuminaVaultShared
import SwiftUI

typealias AchievementArchetype = AchievementsListResponse.ArchetypeDTO

struct ArchetypeFormCard: View {
    @Environment(\.lvPalette) private var palette

    let archetype: AchievementArchetype

    private var unlockedCount: Int { archetype.sub.filter { $0.unlockedAt != nil }.count }
    private var isTrueForm: Bool { !archetype.sub.isEmpty && unlockedCount == archetype.sub.count }

    private let columns = [
        GridItem(.flexible(), spacing: LVSpacing.base),
        GridItem(.flexible(), spacing: LVSpacing.base)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.lg) {
            header
            LazyVGrid(columns: columns, spacing: LVSpacing.lg) {
                ForEach(archetype.sub, id: \.key) { sub in
                    BadgeView(sub: sub)
                }
            }
        }
        .padding(LVSpacing.lg)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: isTrueForm ? 0.9 : 0.55)
        .modifier(TrueFormRing(active: isTrueForm))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: LVSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(archetype.label)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Text(isTrueForm ? "True Form unlocked" : "\(unlockedCount)/\(archetype.sub.count) unlocked")
                    .font(.caption)
                    .foregroundStyle(isTrueForm ? palette.accent : palette.textSecondary)
            }
            Spacer()
            if isTrueForm {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(palette.accent)
                    .shadow(color: palette.accent.opacity(0.7), radius: 8)
            }
        }
    }
}

/// Applies the premium gold ring only when the whole archetype is complete.
private struct TrueFormRing: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.lvAuroraGoldRing(cornerRadius: LVRadius.card)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("Form card — partial & true form") {
    let sub: (String, Int64, Int64, Bool) -> AchievementSub = { l, t, p, u in
        AchievementsListResponse.SubDTO(key: l, label: l, target: t, progress: p, unlockedAt: u ? Date() : nil)
    }
    return ScrollView {
        VStack(spacing: 24) {
            ArchetypeFormCard(archetype: .init(key: "lightbringer", label: "Lightbringer", sub: [
                sub("First Spark", 1, 1, true),
                sub("Kindled Mind", 10, 4, false),
                sub("Illuminator", 50, 0, false),
                sub("Lightbearer", 200, 0, false)
            ]))
            ArchetypeFormCard(archetype: .init(key: "soulseeker", label: "Soulseeker", sub: [
                sub("First Relic", 1, 1, true),
                sub("Collector", 10, 10, true),
                sub("Cartographer", 3, 3, true),
                sub("Soulkeeper", 100, 100, true)
            ]))
        }
        .padding()
    }
    .background(LVPalette.cyanGoldDark.backgroundBase)
    .environment(\.lvPalette, .cyanGoldDark)
}
#endif
