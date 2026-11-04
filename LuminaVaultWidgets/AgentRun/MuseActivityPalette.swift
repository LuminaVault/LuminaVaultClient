//
//  MuseActivityPalette.swift
//  LuminaVaultWidgets
//

import SwiftUI

/// The Muse chat tokens for Lumina, dark variant. The lock screen and the
/// island are always dark surfaces, so there is no light variant here.
enum MuseActivityPalette {
    /// `muse.canvas` — `#0a0f18` Vault Obsidian.
    static let canvas = Color(red: 10 / 255, green: 15 / 255, blue: 24 / 255)
    /// `--lv-primary` — `#65dce5` Memory Cyan. The ring and accents.
    static let accent = Color(red: 101 / 255, green: 220 / 255, blue: 229 / 255)
    /// `muse.pill` — white 10%. A background fill, not foreground content,
    /// so the contrast floor the rule guards does not apply.
    // swiftlint:disable:next near_invisible_opacity
    static let pill = Color.white.opacity(0.10)
    /// `#f5f1e9` Ivory.
    static let text = Color(red: 245 / 255, green: 241 / 255, blue: 233 / 255)
    /// `#a8b5c3` Muted Silver.
    static let textSecondary = Color(red: 168 / 255, green: 181 / 255, blue: 195 / 255)
    static let snag = Color(red: 1, green: 0.62, blue: 0.4)
    /// The largest text size the activity lays out for. The lock screen
    /// banner and the island have fixed heights; past this the prompt and
    /// status would clip rather than wrap.
    static let maxTypeSize = DynamicTypeSize.xxLarge
}
