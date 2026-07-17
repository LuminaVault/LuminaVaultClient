// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/CommandCenterHeroView.swift
//
// Hybrid Command Center hero: neural brain sphere center + small Hermie,
// active model name, and ONLINE status chip.

import LuminaVaultShared
import SwiftUI

struct CommandCenterHeroView: View {
    @Environment(\.lvPalette) private var palette

    let modelName: String?
    let providerName: String?
    let agentOnline: Bool
    let networkOnline: Bool
    let onOpenBrain: () -> Void

    private var isOnline: Bool { agentOnline && networkOnline }

    var body: some View {
        VStack(spacing: LVSpacing.md) {
            Text("LUMINA COMMAND")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(palette.textSecondary)

            ZStack(alignment: .bottomTrailing) {
                Button(action: onOpenBrain) {
                    BrainCoreSphereView(size: 200)
                        .shadow(color: palette.glowPrimary.opacity(0.45), radius: 24)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens your knowledge graph")

                HermieMascotView(state: .idle, size: 72, fallbackImageName: "Lumina/Mascot/hermie-hero")
                    .shadow(color: palette.glowPrimary.opacity(0.4), radius: 12)
                    .offset(x: 8, y: 12)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text(displayModel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 8) {
                    Circle()
                        .fill(isOnline ? Color.green : palette.textSecondary)
                        .frame(width: 7, height: 7)
                        .shadow(color: isOnline ? .green.opacity(0.8) : .clear, radius: 4)
                    Text(isOnline ? "AGENT CORE · ONLINE" : "AGENT CORE · OFFLINE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(palette.textSecondary)
                }

                if let providerName, !providerName.isEmpty {
                    Text(providerName.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.textSecondary.opacity(0.8))
                }
            }
        }
        .padding(.vertical, LVSpacing.lg)
        .padding(.horizontal, LVSpacing.base)
        .frame(maxWidth: .infinity)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.7)
        .lvAuroraGoldRing(cornerRadius: LVRadius.card)
    }

    private var displayModel: String {
        let name = modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return "Default brain"
    }
}
