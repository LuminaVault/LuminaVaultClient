// LuminaVaultClient/LuminaVaultClientTests/ChatCosmicBackgroundTests.swift
//
// The chat backdrop used to paint `Color.black` regardless of color scheme,
// so a light-mode user saw a black starfield under a light header and tab
// bar — the "chat changes the theme of the whole app" report. The backdrop
// now resolves its layers from the palette and scheme like every other
// screen (`View+LVBackground`).
//
// Muse Stage A flattened it to the chat canvas: `#070d1e` in the dark, the
// palette base in the light, and no sparkle layer in either.

import SwiftUI
import XCTest
@testable import LuminaVaultClient

final class ChatCosmicBackgroundTests: XCTestCase {
    func testLightSchemeUsesPaletteBase() {
        let palette = LVTheme.cyanGold.palette(for: .light)
        let layers = ChatCosmicBackground.Layers(scheme: .light, palette: palette)

        XCTAssertEqual(layers.base, palette.backgroundBase, "light chat must sit on the same base as the rest of the app")
    }

    func testDarkSchemeUsesMuseCanvas() {
        let palette = LVTheme.cyanGold.palette(for: .dark)
        let layers = ChatCosmicBackground.Layers(scheme: .dark, palette: palette)

        XCTAssertEqual(layers.base, LVPalette.museCanvasDark)
    }

    func testLightBaseFollowsEveryThemePalette() {
        for theme in LVTheme.allCases {
            let palette = theme.palette(for: .light)
            let layers = ChatCosmicBackground.Layers(scheme: .light, palette: palette)
            XCTAssertEqual(layers.base, palette.backgroundBase, "\(theme)")
        }
    }

    func testDarkCanvasIsTheSameForEveryTheme() {
        // The contract fixes the canvas per app, not per theme.
        for theme in LVTheme.allCases {
            let layers = ChatCosmicBackground.Layers(scheme: .dark, palette: theme.palette(for: .dark))
            XCTAssertEqual(layers.base, LVPalette.museCanvasDark, "\(theme)")
        }
    }
}

/// The contract's user bubble (`#0096ff`) fails AA under white text, so the
/// token is darkened. This keeps it from drifting back.
final class MuseColorsContrastTests: XCTestCase {
    private func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    func testWhiteOnUserBubbleMeetsAA() {
        let ratio = 1.05 / (luminance(LVPalette.museUserBubble) + 0.05)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }
}
