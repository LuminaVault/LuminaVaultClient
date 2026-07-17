// LuminaVaultClient/LuminaVaultClient/Utilities/LVTypography.swift
import SwiftUI

/// LuminaVault typography scale. Each token maps to a `Font.TextStyle` so it
/// automatically scales with Dynamic Type. Use `LVTypography` tokens instead
/// of ad-hoc `.font(.system(size:))` calls.
///
/// Migration path:
///   - `.font(.system(size: 13, weight: .heavy))`  →  `.font(LVTypography.button)`
///   - `.font(.system(size: 12))`                  →  `.font(LVTypography.caption)`
///   - `.font(.subheadline.weight(.semibold))`     →  `.font(LVTypography.fieldLabel)`
enum LVTypography {
    /// 56pt hero glyph — splash, full-screen state icons. Does NOT scale (visual anchor).
    case hero

    /// `.largeTitle` weight `.bold` — top-level screen headers.
    case display

    /// `.title2` weight `.bold` — section banners, modal titles.
    case title

    /// `.title3` weight `.semibold` — card titles, empty-state headlines.
    case subtitle

    /// `.headline` — primary copy with emphasis.
    case headline

    /// `.body` — default body copy.
    case body

    /// `.body` weight `.semibold` — CTA labels inside list rows.
    case bodyEmphasis

    /// `.callout` — secondary body / banner copy.
    case callout

    /// `.subheadline` weight `.semibold` — field labels, group headers.
    case fieldLabel

    /// `.footnote` — supporting copy below inputs, helper text.
    case footnote

    /// `.caption` — captions, badges, tab-bar text.
    case caption

    /// `.caption2` weight `.semibold` — micro tags, env badges.
    case microTag

    /// `.caption2` monospaced weight `.semibold` — identity kickers / eyebrows
    /// (`LVKickerLabel`). Pair with `.kerning(1.6)` + `.textCase(.uppercase)`.
    case kicker

    /// 13pt weight `.heavy` — primary CTA button labels (`LVButton`).
    case button

    /// 18pt weight `.bold`, monospaced digit — OTP entry, code displays.
    case otp

    /// `.body` monospaced — code blocks, server URLs, identifiers.
    case mono

    var font: Font {
        switch self {
        case .hero:         return .system(size: 56, weight: .regular)
        case .display:      return .system(.largeTitle, design: .default, weight: .bold)
        case .title:        return .system(.title2, design: .default, weight: .bold)
        case .subtitle:     return .system(.title3, design: .default, weight: .semibold)
        case .headline:     return .system(.headline, design: .default, weight: .semibold)
        case .body:         return .system(.body)
        case .bodyEmphasis: return .system(.body, design: .default, weight: .semibold)
        case .callout:      return .system(.callout)
        case .fieldLabel:   return .system(.subheadline, design: .default, weight: .semibold)
        case .footnote:     return .system(.footnote)
        case .caption:      return .system(.caption)
        case .microTag:     return .system(.caption2, design: .default, weight: .semibold)
        case .kicker:       return .system(.caption2, design: .monospaced, weight: .semibold)
        case .button:       return .system(size: 13, weight: .heavy)
        case .otp:          return .system(size: 18, weight: .bold).monospacedDigit()
        case .mono:         return .system(.body, design: .monospaced)
        }
    }
}

extension Text {
    /// Sugar so `Text("Save").lv(.button)` reads cleaner than `.font(LVTypography.button.font)`.
    func lv(_ token: LVTypography) -> Text {
        font(token.font)
    }
}

extension View {
    /// View-level overload — apply an `LVTypography` token to any view.
    func lvFont(_ token: LVTypography) -> some View {
        font(token.font)
    }
}
