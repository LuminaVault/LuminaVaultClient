// LuminaVaultClient/LuminaVaultClient/Features/Achievements/Components/AchievementUnlockOverlay.swift
//
// Full-screen unlock celebration. Steps through a queue of freshly-unlocked
// badges one at a time: dimmed backdrop, hero particle field, the celebrating
// Lumina mascot, the badge scaling/glowing in, and a success haptic per reveal.
// Tap anywhere to advance; dismisses when the queue is exhausted.

import LuminaVaultShared
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AchievementUnlockOverlay: View {
    @Environment(\.lvPalette) private var palette

    let subs: [AchievementSub]
    let onDismiss: () -> Void

    @State private var index = 0
    @State private var revealed = false

    private var current: AchievementSub? { subs.indices.contains(index) ? subs[index] : nil }
    private var rarity: AchievementRarity { AchievementRarity(target: current?.target ?? 1) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            Color.clear.lvParticleBackground(intensity: .hero).ignoresSafeArea()

            if let current {
                VStack(spacing: LVSpacing.xl) {
                    Text("ACHIEVEMENT UNLOCKED")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(rarity.tint(palette))

                    HermieMascotView(state: .celebrating, size: 200, fallbackImageName: "Mascot")
                        .shadow(color: palette.glowPrimary.opacity(0.55), radius: 28)
                        .shadow(color: palette.accent.opacity(0.25), radius: 48)

                    BadgeView(sub: current, revealed: revealed)
                        .scaleEffect(1.4)
                        .frame(height: 150)

                    Text(current.label)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(subs.count > 1 ? "Tap to continue (\(index + 1)/\(subs.count))" : "Tap to dismiss")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(LVSpacing.xl)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .task(id: index) { await revealCurrent() }
    }

    private func revealCurrent() async {
        revealed = false
        fireHaptic()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) {
            revealed = true
        }
    }

    private func advance() {
        if index + 1 < subs.count {
            withAnimation(.easeIn(duration: 0.15)) { revealed = false }
            index += 1
        } else {
            onDismiss()
        }
    }

    private func fireHaptic() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

#if DEBUG
#Preview("Unlock overlay") {
    AchievementUnlockOverlay(
        subs: [
            AchievementsListResponse.SubDTO(key: "soulkeeper", label: "Soulkeeper", target: 100, progress: 100, unlockedAt: Date()),
            AchievementsListResponse.SubDTO(key: "illuminator", label: "Illuminator", target: 50, progress: 50, unlockedAt: Date())
        ],
        onDismiss: {}
    )
    .environment(\.lvPalette, .cyanGoldDark)
}
#endif
