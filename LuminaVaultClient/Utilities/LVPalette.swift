import SwiftUI

/// A bundle of colors that fully describes the active LuminaVault theme.
/// Resolved once per ColorScheme inside `LVTheme.palette(for:)` and injected
/// via `\.lvPalette` so every view reads from one source of truth.
struct LVPalette: Equatable {
    let primary: Color
    let secondary: Color
    let accent: Color

    let glowPrimary: Color
    let glowSecondary: Color

    let surface: Color           // glass-card fill (kept subtle; pairs with `.ultraThinMaterial`)
    let surfaceStroke: Color     // hairline border

    let backgroundBase: Color    // root background fill
    let auroraTop: Color         // top-trailing radial wash
    let auroraBottom: Color      // bottom-leading radial wash
    let auroraCenter: Color      // mid-depth pulse

    let textPrimary: Color
    let textSecondary: Color
}

/// Available palettes shown in the Settings → Appearance picker.
/// Each case knows how to materialize itself for the active color scheme.
enum LVTheme: String, CaseIterable, Identifiable, Codable {
    case cyanGold
    case nebula
    case solar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cyanGold: return "Cyan Gold"
        case .nebula:   return "Nebula"
        case .solar:    return "Solar"
        }
    }

    /// Two-tone swatch shown in the theme picker.
    var swatch: [Color] {
        let p = palette(for: .dark)
        return [p.primary, p.accent]
    }

    func palette(for scheme: ColorScheme) -> LVPalette {
        switch self {
        case .cyanGold: return scheme == .dark ? .cyanGoldDark : .cyanGoldLight
        case .nebula:   return scheme == .dark ? .nebulaDark   : .nebulaLight
        case .solar:    return scheme == .dark ? .solarDark    : .solarLight
        }
    }
}

// MARK: - Concrete palettes

