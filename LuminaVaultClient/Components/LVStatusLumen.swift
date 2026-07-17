// LuminaVaultClient/LuminaVaultClient/Components/LVStatusLumen.swift
import SwiftUI

/// A status "lumen" — a dot that glows instead of sitting flat. Pass a
/// `symbolName` to render an SF Symbol glyph in place of the plain circle
/// (used by `ConnectionHealthDot` so status stays legible under
/// Differentiate Without Color).
struct LVStatusLumen: View {
    let color: Color
    var symbolName: String? = nil

    var body: some View {
        glyph
            .shadow(color: color.opacity(0.8), radius: 4)
            .shadow(color: color.opacity(0.5), radius: 1)
    }

    @ViewBuilder
    private var glyph: some View {
        if let symbolName {
            Image(systemName: symbolName)
                .font(.caption.bold())
                .foregroundStyle(color)
        } else {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
    }
}

#Preview {
    HStack(spacing: LVSpacing.base) {
        LVStatusLumen(color: .green)
        LVStatusLumen(color: .orange)
        LVStatusLumen(color: .red)
        LVStatusLumen(color: .green, symbolName: "checkmark.circle.fill")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LVPalette.cyanGoldDark.backgroundBase)
    .environment(\.lvPalette, .cyanGoldDark)
}
