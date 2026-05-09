// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/Color+LV.swift
import SwiftUI

extension Color {
    // Brand accent colors (same in light + dark)
    static let lvCyan        = Color(red: 0.000, green: 0.831, blue: 1.000) // #00D4FF
    static let lvBlue        = Color(red: 0.000, green: 0.588, blue: 1.000) // #0096FF
    static let lvAmber       = Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B

    // Adaptive background — dark: deep navy, light: pale blue-white
    static let lvNavy = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.027, green: 0.051, blue: 0.118, alpha: 1) // #070D1E
            : UIColor(red: 0.940, green: 0.970, blue: 1.000, alpha: 1) // #F0F7FF
    })

    // Adaptive glass surface
    static let lvGlass = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.04)
            : UIColor(white: 0, alpha: 0.04)
    })

    // Adaptive borders
    static let lvBorder      = Color.lvCyan.opacity(0.18)
    static let lvBorderFocus = Color.lvCyan.opacity(0.50)

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
