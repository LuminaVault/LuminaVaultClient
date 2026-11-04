// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/View+LVBackground.swift
import SwiftUI

extension View {
    /// The app's base background, behind the content.
    ///
    /// This used to draw a branded backdrop — an aurora wash plus a 55-star
    /// field — on every one of its ~97 call sites. The app now wears the
    /// system's chrome, so it is one plain fill that matches what `List`
    /// draws for itself, and the call sites did not have to change.
    func lvBackground() -> some View {
        modifier(LVBackgroundModifier())
    }

    /// For a `List` on a tab root: sits it on the palette's canvas when the
    /// theme paints its own (Memory Keeper). Themes on the system grouped
    /// background keep the native list untouched.
    func lvListCanvas() -> some View {
        modifier(LVListCanvasModifier())
    }
}

private struct LVBackgroundModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette

    func body(content: Content) -> some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
    }
}

private struct LVListCanvasModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(palette.usesBrandCanvas ? .hidden : .automatic)
            .background(palette.backgroundBase.ignoresSafeArea())
    }
}
