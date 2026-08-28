// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/PowerProgressStrip.swift
//
// Marketable "road to next rank" strip under the Command Center hero.

import LuminaVaultShared
import SwiftUI

struct PowerProgressStrip: View {
    @Environment(\.lvPalette) private var palette

    let powerLevel: Int?
    let powerXP: Int?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            HStack {
                Text("POWER LEVEL")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(palette.glowPrimary)
                Spacer()
                if let powerLevel {
                    Text("Lv.\(powerLevel) · \(PowerLevelTitle.title(for: powerLevel))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                }
            }

            // One shape, no `GeometryReader`. The bar used to read its own
            // width to size a second Capsule on top of a track Capsule, which
            // put a geometry round-trip inside Home's scroll for what is a
            // purely proportional fill. Hard gradient stops at `fraction`
            // paint the same two-tone bar without ever needing the width.
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: palette.glowPrimary, location: 0),
                            .init(color: palette.accent, location: fraction),
                            .init(color: trackColor, location: fraction),
                            .init(color: trackColor, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                // Scaled by fill so an empty bar does not glow.
                .shadow(color: palette.glowPrimary.opacity(0.5 * Double(fraction)), radius: 6)
                .frame(height: 10)

            if let powerXP {
                Text("\(powerXP.formatted()) XP")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.65)
        .redacted(reason: isLoading ? .placeholder : [])
    }

    private var trackColor: Color { palette.textSecondary.opacity(0.15) }

    private var fraction: CGFloat {
        guard let powerLevel, let powerXP, powerLevel >= 1 else { return 0 }
        let floorXP = (powerLevel - 1) * (powerLevel - 1)
        let nextXP = powerLevel * powerLevel
        let span = nextXP - floorXP
        guard span > 0 else { return 0 }
        return max(0, min(1, CGFloat(powerXP - floorXP) / CGFloat(span)))
    }
}
