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
        VStack(spacing: 22) {
            ZStack {
                if let backgroundImage {
                    Image(backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 320, height: 320)
                        .opacity(0.18)
                        .mask {
                            RadialGradient(
                                colors: [Color.white, .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 160
                            )
                        }
                }
                NeuralParticleRing()
                    .frame(width: 220, height: 220)
                HermieMascotView(state: mascot, size: 160)
            }
            VStack(spacing: 8) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textPrimary)
                if let supporting {
                    Text(supporting)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 24)
                }
            }
            if let cta = primaryCTA {
                Button(action: cta.action) {
                    Text(cta.label)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .lvGlassCard(cornerRadius: 24, intensity: 0.8)
                .lvGlowPress()
                .foregroundStyle(palette.primary)
            }
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(chips) { chip in
                            Button(action: chip.action) {
                                Text(chip.label)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .lvGlassCard(cornerRadius: 14, intensity: 0.4)
                            .lvGlowPress()
                            .foregroundStyle(palette.textPrimary)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.vertical, 24)
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
