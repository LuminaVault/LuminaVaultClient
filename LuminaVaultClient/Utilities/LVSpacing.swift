// LuminaVaultClient/LuminaVaultClient/Utilities/LVSpacing.swift
import SwiftUI

/// LuminaVault spacing scale. 4pt base grid. Use these tokens for any `padding`,
/// `spacing`, `frame`, or layout offset. Raw point literals in feature code are
/// considered tech debt — replace incrementally as files are touched.
enum LVSpacing {
    /// 2pt — hairline separation.
    public static let hairline: CGFloat = 2

    /// 4pt — tight intra-component spacing (icon ↔ label).
    public static let xs: CGFloat = 4

    /// 8pt — small spacing (chip padding, badge gutter).
    public static let sm: CGFloat = 8

    /// 12pt — default vertical rhythm inside cards.
    public static let md: CGFloat = 12

    /// 16pt — standard padding and inter-section gutter.
    public static let base: CGFloat = 16

    /// 20pt — list-row vertical padding, comfortable inset.
    public static let lg: CGFloat = 20

    /// 24pt — section margin, dialog inset.
    public static let xl: CGFloat = 24

    /// 32pt — major group separation.
    public static let xxl: CGFloat = 32

    /// 48pt — hero spacing on splash and empty states.
    public static let hero: CGFloat = 48

    /// 64pt — top-of-screen drop above hero content.
    public static let heroTop: CGFloat = 64
}

/// Component sizing tokens — for surfaces whose dimensions are part of the
/// design language (button heights, tab-bar heights, icon sizes).
enum LVSize {
    /// 48pt — primary CTA button height (`HVButton`).
    public static let buttonHeight: CGFloat = 48

    /// 56pt — secondary surface height (large CTA, search bar).
    public static let largeControlHeight: CGFloat = 56

    /// 22pt — tab-bar glyph size (`LVTabBar`).
    public static let tabBarGlyph: CGFloat = 22

    /// 28pt — list-row leading glyph.
    public static let rowGlyph: CGFloat = 28

    /// 220pt — empty-state Rive mascot.
    public static let mascotSmall: CGFloat = 220

    /// 320pt — splash / onboarding hero size.
    public static let heroLarge: CGFloat = 320
}

/// Radius tokens used by `lvGlassCard`, pills, sheets.
enum LVRadius {
    public static let pill: CGFloat = 999
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let card: CGFloat = 20
    public static let sheet: CGFloat = 28
}
