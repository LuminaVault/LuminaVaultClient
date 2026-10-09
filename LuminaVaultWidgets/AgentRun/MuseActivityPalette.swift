//
//  MuseActivityPalette.swift
//  LuminaVaultWidgets
//

import SwiftUI

/// The Muse chat tokens for Lumina, dark variant. The lock screen and the
/// island are always dark surfaces, so there is no light variant here.
enum MuseActivityPalette {
    /// `muse.canvas` — `#070d1e`.
    static let canvas = Color(red: 7 / 255, green: 13 / 255, blue: 30 / 255)
    /// `muse.userBubble` / `--lv-secondary` — `#0096ff`. The ring and accents.
    static let accent = Color(red: 0, green: 150 / 255, blue: 1)
    /// `muse.pill` — white 10%. A background fill, not foreground content,
    /// so the contrast floor the rule guards does not apply.
    // swiftlint:disable:next near_invisible_opacity
    static let pill = Color.white.opacity(0.10)
    static let text = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let snag = Color(red: 1, green: 0.62, blue: 0.4)
    /// The largest text size the activity lays out for. The lock screen
    /// banner and the island have fixed heights; past this the prompt and
    /// status would clip rather than wrap.
    static let maxTypeSize = DynamicTypeSize.xxLarge
}
