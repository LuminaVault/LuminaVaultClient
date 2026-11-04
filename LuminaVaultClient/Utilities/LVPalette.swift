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
    /// One step above `surface`: sheets-on-cards, selected rows, user chat
    /// bubbles. Titanium Navy in Memory Keeper.
    let surfaceElevated: Color
    /// Warm emphasis for discoveries and milestones. Use sparingly — it is
    /// the "important" gold, not a second accent.
    let highlight: Color
    /// Label colour on a `primary` fill (buttons, selected chips). Stored, not
    /// derived, because `system` resolves its primary from a dynamic asset.
    let onPrimary: Color

    /// Root background fill. Most themes map this to the system grouped
    /// background so `List` screens and `.lvBackground()` screens sit on the
    /// same colour. Memory Keeper paints its own canvas (Obsidian / Ivory, the
    /// launch screen's colours); see `usesBrandCanvas` and `lvListCanvas()`.
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
        case .cyanGold: return "Memory Keeper"
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
    /// True when `backgroundBase` is not the system grouped background, so a
    /// `List` has to hide its own background to sit on the same colour.
    var usesBrandCanvas: Bool {
        self == .cyanGoldDark || self == .cyanGoldLight
    }
}

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
        surfaceElevated: Color(uiColor: .tertiarySystemGroupedBackground),
        highlight:      Color(uiColor: .systemOrange),
        onPrimary:      Color.black,
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
        surfaceElevated: Color(uiColor: .systemBackground),
        highlight:      Color(uiColor: .systemOrange),
        onPrimary:      Color.white,
        backgroundBase: Color(uiColor: .systemGroupedBackground),
        auroraTop:      .clear,
        auroraBottom:   .clear,
        auroraCenter:   .clear,
        textPrimary:    Color(uiColor: .label),
        textSecondary:  Color(uiColor: .secondaryLabel)
    )

    // Cyan-Gold — "Memory Keeper" (default LuminaVault aesthetic, 2026-10).
    // Sampled from the key art: obsidian/navy structure, cyan for anything
    // interactive or "intelligent", gold for brand and premium moments, ivory
    // and silver for reading. Aurora washes are retired (clear) — the identity
    // has to hold with every glow off. Full table: docs/DESIGN_SYSTEM.md §3.
    static let cyanGoldDark = LVPalette(
        primary:        Color(red: 0.396, green: 0.863, blue: 0.898), // #65DCE5 Memory Cyan
        secondary:      Color(red: 0.639, green: 0.941, blue: 0.933), // #A3F0EE Neural Glow
        accent:         Color(red: 0.847, green: 0.682, blue: 0.494), // #D8AE7E Archive Gold
        glowPrimary:    Color(red: 0.396, green: 0.863, blue: 0.898),
        glowSecondary:  Color(red: 0.957, green: 0.820, blue: 0.635), // #F4D1A2 Warm Gold
        surface:        Color(red: 0.071, green: 0.114, blue: 0.176), // #121D2D Midnight Archive
        surfaceStroke:  Color(red: 0.204, green: 0.275, blue: 0.357), // #34465B Steel Blue
        surfaceElevated: Color(red: 0.110, green: 0.176, blue: 0.263), // #1C2D43 Titanium Navy
        highlight:      Color(red: 0.957, green: 0.820, blue: 0.635), // #F4D1A2 Warm Gold
        onPrimary:      Color(red: 0.039, green: 0.059, blue: 0.094), // #0A0F18 Vault Obsidian
        backgroundBase: Color(red: 0.039, green: 0.059, blue: 0.094), // #0A0F18 Vault Obsidian
        auroraTop:      .clear,
        auroraBottom:   .clear,
        auroraCenter:   .clear,
        textPrimary:    Color(red: 0.961, green: 0.945, blue: 0.914), // #F5F1E9 Ivory
        textSecondary:  Color(red: 0.659, green: 0.710, blue: 0.765)  // #A8B5C3 Muted Silver
    )

    // Light is its own palette, not an inversion: white cards on Ivory,
    // deep-navy text, and darkened cyan/gold that clear WCAG AA as text on both.
    static let cyanGoldLight = LVPalette(
        primary:        Color(red: 0.043, green: 0.431, blue: 0.471), // #0B6E78
        secondary:      Color(red: 0.055, green: 0.529, blue: 0.565), // #0E8790
        accent:         Color(red: 0.541, green: 0.392, blue: 0.141), // #8A6424
        glowPrimary:    Color(red: 0.055, green: 0.529, blue: 0.565),
        glowSecondary:  Color(red: 0.663, green: 0.486, blue: 0.208), // #A97C35
        surface:        Color.white,
        surfaceStroke:  Color(red: 0.780, green: 0.816, blue: 0.855), // #C7D0DA
        surfaceElevated: Color(red: 0.984, green: 0.976, blue: 0.961), // #FBF9F5
        highlight:      Color(red: 0.663, green: 0.486, blue: 0.208), // #A97C35
        onPrimary:      Color(red: 0.961, green: 0.945, blue: 0.914), // #F5F1E9
        backgroundBase: Color(red: 0.961, green: 0.945, blue: 0.914), // #F5F1E9 Ivory
        auroraTop:      .clear,
        auroraBottom:   .clear,
        auroraCenter:   .clear,
        textPrimary:    Color(red: 0.043, green: 0.067, blue: 0.114), // #0B111D
        textSecondary:  Color(red: 0.290, green: 0.341, blue: 0.408)  // #4A5768
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
        surfaceElevated: Color.white.opacity(0.18),
        highlight:      Color(red: 1.000, green: 0.431, blue: 0.780),
        onPrimary:      Color.black,
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
        surfaceElevated: Color.white,
        highlight:      Color(red: 0.780, green: 0.220, blue: 0.520),
        onPrimary:      Color.white,
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
        surfaceElevated: Color.white.opacity(0.18),
        highlight:      Color(red: 1.000, green: 0.835, blue: 0.310),
        onPrimary:      Color.black,
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
        surfaceElevated: Color.white,
        highlight:      Color(red: 0.690, green: 0.560, blue: 0.000),
        onPrimary:      Color.white,
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
    /// `#0A0F18` Vault Obsidian — the dark chat canvas.
    static let museCanvasDark = Color(red: 10 / 255, green: 15 / 255, blue: 24 / 255)
    /// `#1C2D43` Titanium Navy. The user's own words sit on structure, not on
    /// the interactive cyan; ivory text on it measures ≈ 12:1.
    static let museUserBubble = Color(red: 28 / 255, green: 45 / 255, blue: 67 / 255)
    /// `#121D2D` Midnight Archive — the dark agent bubble.
    static let museAgentBubbleDark = Color(red: 18 / 255, green: 29 / 255, blue: 45 / 255)
    /// White — the light agent bubble, a card on the grouped base.
    static let museAgentBubbleLight = Color.white
    /// `#F5F1E9` Ivory — text on the user bubble in both schemes.
    static let museUserText = Color(red: 245 / 255, green: 241 / 255, blue: 233 / 255)

    /// Muse tokens for `scheme`. Light keeps the palette's own base and text,
    /// which is what "existing light base" means in the contract.
    func muse(_ scheme: ColorScheme) -> LVMuseColors {
        if scheme == .dark {
            return LVMuseColors(
                canvas: Self.museCanvasDark,
                agentBubble: Self.museAgentBubbleDark,
                userBubble: Self.museUserBubble,
                userText: Self.museUserText,
                pill: Color.white.opacity(0.10),
                text: Self.museUserText,
                textSecondary: Color(red: 168 / 255, green: 181 / 255, blue: 195 / 255)
            )
        }
        return LVMuseColors(
            canvas: backgroundBase,
            agentBubble: Self.museAgentBubbleLight,
            userBubble: Self.museUserBubble,
            userText: Self.museUserText,
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
