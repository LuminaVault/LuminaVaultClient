// LuminaVaultClient/LuminaVaultClient/Components/LVKickerLabel.swift
import SwiftUI

/// Identity kicker — a small uppercase monospaced eyebrow with a leading
/// 1×10pt `palette.accent` tick. Used as pane eyebrows and section headers
/// to carry the vault identity ("VAULT / CONNECTIONS").
///
/// Amber (`palette.accent`) is reserved as the premium/highlight signal, so
/// only the tick uses it; the text stays on `palette.primary`.
struct LVKickerLabel: View {
    @Environment(\.lvPalette) private var palette

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: LVSpacing.sm) {
            Rectangle()
                .fill(palette.accent)
                .frame(width: 1, height: 10)
            Text(text)
                .font(LVTypography.kicker.font)
                .kerning(1.6)
                .textCase(.uppercase)
                .foregroundStyle(palette.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: LVSpacing.base) {
        LVKickerLabel("Vault / Connections")
        LVKickerLabel("Gateways / Everywhere you talk")
        LVKickerLabel("Your keys / Your models")
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LVPalette.cyanGoldDark.backgroundBase)
    .environment(\.lvPalette, .cyanGoldDark)
}
