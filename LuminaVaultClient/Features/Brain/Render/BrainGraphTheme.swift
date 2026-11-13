// The Brain graph's drawing colours, taken from the active `LVPalette`. The web
// reads `--lv-graph-*` tokens; the iOS palette has no graph tokens, so the
// eight category swatches and the one colour per connection kind are derived
// from the palette: the primary colour's OKLCH hue, rotated, at a lightness
// and chroma fixed per appearance, then nudged until it stands off the
// background. Same palette and scheme, same colours, every time.

import LuminaVaultShared
import SwiftUI

nonisolated struct BrainGraphTheme: Equatable, Sendable {
    static let categoryCount = 8

    /// Behind everything; also hub interiors and label plates.
    var background: Color
    var label: Color
    /// Dimmed points and edges, drawn at `BrainGraphCanvasLogic.dimAlpha`.
    var dim: Color
    /// Hub rings.
    var hub: Color
    /// The ring around selected points.
    var selection: Color
    var categories: [Color]
    /// One per `BrainLinkKindDTO.allCases`, in that order.
    var links: [Color]

    /// Hue steps between neighbouring swatches: eight distinct hues, each
    /// 135 degrees from the one before it.
    private static let categoryHueStep: Double = 135
    /// Connection kinds start a little off the category hues.
    private static let linkHueOffset: Double = 22
    /// Coprime with the seven connection kinds, so every slot is used once.
    private static let linkSlotStride = 3

    @MainActor
    init(palette: LVPalette, scheme: ColorScheme) {
        let bg = BrainOKLCH.RGB(palette.backgroundBase, scheme: scheme, over: scheme == .dark ? .black : .white)
        let dark = BrainOKLCH.luminance(bg) < 0.2
        func over(_ c: Color) -> BrainOKLCH.RGB { BrainOKLCH.RGB(c, scheme: scheme, over: bg) }
        func swatch(_ rgb: BrainOKLCH.RGB, contrast: Double) -> Color {
            BrainOKLCH(rgb).standingOff(bg, contrast: contrast, lighter: dark).color
        }

        background = bg.color
        label = swatch(over(palette.textPrimary), contrast: 4.5)
        hub = swatch(over(palette.textSecondary), contrast: 3)
        dim = over(palette.textSecondary).color
        selection = swatch(over(palette.highlight), contrast: 3)

        let base = BrainOKLCH(over(palette.primary)).h
        let (l, c) = dark ? (0.76, 0.13) : (0.52, 0.14)
        categories = (0 ..< Self.categoryCount).map { i in
            BrainOKLCH(l: l, c: c, h: base + Double(i) * Self.categoryHueStep)
                .standingOff(bg, contrast: 3, lighter: dark).color
        }
        let kinds = BrainLinkKindDTO.allCases.count
        let (ll, lc) = dark ? (0.70, 0.11) : (0.50, 0.12)
        links = (0 ..< kinds).map { i in
            // Kinds take every third hue slot, so neighbours in the list (and
            // Links and Similar, first and last, which would otherwise sit
            // one slot apart) are far apart on the wheel.
            let slot = (i * Self.linkSlotStride) % kinds
            return BrainOKLCH(l: ll, c: lc, h: base + Self.linkHueOffset + Double(slot) * 360 / Double(kinds))
                .standingOff(bg, contrast: 3, lighter: dark).color
        }
    }

    func link(_ kind: BrainLinkKindDTO) -> Color {
        guard let at = BrainLinkKindDTO.allCases.firstIndex(of: kind), at < links.count else { return dim }
        return links[at]
    }

    /// The swatch slot of a colour key (web `categoryColour`): keys take slots
    /// in `order` and wrap after eight; a key outside `order` gets one from a
    /// hash of its text, so it is still the same every time.
    func categoryIndex(for key: String, order: [String]) -> Int {
        let slot = order.firstIndex(of: key) ?? Int(Self.hash(key) % UInt32(Self.categoryCount))
        return slot % Self.categoryCount
    }

    func categoryColour(for key: String, order: [String]) -> Color {
        guard !categories.isEmpty else { return dim }
        return categories[categoryIndex(for: key, order: order) % categories.count]
    }

    /// The web's hash: `h = h * 31 + code unit`, unsigned 32-bit.
    private static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 0
        for unit in text.utf16 { h = h &* 31 &+ UInt32(unit) }
        return h
    }
}

