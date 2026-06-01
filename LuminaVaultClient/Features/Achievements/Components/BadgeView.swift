// LuminaVaultClient/LuminaVaultClient/Features/Achievements/Components/BadgeView.swift
//
// A single achievement badge — the visual atom of the Achievements screen.
// Unlocked: a glowing glass medallion tinted by rarity. Locked: dimmed with a
// progress ring driven by progress/target so the next tier is always visible.

import LuminaVaultShared
import SwiftUI

typealias AchievementSub = AchievementsListResponse.SubDTO

struct BadgeView: View {
    @Environment(\.lvPalette) private var palette

    let sub: AchievementSub
    /// Drives the unlock reveal animation when presented in the overlay.
    var revealed: Bool = true

    private var rarity: AchievementRarity { AchievementRarity(target: sub.target) }
    private var isUnlocked: Bool { sub.unlockedAt != nil }
    private var progressFraction: Double {
        guard sub.target > 0 else { return isUnlocked ? 1 : 0 }
        return min(1, Double(sub.progress) / Double(sub.target))
    }

    var body: some View {
        VStack(spacing: LVSpacing.sm) {
            medallion
            label
        }
        .frame(maxWidth: .infinity)
        .opacity(revealed ? 1 : 0)
        .scaleEffect(revealed ? 1 : 0.6)
    }

    // MARK: Medallion

    private var medallion: some View {
        ZStack {
            // Base disc — material + faint rarity wash.
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(palette.surface))
                .overlay(
                    Circle().fill(
                        RadialGradient(
                            colors: [tint.opacity(isUnlocked ? 0.30 : 0.06), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 44
                        )
                    )
                )

            // Locked: faint track + progress arc. Unlocked: solid rarity ring.
            if isUnlocked {
                Circle().stroke(tint.opacity(0.9), lineWidth: 2)
            } else {
                Circle().stroke(palette.textSecondary.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(
                        tint.opacity(0.8),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            glyph
        }
        .frame(width: 76, height: 76)
        .saturation(isUnlocked ? 1 : 0.25)
        .shadow(color: tint.opacity(isUnlocked ? 0.5 * rarity.glowIntensity : 0), radius: 14)
        .overlay(alignment: .bottomTrailing) {
            if isUnlocked, rarity.usesGoldRing {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .padding(4)
                    .background(Circle().fill(.ultraThinMaterial))
                    .offset(x: 2, y: 2)
            }
        }
    }

    private var glyph: some View {
        Image(systemName: glyphSymbol)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(isUnlocked ? tint : palette.textSecondary.opacity(0.7))
            .shadow(color: tint.opacity(isUnlocked ? 0.7 : 0), radius: 6)
    }

    private var glyphSymbol: String {
        guard isUnlocked else { return "lock.fill" }
        switch rarity {
        case .common: return "seal.fill"
        case .rare: return "rosette"
        case .epic: return "sparkles"
        case .legendary: return "crown.fill"
        }
    }

    // MARK: Label

    private var label: some View {
        VStack(spacing: 2) {
            Text(sub.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isUnlocked ? palette.textPrimary : palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if isUnlocked {
                Text(rarity.label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(tint)
            } else {
                Text("\(sub.progress)/\(sub.target)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.textSecondary.opacity(0.8))
            }
        }
    }

    private var tint: Color { rarity.tint(palette) }
}

#if DEBUG
#Preview("Badges — all rarities × states") {
    let mk: (String, Int64, Int64, Bool) -> AchievementSub = { label, target, progress, unlocked in
        AchievementsListResponse.SubDTO(
            key: label, label: label, target: target,
            progress: progress, unlockedAt: unlocked ? Date() : nil
        )
    }
    return ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
            BadgeView(sub: mk("First Spark", 1, 1, true))
            BadgeView(sub: mk("Kindled Mind", 10, 4, false))
            BadgeView(sub: mk("Illuminator", 50, 50, true))
            BadgeView(sub: mk("Night Walker", 25, 9, false))
            BadgeView(sub: mk("Soulkeeper", 100, 100, true))
            BadgeView(sub: mk("Regent", 100, 12, false))
        }
        .padding()
    }
    .background(LVPalette.cyanGoldDark.backgroundBase)
    .environment(\.lvPalette, .cyanGoldDark)
}
#endif
