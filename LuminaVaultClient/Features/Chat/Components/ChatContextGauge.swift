// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatContextGauge.swift
//
// How full the model's context window is for the turn in flight.
//
// The same rule as the web `ContextMeter`, because the two are one contract:
// the fill is the server's `promptTokens` over the window it reported, and
// nothing else. It is never inferred from the previous turn's usage. A gauge
// that moves for reasons the user cannot see is worse than no gauge, because
// they cannot tell a wrong one from a right one.
//
// It goes live because `promptTokens` rides the routing event, which fires
// before the first token. A managed tenant gets no window — it fingerprints
// the model, so the server scrubs it — and therefore no gauge, by design.

import LuminaVaultShared
import SwiftUI

struct ChatContextGauge: View {
    @Environment(\.lvPalette) private var palette

    let reading: Reading

    /// What the gauge can honestly say, or nothing.
    struct Reading: Equatable {
        /// 0...1, already clamped.
        let fraction: Double
        let droppedHistoryTurns: Int

        var percent: Int { Int((fraction * 100).rounded()) }
        /// Past this the next turn is likely to trim history.
        var isNearlyFull: Bool { percent >= 90 }

        /// `nil` unless the server supplied both numbers for this turn.
        static func make(routing: RouterRoutingEventDTO?, usage: RouterUsageDTO?) -> Reading? {
            guard let prompt = routing?.promptTokens,
                  let window = routing?.contextWindowTokens ?? usage?.contextWindowTokens,
                  window > 0
            else { return nil }
            return Reading(
                fraction: min(1, max(0, Double(prompt) / Double(window))),
                droppedHistoryTurns: routing?.droppedHistoryTurns ?? 0
            )
        }

        /// Trimming is otherwise invisible, and a user whose assistant forgot
        /// something deserves to know why.
        var droppedPhrase: String? {
            switch droppedHistoryTurns {
            case ...0: nil
            case 1: "1 earlier turn dropped to fit"
            default: "\(droppedHistoryTurns) earlier turns dropped to fit"
            }
        }
    }

    var body: some View {
        HStack(spacing: LVSpacing.xs) {
            Capsule()
                .fill(palette.surfaceStroke)
                .frame(width: 36, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(reading.isNearlyFull ? Color.red : palette.accent)
                        .frame(width: 36 * reading.fraction, height: 4)
                }
            Text("\(reading.percent)%")
                .lvFont(.microTag)
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context \(reading.percent) percent full")
    }
}
