// LuminaVaultClient/LuminaVaultClient/Components/LVEmptyState.swift
// HER-255: shared empty-state component used across every screen.
// Mascot + headline + supporting text + glowing CTA + optional suggestion chips
// orbited by a soft neural particle ring.
import SwiftUI

struct LVEmptyStateChip: Identifiable, Equatable {
    let id: UUID
    let label: String
    let action: () -> Void

    init(id: UUID = .init(), label: String, action: @escaping () -> Void) {
        self.id = id
        self.label = label
        self.action = action
    }

    static func == (lhs: LVEmptyStateChip, rhs: LVEmptyStateChip) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label
    }
}

struct LVEmptyState: View {
    @Environment(\.lvPalette) private var palette
    let mascot: HermieMascotState
    let headline: String
    let supporting: String?
    let primaryCTA: (label: String, action: () -> Void)?
    let chips: [LVEmptyStateChip]
    /// Optional decorative background art (asset catalog name).
    /// Drawn behind the mascot at low opacity with a radial fade.
    let backgroundImage: String?

    init(
        mascot: HermieMascotState = .idle,
        headline: String,
        supporting: String? = nil,
        primaryCTA: (label: String, action: () -> Void)? = nil,
        chips: [LVEmptyStateChip] = [],
        backgroundImage: String? = nil
    ) {
        self.mascot = mascot
        self.headline = headline
        self.supporting = supporting
        self.primaryCTA = primaryCTA
        self.chips = chips
        self.backgroundImage = backgroundImage
    }

    var body: some View {
        VStack(spacing: LVSpacing.xl) {
            ZStack {
                if let backgroundImage {
                    // HER-305 — softer, larger background art so the
                    // mascot reads as the hero with the illustration
                    // breathing around it rather than confined to a disc.
                    Image(backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 340, height: 340)
                        .opacity(0.18)
                        .mask {
                            RadialGradient(
                                colors: [Color.white, Color.white.opacity(0.6), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        }
                }
                NeuralParticleRing()
                    .frame(width: LVSize.mascotSmall, height: LVSize.mascotSmall)
                HermieMascotView(state: mascot, size: 160)
            }
            VStack(spacing: LVSpacing.sm) {
                Text(headline)
                    .font(LVTypography.subtitle.font)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textPrimary)
                if let supporting {
                    Text(supporting)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, LVSpacing.xl)
                }
            }
            if let cta = primaryCTA {
                Button(action: cta.action) {
                    Text(cta.label)
                        .font(LVTypography.bodyEmphasis.font)
                        .padding(.horizontal, LVSpacing.xl)
                        .padding(.vertical, LVSpacing.md)
                }
                .buttonStyle(.plain)
                .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.8)
                .lvGlowPress()
                .foregroundStyle(palette.primary)
            }
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LVSpacing.md) {
                        ForEach(chips) { chip in
                            Button(action: chip.action) {
                                Text(chip.label)
                                    .font(LVTypography.caption.font.weight(.medium))
                                    .padding(.horizontal, LVSpacing.base)
                                    .padding(.vertical, LVSpacing.sm)
                            }
                            .buttonStyle(.plain)
                            .lvGlassCard(cornerRadius: LVRadius.lg, intensity: 0.4)
                            .lvGlowPress()
                            .foregroundStyle(palette.textPrimary)
                        }
                    }
                    .padding(.horizontal, LVSpacing.lg)
                }
            }
        }
        .padding(.vertical, LVSpacing.xl)
    }
}

/// Soft orbit of glowing particles behind the empty-state mascot.
/// Animated via TimelineView at 18 fps; Reduce Motion freezes phase.
private struct NeuralParticleRing: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let particleCount = 12
    private let radius: CGFloat = 100

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? .infinity : 1.0 / 18.0)) { ctx in
            let phase = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate * 0.35
            Canvas { canvas, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<particleCount {
                    let theta = phase + Double(i) * (2 * .pi / Double(particleCount))
                    let x = center.x + cos(theta) * radius
                    let y = center.y + sin(theta) * radius
                    let particleRect = CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)
                    let opacity = 0.35 + 0.4 * (0.5 + 0.5 * sin(theta * 2))
                    canvas.fill(
                        Path(ellipseIn: particleRect),
                        with: .color(palette.glowPrimary.opacity(opacity))
                    )
                }
            }
        }
    }
}
