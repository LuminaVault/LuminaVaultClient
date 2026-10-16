// LuminaVaultClient/LuminaVaultClient/Components/YourWeekStrip.swift
//
// "Your week" on Home: a seven-bar sparkline, three small numbers, a chevron.
// The whole row is the button into the recap sheet. It shows a redacted
// placeholder while the recap loads and nothing at all if it fails — the
// caller simply does not render it then.

import LuminaVaultShared
import SwiftUI

struct YourWeekStrip: View {
    /// Nil while loading; the strip draws placeholder bars and numbers.
    let recap: MeRecapResponse?
    let onOpen: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: LVSpacing.md) {
                sparkline
                    .frame(width: 64, height: 32)
                VStack(alignment: .leading, spacing: LVSpacing.xs) {
                    Text("Your week")
                        .font(LVTypography.kicker.font)
                        .kerning(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.textSecondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: LVSpacing.md) { figures }
                        HStack(spacing: LVSpacing.sm) { figures }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .lvFont(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, LVSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .redacted(reason: recap == nil ? .placeholder : [])
        .disabled(recap == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens your recap")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Pieces

    private var shown: MeRecapResponse { recap ?? RecapPlaceholder.recap }

    /// The last seven days, oldest first. A 30-day recap would still show
    /// its last week here, but Home only ever asks for 7d.
    private var lastWeek: [RecapDayDTO] { Array(shown.daily.suffix(7)) }

    private func total(_ day: RecapDayDTO) -> Int {
        day.captures + day.learned + day.asked
    }

    private var sparkline: some View {
        let peak = max(lastWeek.map(total).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(lastWeek) { day in
                let value = total(day)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(value == 0 ? AnyShapeStyle(.quaternary) : AnyShapeStyle(palette.primary))
                    // Empty days keep a stub so the week reads as seven days.
                    .frame(height: value == 0 ? 3 : max(4, 32 * CGFloat(value) / CGFloat(peak)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var figures: some View {
        figure(shown.totals.captures, systemImage: "tray.and.arrow.down")
        figure(shown.totals.learned, systemImage: "sparkles")
        figure(shown.totals.streakDays, systemImage: "flame", suffix: "d")
    }

    private func figure(_ value: Int, systemImage: String, suffix: String = "") -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(palette.textSecondary)
            Text("\(value)\(suffix)")
                .lvFont(.bodyEmphasis)
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .contentTransition(.numericText())
        }
        .fixedSize()
    }

    private var accessibilityText: String {
        guard let recap else { return "Your week, loading" }
        let t = recap.totals
        return "Your week: \(t.captures) captures, \(t.learned) learned, \(t.streakDays)-day streak"
    }
}

#Preview {
    List {
        Section("Today") {
            YourWeekStrip(recap: RecapPlaceholder.recap, onOpen: {})
            YourWeekStrip(recap: nil, onOpen: {})
        }
    }
}
