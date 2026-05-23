// HER-287 — Screen 3: Pain points (multi-select).
import SwiftUI

struct PainPointsView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette

    var body: some View {
        FunnelScreenChrome(
            headline: "What's tripping you up right now?",
            subhead: "Pick as many as feel true.",
            primaryCTA: "Continue",
            onPrimary: { state.advance() }
        ) {
            VStack(spacing: 10) {
                ForEach(FunnelPainPoint.allCases) { pain in
                    Button {
                        state.togglePain(pain)
                    } label: {
                        row(for: pain)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for pain: FunnelPainPoint) -> some View {
        let selected = state.selectedPains.contains(pain)
        HStack(spacing: 14) {
            Image(systemName: selected ? "checkmark.square.fill" : "square")
                .font(.system(size: 20))
                .foregroundStyle(selected ? palette.glowPrimary : .secondary)
            Text(pain.emoji)
                .font(.system(size: 22))
            Text(pain.label)
                .font(.system(size: 15))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? palette.glowPrimary.opacity(0.10) : palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    selected ? palette.glowPrimary.opacity(0.5) : Color.gray.opacity(0.2),
                    lineWidth: 1
                )
        )
    }
}
