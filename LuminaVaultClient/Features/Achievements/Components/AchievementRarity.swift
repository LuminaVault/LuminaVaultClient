// LuminaVaultClient/LuminaVaultClient/Features/Achievements/Components/AchievementRarity.swift
//
// Client-side rarity tiering. The server catalog only carries a numeric
// `target` per sub-achievement; we map that threshold to a visual rarity so
// badges escalate cyan → gold as they get harder. Pure presentation — no
// wire contract, so tuning thresholds here never needs a backend change.

import SwiftUI

enum AchievementRarity: CaseIterable {
    case common
    case rare
    case epic
    case legendary

    /// Derive rarity from a sub-achievement's unlock threshold.
    /// 1 → Common · 10 → Rare · 50 → Epic · ≥100 → Legendary.
    init(target: Int64) {
        switch target {
        case ..<10: self = .common
        case ..<50: self = .rare
        case ..<100: self = .epic
        default: self = .legendary
        }
    }

    var label: String {
        switch self {
        case .common: "Common"
        case .rare: "Rare"
        case .epic: "Epic"
        case .legendary: "Legendary"
        }
    }

    /// Glow strength fed to `lvGlassCard` / `lvInnerGlow` intensity.
    var glowIntensity: CGFloat {
        switch self {
        case .common: 0.35
        case .rare: 0.55
        case .epic: 0.75
        case .legendary: 1.0
        }
    }

    /// Primary tint for the medallion ring + badge glow. Common/Rare lean cyan
    /// (palette.glowPrimary), Epic blends, Legendary is full gold (accent).
    func tint(_ palette: LVPalette) -> Color {
        switch self {
        case .common: palette.glowPrimary.opacity(0.7)
        case .rare: palette.glowPrimary
        case .epic: palette.secondary
        case .legendary: palette.accent
        }
    }

    /// Legendary badges earn the premium gold aurora ring.
    var usesGoldRing: Bool { self == .legendary }
}