// MARK: - OKLCH

/// A colour in OKLCH (lightness 0...1, chroma, hue in degrees), with the
/// conversions the theme needs. Björn Ottosson's OKLab matrices.
nonisolated struct BrainOKLCH: Equatable, Sendable {
    /// Gamma-encoded sRGB, 0...1 when in gamut.
    nonisolated struct RGB: Equatable, Sendable {
        var r: Double
        var g: Double
        var b: Double

        static let black = RGB(r: 0, g: 0, b: 0)
        static let white = RGB(r: 1, g: 1, b: 1)

        init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        /// `color` resolved for `scheme`, its opacity composited over `backdrop`.
        @MainActor
        init(_ color: Color, scheme: ColorScheme, over backdrop: RGB = .black) {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let c = color.resolve(in: environment)
            let a = Double(c.opacity)
            r = Double(c.red) * a + backdrop.r * (1 - a)
            g = Double(c.green) * a + backdrop.g * (1 - a)
            b = Double(c.blue) * a + backdrop.b * (1 - a)
        }

        var color: Color {
            Color(.sRGB, red: min(1, max(0, r)), green: min(1, max(0, g)), blue: min(1, max(0, b)))
        }

        var inGamut: Bool {
            let e = 1e-9
            return [r, g, b].allSatisfy { $0 >= -e && $0 <= 1 + e }
        }
    }

    var l: Double
    var c: Double
    var h: Double

    init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    init(_ rgb: RGB) {
        let r = Self.linear(rgb.r), g = Self.linear(rgb.g), b = Self.linear(rgb.b)
        let lc = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let mc = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let sc = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc
        let A = 1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc
        let B = 0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc
        self.init(l: L, c: (A * A + B * B).squareRoot(), h: atan2(B, A) * 180 / .pi)
    }

    var rgb: RGB {
        let A = c * cos(h * .pi / 180)
        let B = c * sin(h * .pi / 180)
        let lc = l + 0.3963377774 * A + 0.2158037573 * B
        let mc = l - 0.1055613458 * A - 0.0638541728 * B
        let sc = l - 0.0894841775 * A - 1.2914855480 * B
        let L = lc * lc * lc, M = mc * mc * mc, S = sc * sc * sc
        return RGB(
            r: Self.gamma(4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S),
            g: Self.gamma(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S),
            b: Self.gamma(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S)
        )
    }

    var color: Color { inGamut().rgb.color }

    /// The same lightness and hue with as much chroma as sRGB can show.
    func inGamut() -> BrainOKLCH {
        if rgb.inGamut { return self }
        var lo = 0.0, hi = c
        for _ in 0 ..< 24 {
            let mid = (lo + hi) / 2
            if BrainOKLCH(l: l, c: mid, h: h).rgb.inGamut { lo = mid } else { hi = mid }
        }
        return BrainOKLCH(l: l, c: lo, h: h)
    }

    /// This colour, made lighter (on a dark background) or darker (on a light
    /// one) in small steps until it reaches `contrast` against `background`.
    func standingOff(_ background: RGB, contrast target: Double, lighter: Bool) -> BrainOKLCH {
        var next = inGamut()
        var steps = 0
        while Self.contrast(next.rgb, background) < target, steps < 100 {
            let l = min(1, max(0, next.l + (lighter ? 0.01 : -0.01)))
            if l == next.l { break }
            next = BrainOKLCH(l: l, c: c, h: h).inGamut()
            steps += 1
        }
        return next
    }

    /// WCAG relative luminance.
    static func luminance(_ rgb: RGB) -> Double {
        0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }

    /// WCAG contrast ratio, 1...21.
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func linear(_ v: Double) -> Double {
        let a = abs(v)
        let out = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
        return v < 0 ? -out : out
    }

    private static func gamma(_ v: Double) -> Double {
        let a = abs(v)
        let out = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055
        return v < 0 ? -out : out
    }
}
