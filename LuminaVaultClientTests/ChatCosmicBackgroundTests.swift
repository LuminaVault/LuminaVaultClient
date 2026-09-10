// LuminaVaultClient/LuminaVaultClientTests/ChatCosmicBackgroundTests.swift
//
// The chat backdrop used to paint `Color.black` regardless of color scheme,
// so a light-mode user saw a black starfield under a light header and tab
// bar — the "chat changes the theme of the whole app" report. The backdrop
// now resolves its layers from the palette and scheme like every other
// screen (`View+LVBackground`).

import SwiftUI
import XCTest
@testable import LuminaVaultClient

final class ChatCosmicBackgroundTests: XCTestCase {
    func testLightSchemeUsesPaletteBaseAndNoSparkles() {
        let palette = LVTheme.cyanGold.palette(for: .light)
        let layers = ChatCosmicBackground.Layers(scheme: .light, palette: palette)

        XCTAssertEqual(layers.base, palette.backgroundBase, "light chat must sit on the same base as the rest of the app")
        XCTAssertFalse(layers.showsSparkles, "screen-blended white sparkles are invisible noise on a light base")
    }

    func testDarkSchemeKeepsTheRecordedBlackBaseAndSparkles() {
        // Dark is deliberately unchanged: `think-empty-dark` is recorded on
        // the CI runtime (iOS 26.4), which cannot be re-recorded from an
        // Xcode 26.2 machine. Switching dark to `palette.backgroundBase`
        // is a one-line change once that baseline can be re-recorded.
        let palette = LVTheme.cyanGold.palette(for: .dark)
        let layers = ChatCosmicBackground.Layers(scheme: .dark, palette: palette)

        XCTAssertEqual(layers.base, .black)
        XCTAssertTrue(layers.showsSparkles)
    }

    func testLightBaseFollowsEveryThemePalette() {
        for theme in LVTheme.allCases {
            let palette = theme.palette(for: .light)
            let layers = ChatCosmicBackground.Layers(scheme: .light, palette: palette)
            XCTAssertEqual(layers.base, palette.backgroundBase, "\(theme)")
            XCTAssertFalse(layers.showsSparkles, "\(theme)")
        }
    }
}
