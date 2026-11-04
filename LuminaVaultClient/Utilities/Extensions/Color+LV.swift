// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/Color+LV.swift
import SwiftUI

extension Color {
    // Brand accents — Memory Keeper (2026-10). Adaptive since the retune: the
    // dark values are the key-art colours, the light values are darkened to
    // clear WCAG AA as text on white. Prefer `palette.*`; these exist for the
    // call sites that predate the environment palette.
    static let lvCyan = adaptive(dark: (0x65, 0xDC, 0xE5), light: (0x0B, 0x6E, 0x78))   // Memory Cyan
    static let lvBlue = adaptive(dark: (0xA3, 0xF0, 0xEE), light: (0x0E, 0x87, 0x90))   // Neural Glow
    static let lvAmber = adaptive(dark: (0xD8, 0xAE, 0x7E), light: (0x8A, 0x64, 0x24))  // Archive Gold

    // Adaptive background — dark: Vault Obsidian, light: Ivory
    static let lvNavy = adaptive(dark: (0x0A, 0x0F, 0x18), light: (0xF5, 0xF1, 0xE9))

    // Adaptive surface — dark: Midnight Archive, light: white card
    static let lvGlass = adaptive(dark: (0x12, 0x1D, 0x2D), light: (0xFF, 0xFF, 0xFF))

    // Adaptive borders — Steel Blue hairline; focus is the interactive cyan
    static let lvBorder = adaptive(dark: (0x34, 0x46, 0x5B), light: (0xC7, 0xD0, 0xDA))
    static let lvBorderFocus = Color.lvCyan.opacity(0.70)

    private static func adaptive(dark: (Int, Int, Int), light: (Int, Int, Int)) -> Color {
        Color(uiColor: UIColor { tc in
            let c = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
        })
    }

    // Adaptive text
    static let lvTextPrimary = Color(uiColor: .label)
    static let lvTextSub = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.45)
            : UIColor(white: 0, alpha: 0.50)
    })
    static let lvTextMuted = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.28)
            : UIColor(white: 0, alpha: 0.32)
    })
}
