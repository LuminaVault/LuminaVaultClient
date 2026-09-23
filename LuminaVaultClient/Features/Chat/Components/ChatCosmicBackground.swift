// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/ChatCosmicBackground.swift
//
// Shared backdrop for the AI chat surface, behind both the empty state and
// the active conversation.
//
// Muse (Stage A) flattened it to the plain chat canvas: `#070d1e` in the dark,
// the palette's own base in the light. The radial glows and the drifting
// sparkle field are gone — the contract's canvas is one colour, and the
// avatar ring is the only thing on the screen that moves on its own.
//
// Light still follows the palette's base, which is what fixed the old "chat
// flips the whole app's theme" report. The layer decision stays factored into
// `Layers` so it can be asserted without rendering.
import SwiftUI

struct ChatCosmicBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.lvPalette) private var palette

    /// What the backdrop draws for a given scheme + palette.
    struct Layers: Equatable {
        let base: Color

        init(scheme: ColorScheme, palette: LVPalette) {
            base = palette.muse(scheme).canvas
        }
    }

    var body: some View {
        Layers(scheme: scheme, palette: palette).base
            .ignoresSafeArea()
    }
}
