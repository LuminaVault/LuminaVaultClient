// The 2D Brain canvas's colours: palette tokens resolved to concrete colours,
// category and connection colours derived from the palette by OKLCH hue
// rotation, and the web's `categoryColour` rule.

import SwiftUI
import Testing
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
struct BrainGraphThemeTests {
    private static let palettes: [(String, LVPalette, ColorScheme)] = LVTheme.allCases.flatMap { theme in
        [ColorScheme.light, .dark].map { scheme in ("\(theme.rawValue)-\(scheme)", theme.palette(for: scheme), scheme) }
    }

    @Test func oklabRoundTripsSRGB() {
        for rgb in [BrainOKLCH.RGB(r: 0.043, g: 0.431, b: 0.471), .init(r: 0.9, g: 0.2, b: 0.1), .init(r: 0, g: 0, b: 0), .init(r: 1, g: 1, b: 1)] {
            let back = BrainOKLCH(rgb).rgb
            #expect(abs(back.r - rgb.r) < 1e-6 && abs(back.g - rgb.g) < 1e-6 && abs(back.b - rgb.b) < 1e-6)
        }
    }

    @Test func oklchOfWhiteIsLightness1WithNoChroma() {
        let white = BrainOKLCH(BrainOKLCH.RGB(r: 1, g: 1, b: 1))
        #expect(abs(white.l - 1) < 1e-4)
        #expect(white.c < 1e-4)
    }

    @Test func gamutMappingKeepsEveryChannelInRange() {
        let wild = BrainOKLCH(l: 0.8, c: 0.4, h: 140).inGamut().rgb
        for v in [wild.r, wild.g, wild.b] { #expect(v >= -1e-9 && v <= 1 + 1e-9) }
    }

    @Test func everyPaletteGivesEightDistinctCategoriesAndOneColourPerConnectionKind() {
        for (name, palette, scheme) in Self.palettes {
            let theme = BrainGraphTheme(palette: palette, scheme: scheme)
            #expect(theme.categories.count == BrainGraphTheme.categoryCount, "\(name)")
            #expect(Set(theme.categories).count == BrainGraphTheme.categoryCount, "\(name)")
            #expect(theme.links.count == BrainLinkKindDTO.allCases.count, "\(name)")
            #expect(Set(theme.links).count == BrainLinkKindDTO.allCases.count, "\(name)")
            // Neighbouring categories sit far apart in hue.
            let hues = theme.categories.map { BrainOKLCH(BrainOKLCH.RGB($0, scheme: scheme)).h }
            for i in 1 ..< hues.count {
                let d = abs(hues[i] - hues[i - 1]).truncatingRemainder(dividingBy: 360)
                #expect(min(d, 360 - d) >= 80, "\(name) \(i)")
            }
        }
    }

    @Test func pointsHubsAndTheSelectionStandOffTheBackgroundInEveryPalette() {
        for (name, palette, scheme) in Self.palettes {
            let theme = BrainGraphTheme(palette: palette, scheme: scheme)
            let bg = BrainOKLCH.RGB(theme.background, scheme: scheme)
            for (i, c) in theme.categories.enumerated() {
                #expect(BrainOKLCH.contrast(BrainOKLCH.RGB(c, scheme: scheme), bg) >= 3, "\(name) category \(i)")
            }
            for (i, c) in theme.links.enumerated() {
                #expect(BrainOKLCH.contrast(BrainOKLCH.RGB(c, scheme: scheme), bg) >= 3, "\(name) link \(i)")
            }
            #expect(BrainOKLCH.contrast(BrainOKLCH.RGB(theme.hub, scheme: scheme), bg) >= 3, "\(name) hub")
            #expect(BrainOKLCH.contrast(BrainOKLCH.RGB(theme.selection, scheme: scheme), bg) >= 3, "\(name) selection")
        }
    }

    @Test func labelsReadOnTheirPlateInEveryPalette() {
        for (name, palette, scheme) in Self.palettes {
            let theme = BrainGraphTheme(palette: palette, scheme: scheme)
            let bg = BrainOKLCH.RGB(theme.background, scheme: scheme)
            #expect(BrainOKLCH.contrast(BrainOKLCH.RGB(theme.label, scheme: scheme), bg) >= 4.5, "\(name) label")
        }
    }

    @Test func linkColourIsLookedUpByKind() {
        let theme = BrainGraphTheme(palette: .cyanGoldDark, scheme: .dark)
        for (i, kind) in BrainLinkKindDTO.allCases.enumerated() {
            #expect(theme.link(kind) == theme.links[i])
        }
    }

    @Test func aThemeIsStableForTheSamePaletteAndScheme() {
        #expect(BrainGraphTheme(palette: .cyanGoldLight, scheme: .light) == BrainGraphTheme(palette: .cyanGoldLight, scheme: .light))
        #expect(BrainGraphTheme(palette: .cyanGoldLight, scheme: .light) != BrainGraphTheme(palette: .cyanGoldDark, scheme: .dark))
    }

    // Ported from the web's `categoryColour` cases.

    private let order = (0 ..< 10).map { "k\($0)" }

    @Test func categoryIsStableForTheSameKeyAndOrder() {
        let theme = BrainGraphTheme(palette: .cyanGoldDark, scheme: .dark)
        #expect(theme.categoryIndex(for: "k3", order: order) == 3)
        #expect(theme.categoryColour(for: "k3", order: order) == theme.categories[3])
    }

    @Test func categoryWrapsAfterEight() {
        let theme = BrainGraphTheme(palette: .cyanGoldDark, scheme: .dark)
        #expect(theme.categoryIndex(for: "k0", order: order) == 0)
        #expect(theme.categoryIndex(for: "k8", order: order) == 0)
        #expect(theme.categoryIndex(for: "k9", order: order) == 1)
    }

    @Test func aKeyOutsideTheOrderGetsAStableSwatchFromItsHash() {
        let theme = BrainGraphTheme(palette: .cyanGoldDark, scheme: .dark)
        let first = theme.categoryIndex(for: "stranger", order: order)
        #expect(first == theme.categoryIndex(for: "stranger", order: order))
        #expect((0 ..< 8).contains(first))
        // The web's hash: h = h * 31 + code unit, unsigned 32-bit.
        var h: UInt32 = 0
        for unit in "stranger".utf16 { h = h &* 31 &+ UInt32(unit) }
        #expect(first == Int(h % 8))
    }
}
