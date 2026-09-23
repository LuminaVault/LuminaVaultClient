import SwiftUI
import UIKit

/// A bundle of colors that fully describes the active LuminaVault theme.
/// Resolved once per ColorScheme inside `LVTheme.palette(for:)` and injected
/// via `\.lvPalette` so every view reads from one source of truth.
struct LVPalette: Equatable {
    let primary: Color
    let secondary: Color
    let accent: Color

    let glowPrimary: Color
    let glowSecondary: Color

    // Glass-card fill. Held at 4% for a long time, which over an aurora-gradient
    // background meant cards had no discernible fill AND no edge — surfaces read
    // as flat washes rather than layers. Raised to 12% dark / 7% light, with a
    // correspondingly stronger stroke, so every card is actually bounded.
    let surface: Color           // glass-card fill (pairs with `.ultraThinMaterial`)
    let surfaceStroke: Color     // hairline border

    /// Root background fill. Every theme maps this to the system
    /// grouped background so `List` screens and `.lvBackground()` screens
    /// sit on the same colour.
    let backgroundBase: Color
    let auroraTop: Color         // top-trailing radial wash
    let auroraBottom: Color      // bottom-leading radial wash
    let auroraCenter: Color      // mid-depth pulse

    let textPrimary: Color
    let textSecondary: Color
}

/// Available palettes shown in the Settings → Appearance picker.
/// Each case knows how to materialize itself for the active color scheme.
enum LVTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case cyanGold
    case nebula
    case solar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:   return "System"
        case .cyanGold: return "Cyan Gold"
        case .nebula:   return "Nebula"
        case .solar:    return "Solar"
        }
    }

    /// Two-tone swatch shown in the theme picker.
    var swatch: [Color] {
        switch self {
        case .system:
            return [Color(uiColor: .secondaryLabel), Color.accentColor]
        case .cyanGold, .nebula, .solar:
            let p = palette(for: .dark)
            return [p.primary, p.accent]
        }
    }

    func palette(for scheme: ColorScheme) -> LVPalette {
        switch self {
        case .system:   return scheme == .dark ? .systemDark : .systemLight
        case .cyanGold: return scheme == .dark ? .cyanGoldDark : .cyanGoldLight
        case .nebula:   return scheme == .dark ? .nebulaDark   : .nebulaLight
        case .solar:    return scheme == .dark ? .solarDark    : .solarLight
        }
    }
}

// MARK: - Concrete palettes

extension LVPalette {
    // System — native iOS semantic colors; no custom aurora identity.
    static let systemDark = LVPalette(
        primary:        Color.accentColor,
        secondary:      Color(uiColor: .systemBlue),
        accent:         Color(uiColor: .systemOrange),
        glowPrimary:    Color.accentColor,
        glowSecondary:  Color(uiColor: .systemIndigo),
        surface:        Color(uiColor: .secondarySystemGroupedBackground).opacity(0.72),
        surfaceStroke:  Color(uiColor: .separator),
        backgroundBase: Color(uiColor: .systemGroupedBackground),
        auroraTop:      .clear,
        auroraBottom:   .clear,
        auroraCenter:   .clear,
        textPrimary:    Color(uiColor: .label),
        textSecondary:  Color(uiColor: .secondaryLabel)
    )

    static let systemLight = LVPalette(
        primary:        Color.accentColor,
        secondary:      Color(uiColor: .systemBlue),
        accent:         Color(uiColor: .systemOrange),
        glowPrimary:    Color.accentColor,
        glowSecondary:  Color(uiColor: .systemIndigo),
        surface:        Color(uiColor: .secondarySystemGroupedBackground).opacity(0.88),
        surfaceStroke:  Color(uiColor: .separator),
        backgroundBase: Color(uiColor: .systemGroupedBackground),
        auroraTop:      .clear,
        auroraBottom:   .clear,
        auroraCenter:   .clear,
        textPrimary:    Color(uiColor: .label),
        textSecondary:  Color(uiColor: .secondaryLabel)
    )

