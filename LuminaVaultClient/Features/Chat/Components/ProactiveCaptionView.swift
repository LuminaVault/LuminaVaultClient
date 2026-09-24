// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ProactiveCaptionView.swift
//
// Muse Stage C — the caption above an agent bubble Hermie sent unprompted
// ("Briefing · 07:00", "Standing task", "From Weekly review"). Same type as
// the proposal card's caption so the two read as one voice. The text comes
// from ``ProactiveCaption``.

import SwiftUI

struct ProactiveCaptionView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    private var muse: LVMuseColors { palette.muse(colorScheme) }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(muse.textSecondary)
            .padding(.leading, LVSpacing.base)
            .accessibilityAddTraits(.isHeader)
    }
}
