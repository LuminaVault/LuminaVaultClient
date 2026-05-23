// HER-287 — Screen 6: Personalised solution (pain → solution mirror).
import SwiftUI

struct PersonalisedSolutionView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette

    private struct Row: Identifiable {
        let id: Int
        let icon: String
        let pain: String
        let solution: String
    }

    private let rows: [Row] = [
        .init(id: 0, icon: "🧠",
              pain: "Re-explaining context every chat",
              solution: "Lumina remembers every capture. Persistent across sessions, automatically."),
        .init(id: 1, icon: "🎙️",
              pain: "AI that sounds robotic",
              solution: "SOUL.md mirrors your tone. Set it once. Every reply forever."),
        .init(id: 2, icon: "📥",
              pain: "Notes scattered across apps",
              solution: "Share Extension + photo OCR + voice + Health → one inbox. Query in one sentence."),
        .init(id: 3, icon: "💡",
              pain: "Forgetting your own insights",
              solution: "Daily patterns + contradictions, surfaced before coffee."),
    ]

    var body: some View {
        FunnelScreenChrome(
            headline: "Lumina handles all of that.",
            subhead: "Specifically, the thing you said —",
            primaryCTA: "Show me more",
            onPrimary: { state.advance() }
        ) {
            VStack(spacing: 12) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 14) {
                        Text(row.icon)
                            .font(.system(size: 26))
                            .frame(width: 38, alignment: .center)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.pain)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(row.solution)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(palette.glowPrimary.opacity(0.25), lineWidth: 1)
                    )
                }
            }
        }
    }
}