    // Cyan-Gold (default LuminaVault aesthetic)
    static let cyanGoldDark = LVPalette(
        primary:        Color(red: 0.000, green: 0.831, blue: 1.000), // #00D4FF cyan
        secondary:      Color(red: 0.000, green: 0.588, blue: 1.000), // #0096FF blue
        accent:         Color(red: 0.961, green: 0.620, blue: 0.043), // #F59E0B amber
        glowPrimary:    Color(red: 0.000, green: 0.831, blue: 1.000),
        glowSecondary:  Color(red: 0.961, green: 0.620, blue: 0.043),
        surface:        Color.white.opacity(0.12),
        surfaceStroke:  Color(red: 0.000, green: 0.831, blue: 1.000).opacity(0.38),
        backgroundBase: Color(uiColor: .systemGroupedBackground),
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
        surface:        Color.black.opacity(0.07),
        surfaceStroke:  Color(red: 0.000, green: 0.494, blue: 0.658).opacity(0.34),
        backgroundBase: Color(uiColor: .systemGroupedBackground),
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
        surface:        Color.white.opacity(0.12),
        surfaceStroke:  Color(red: 0.878, green: 0.251, blue: 0.984).opacity(0.38),
        backgroundBase: Color(uiColor: .systemGroupedBackground),
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
        surface:        Color.black.opacity(0.07),
        surfaceStroke:  Color(red: 0.580, green: 0.118, blue: 0.690).opacity(0.34),
        backgroundBase: Color(uiColor: .systemGroupedBackground),
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
        surface:        Color.white.opacity(0.12),
        surfaceStroke:  Color(red: 1.000, green: 0.702, blue: 0.000).opacity(0.38),
        backgroundBase: Color(uiColor: .systemGroupedBackground),
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
        surface:        Color.black.opacity(0.07),
        surfaceStroke:  Color(red: 0.690, green: 0.380, blue: 0.000).opacity(0.34),
        backgroundBase: Color(uiColor: .systemGroupedBackground),
        auroraTop:      Color(red: 1.000, green: 0.835, blue: 0.310).opacity(0.10),
        auroraBottom:   Color(red: 1.000, green: 0.361, blue: 0.553).opacity(0.08),
        auroraCenter:   Color(red: 1.000, green: 0.702, blue: 0.000).opacity(0.05),
        textPrimary:    Color(red: 0.18, green: 0.08, blue: 0.05),
        textSecondary:  Color(red: 0.18, green: 0.08, blue: 0.05).opacity(0.72)
    )
}

// MARK: - Muse chat tokens

/// The Muse chat surface's semantic colours (`_reviews/muse-chat-contract.md`).
///
/// Separate from the theme palette on purpose: the contract fixes these per
/// app rather than per theme, so the chat reads the same whichever theme is
/// picked. Dark-first with a light variant — the scheme decides, never the
/// chat (no forced dark).
struct LVMuseColors: Equatable {
    let canvas: Color
    let agentBubble: Color
    let userBubble: Color
    let userText: Color
    let pill: Color
    let text: Color
    let textSecondary: Color
}

extension LVPalette {
    /// `#070d1e` — the dark chat canvas.
    static let museCanvasDark = Color(red: 7 / 255, green: 13 / 255, blue: 30 / 255)
    /// Contract value is `#0096ff` (`--lv-secondary`), but white body text on
    /// it measures 3.09:1 and fails WCAG AA. `#0074DA` keeps the hue and
    /// measures 4.66:1.
    static let museUserBubble = Color(red: 0 / 255, green: 116 / 255, blue: 218 / 255)
    /// Tailwind gray-100, the light agent bubble.
    static let museAgentBubbleLight = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)

    /// Muse tokens for `scheme`. Light keeps the palette's own base and text,
    /// which is what "existing light base" means in the contract.
    func muse(_ scheme: ColorScheme) -> LVMuseColors {
        if scheme == .dark {
            return LVMuseColors(
                canvas: Self.museCanvasDark,
                agentBubble: Color.white.opacity(0.07),
                userBubble: Self.museUserBubble,
                userText: .white,
                pill: Color.white.opacity(0.10),
                text: .white,
                textSecondary: Color.white.opacity(0.72)
            )
        }
        return LVMuseColors(
            canvas: backgroundBase,
            agentBubble: Self.museAgentBubbleLight,
            userBubble: Self.museUserBubble,
            userText: .white,
            pill: Color.black.opacity(0.06),
            text: textPrimary,
            textSecondary: textSecondary
        )
    }
}

/// Muse geometry. Bubble radius and width caps come from the contract.
enum LVMuse {
    static let bubbleRadius: CGFloat = 24
    static let cardRadius: CGFloat = 16
    static let avatarSize: CGFloat = 110
    static let userBubbleWidth: CGFloat = 0.85
    static let agentBubbleWidth: CGFloat = 0.94
    static let scrimHeight: CGFloat = 120
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