extension LVPalette {
    // Cyan-Gold (default LuminaVault aesthetic)
    static let cyanGoldDark = LVPalette(
        primary:        Color(red: 0.000, green: 0.831, blue: 1.000), // #00D4FF cyan
        secondary:      Color(red: 0.000, green: 0.588, blue: 1.000), // #0096FF blue
        accent:         Color(red: 0.961, green: 0.620, blue: 0.043), // #F59E0B amber
        glowPrimary:    Color(red: 0.000, green: 0.831, blue: 1.000),
        glowSecondary:  Color(red: 0.961, green: 0.620, blue: 0.043),
        surface:        Color.white.opacity(0.04),
        surfaceStroke:  Color(red: 0.000, green: 0.831, blue: 1.000).opacity(0.22),
        backgroundBase: Color(red: 0.027, green: 0.051, blue: 0.118), // #070D1E
        auroraTop:      Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.18),
        auroraBottom:   Color(red: 0.000, green: 0.831, blue: 1.000).opacity(0.14),
        auroraCenter:   Color(red: 0.000, green: 0.588, blue: 1.000).opacity(0.08),
        textPrimary:    Color.white,
        textSecondary:  Color.white.opacity(0.72)
    )

    static let cyanGoldLight = LVPalette(
        primary:        Color(red: 0.000, green: 0.494, blue: 0.658),
        secondary:      Color(red: 0.000, green: 0.380, blue: 0.694),
        accent:         Color(red: 0.788, green: 0.502, blue: 0.000),
        glowPrimary:    Color(red: 0.000, green: 0.831, blue: 1.000),
        glowSecondary:  Color(red: 0.961, green: 0.620, blue: 0.043),
        surface:        Color.black.opacity(0.04),
        surfaceStroke:  Color(red: 0.000, green: 0.494, blue: 0.658).opacity(0.24),
        backgroundBase: Color(red: 0.940, green: 0.970, blue: 1.000), // #F0F7FF
        auroraTop:      Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.09),
        auroraBottom:   Color(red: 0.000, green: 0.831, blue: 1.000).opacity(0.08),
        auroraCenter:   Color(red: 0.000, green: 0.588, blue: 1.000).opacity(0.05),
        textPrimary:    Color(red: 0.05, green: 0.08, blue: 0.18),
        textSecondary:  Color(red: 0.05, green: 0.08, blue: 0.18).opacity(0.72)
    )

    // Nebula (magenta + violet)
    static let nebulaDark = LVPalette(
        primary:        Color(red: 0.878, green: 0.251, blue: 0.984), // #E040FB
        secondary:      Color(red: 0.486, green: 0.302, blue: 1.000), // #7C4DFF
        accent:         Color(red: 1.000, green: 0.431, blue: 0.780), // #FF6EC7
        glowPrimary:    Color(red: 0.878, green: 0.251, blue: 0.984),
        glowSecondary:  Color(red: 0.486, green: 0.302, blue: 1.000),
        surface:        Color.white.opacity(0.04),
        surfaceStroke:  Color(red: 0.878, green: 0.251, blue: 0.984).opacity(0.22),
        backgroundBase: Color(red: 0.082, green: 0.039, blue: 0.180), // #150A2E
        auroraTop:      Color(red: 1.000, green: 0.431, blue: 0.780).opacity(0.20),
        auroraBottom:   Color(red: 0.486, green: 0.302, blue: 1.000).opacity(0.18),
        auroraCenter:   Color(red: 0.878, green: 0.251, blue: 0.984).opacity(0.10),
        textPrimary:    Color.white,
        textSecondary:  Color.white.opacity(0.72)
    )

    static let nebulaLight = LVPalette(
        primary:        Color(red: 0.580, green: 0.118, blue: 0.690),
        secondary:      Color(red: 0.310, green: 0.180, blue: 0.690),
        accent:         Color(red: 0.780, green: 0.220, blue: 0.520),
        glowPrimary:    Color(red: 0.878, green: 0.251, blue: 0.984),
        glowSecondary:  Color(red: 0.486, green: 0.302, blue: 1.000),
        surface:        Color.black.opacity(0.04),
        surfaceStroke:  Color(red: 0.580, green: 0.118, blue: 0.690).opacity(0.24),
        backgroundBase: Color(red: 0.973, green: 0.945, blue: 1.000), // #F8F0FF
        auroraTop:      Color(red: 1.000, green: 0.431, blue: 0.780).opacity(0.10),
        auroraBottom:   Color(red: 0.486, green: 0.302, blue: 1.000).opacity(0.08),
        auroraCenter:   Color(red: 0.878, green: 0.251, blue: 0.984).opacity(0.05),
        textPrimary:    Color(red: 0.10, green: 0.05, blue: 0.18),
        textSecondary:  Color(red: 0.10, green: 0.05, blue: 0.18).opacity(0.72)
    )

    // Solar (amber + rose)
    static let solarDark = LVPalette(
        primary:        Color(red: 1.000, green: 0.702, blue: 0.000), // #FFB300
        secondary:      Color(red: 1.000, green: 0.361, blue: 0.553), // #FF5C8D
        accent:         Color(red: 1.000, green: 0.835, blue: 0.310), // #FFD54F
        glowPrimary:    Color(red: 1.000, green: 0.702, blue: 0.000),
        glowSecondary:  Color(red: 1.000, green: 0.361, blue: 0.553),
        surface:        Color.white.opacity(0.04),
        surfaceStroke:  Color(red: 1.000, green: 0.702, blue: 0.000).opacity(0.22),
        backgroundBase: Color(red: 0.118, green: 0.039, blue: 0.078), // #1E0A14
        auroraTop:      Color(red: 1.000, green: 0.835, blue: 0.310).opacity(0.20),
        auroraBottom:   Color(red: 1.000, green: 0.361, blue: 0.553).opacity(0.18),
        auroraCenter:   Color(red: 1.000, green: 0.702, blue: 0.000).opacity(0.10),
        textPrimary:    Color.white,
        textSecondary:  Color.white.opacity(0.72)
    )

    static let solarLight = LVPalette(
        primary:        Color(red: 0.690, green: 0.380, blue: 0.000),
        secondary:      Color(red: 0.690, green: 0.150, blue: 0.300),
        accent:         Color(red: 0.690, green: 0.560, blue: 0.000),
        glowPrimary:    Color(red: 1.000, green: 0.702, blue: 0.000),
        glowSecondary:  Color(red: 1.000, green: 0.361, blue: 0.553),
        surface:        Color.black.opacity(0.04),
        surfaceStroke:  Color(red: 0.690, green: 0.380, blue: 0.000).opacity(0.24),
        backgroundBase: Color(red: 1.000, green: 0.973, blue: 0.940), // #FFF8F0
        auroraTop:      Color(red: 1.000, green: 0.835, blue: 0.310).opacity(0.10),
        auroraBottom:   Color(red: 1.000, green: 0.361, blue: 0.553).opacity(0.08),
        auroraCenter:   Color(red: 1.000, green: 0.702, blue: 0.000).opacity(0.05),
        textPrimary:    Color(red: 0.18, green: 0.08, blue: 0.05),
        textSecondary:  Color(red: 0.18, green: 0.08, blue: 0.05).opacity(0.72)
    )
}

// MARK: - Environment injection

private struct LVPaletteKey: EnvironmentKey {
    static let defaultValue: LVPalette = .cyanGoldDark
}

extension EnvironmentValues {
    var lvPalette: LVPalette {
        get { self[LVPaletteKey.self] }
        set { self[LVPaletteKey.self] = newValue }
    }
}
