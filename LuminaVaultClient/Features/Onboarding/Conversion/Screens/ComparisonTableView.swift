// HER-287 — Screen 7: Comparison table (LuminaVault vs Generic AI).
import SwiftUI

struct ComparisonTableView: View {
    @Bindable var state: ConversionFunnelState
    @Environment(\.lvPalette) private var palette

    private struct Row: Identifiable {
        let id: Int
        let label: String
        let lumina: Bool
        let generic: Bool
    }

    private let rows: [Row] = [
        .init(id: 0, label: "Remembers you across sessions",         lumina: true, generic: false),
        .init(id: 1, label: "Replies in YOUR voice",                 lumina: true, generic: false),
        .init(id: 2, label: "Reads captures + Health + Safari saves", lumina: true, generic: false),
        .init(id: 3, label: "Self-host on your own server",          lumina: true, generic: false),
        .init(id: 4, label: "Surfaces patterns from your past",      lumina: true, generic: false),
    ]

    var body: some View {
        FunnelScreenChrome(
            headline: "73% of knowledge workers re-research the same topic monthly.",
            subhead: "You don't have to.",
            primaryCTA: "Set me up",
            onPrimary: { state.advance() }
        ) {
            VStack(spacing: 0) {
                header
                Divider()
                ForEach(rows) { row in
                    rowView(row)
                    Divider()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text("Placeholder stat — replace with real reference post-launch.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
    }

    private var header: some View {
        HStack {
            Text(" ")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Lumina")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.glowPrimary)
                .frame(width: 70)
            Text("Generic AI")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    private func rowView(_ row: Row) -> some View {
        HStack {
            Text(row.label)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
            checkmark(row.lumina, positive: true)
                .frame(width: 70)
            checkmark(row.generic, positive: false)
                .frame(width: 80)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
    }

    private func checkmark(_ on: Bool, positive: Bool) -> some View {
        Group {
            if on {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.65))
            }
        }
        .font(.system(size: 18))
    }
}
