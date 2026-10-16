// LuminaVaultClient/LuminaVaultClient/Features/Recap/RecapShareCard.swift
//
// The image "Share recap" sends. Numbers and bars only: no highlight titles,
// no kinds, no Space names — nothing that says what was saved, only how much.
// That is the same promise the server makes about `shareText`.
//
// Drawn on its own fixed dark ground rather than the app's palette, so the
// image looks the same in whichever chat it lands in, whatever mode the
// sender's phone was in.

import LuminaVaultShared
import SwiftUI
import UIKit

struct RecapShareCard: View {
    let recap: MeRecapResponse

    /// The card's own palette: the dark cyan/gold identity, independent of
    /// the sender's theme.
    private let palette = LVPalette.cyanGoldDark

    static let width: CGFloat = 390

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.lg) {
            header
            stats
            RecapActivityChart(
                days: RecapDates.chartDays(for: recap),
                range: recap.range,
                timeZone: RecapDates.timeZone(for: recap)
            )
            .frame(height: 150)
            RecapLegend(totals: recap.totals)
            footer
        }
        .padding(LVSpacing.xl)
        .frame(width: Self.width, alignment: .leading)
        .background {
            ZStack {
                Color(red: 7 / 255, green: 13 / 255, blue: 30 / 255)
                RadialGradient(
                    colors: [palette.auroraTop, .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 320
                )
                RadialGradient(
                    colors: [palette.auroraBottom, .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 360
                )
            }
        }
        .environment(\.lvPalette, palette)
        .environment(\.colorScheme, .dark)
        // A rendered image has no Dynamic Type: fix the size so a user on
        // accessibility text sizes still gets a card that fits its frame.
        .dynamicTypeSize(.large)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: LVSpacing.sm) {
            Image("Lumina/Icons/shield-brain")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text("LuminaVault")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(recap.range == .week ? "My week" : "My month")
                    .lvFont(.fieldLabel)
                    .foregroundStyle(palette.textPrimary)
                Text(RecapDates.rangeText(for: recap))
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: LVSpacing.sm) {
            ForEach(RecapMetric.allCases) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(metric.value(in: recap.totals))")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(metric.color(in: palette))
                    Text(metric.title)
                        .lvFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: LVSpacing.xs) {
            Image(systemName: "flame.fill")
                .foregroundStyle(palette.accent)
            Text(footerText)
                .lvFont(.footnote)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var footerText: String {
        let active = recap.totals.activeDays
        let streak = recap.totals.streakDays
        return "Active \(active) of \(recap.range.days) days · \(streak)-day streak"
    }

    /// The card as a PNG-ready image at 3×. Main-actor because
    /// `ImageRenderer` is.
    @MainActor
    static func render(_ recap: MeRecapResponse) -> UIImage? {
        let renderer = ImageRenderer(content: RecapShareCard(recap: recap))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.uiImage
    }
}
