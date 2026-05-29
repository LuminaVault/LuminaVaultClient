// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/ProfileStatsHUDView.swift
//
// Sci-fi "player profile" HUD for the Home dashboard. Renders the
// GET /v1/dashboard/profile counters: a hero Power Level ring (with an XP
// progress arc toward the next level) plus a row of stat tiles —
// Skills · Jobs · Sessions · Badges.

import LuminaVaultShared
import SwiftUI

struct ProfileStatsHUDView: View {
    @Environment(\.lvPalette) private var palette

    let state: HomeViewModel.CardState<DashboardProfileResponse>

    var body: some View {
        VStack(spacing: LVSpacing.lg) {
            powerRing
            statRow
        }
        .padding(.vertical, LVSpacing.lg)
        .padding(.horizontal, LVSpacing.base)
        .frame(maxWidth: .infinity)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.7)
        .lvAuroraGoldRing(cornerRadius: LVRadius.card)
    }

    // MARK: Power ring

    private var powerRing: some View {
        ZStack {
            Circle()
                .stroke(palette.textSecondary.opacity(0.18), lineWidth: 8)

            Circle()
                .trim(from: 0, to: levelFraction)
                .stroke(
                    AngularGradient(
                        colors: [palette.glowPrimary, palette.accent, palette.glowPrimary],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: palette.glowPrimary.opacity(0.7), radius: 8)
                .animation(.easeOut(duration: 0.6), value: levelFraction)

            VStack(spacing: 2) {
                Text(levelText)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [palette.glowPrimary, palette.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: palette.glowPrimary.opacity(0.6), radius: 8)
                Text("POWER LEVEL")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(width: 132, height: 132)
    }

    // MARK: Stat tiles

    private var statRow: some View {
        HStack(spacing: LVSpacing.sm) {
            statTile(symbol: "wand.and.stars", value: profile?.skillsCount, label: "Skills")
            statTile(symbol: "bolt.fill", value: profile?.jobsCount, label: "Jobs")
            statTile(symbol: "bubble.left.and.bubble.right.fill", value: profile?.sessionsCount, label: "Sessions")
            statTile(symbol: "rosette", value: profile?.badgesEarned, label: "Badges")
        }
    }

    private func statTile(symbol: String, value: Int?, label: String) -> some View {
        VStack(spacing: LVSpacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.glowPrimary)
                .shadow(color: palette.glowPrimary.opacity(0.5), radius: 5)
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .redacted(reason: isLoading ? .placeholder : [])
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LVSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.sm, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
    }

    // MARK: Derived values

    private var profile: DashboardProfileResponse? { state.value }

    private var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    private var levelText: String {
        guard let profile else { return "—" }
        return "\(profile.powerLevel)"
    }

    /// Fraction of XP earned toward the next level. Level `L` starts at
    /// `(L-1)^2` XP and the next at `L^2` (inverse of the server's
    /// `floor(sqrt(xp)) + 1` curve). Clamped to 0...1.
    private var levelFraction: CGFloat {
        guard let profile, profile.powerLevel >= 1 else { return 0 }
        let level = profile.powerLevel
        let floorXP = (level - 1) * (level - 1)
        let nextXP = level * level
        let span = nextXP - floorXP
        guard span > 0 else { return 0 }
        let progressed = profile.powerXP - floorXP
        return max(0, min(1, CGFloat(progressed) / CGFloat(span)))
    }
}
