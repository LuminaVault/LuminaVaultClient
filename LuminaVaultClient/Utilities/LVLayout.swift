// LuminaVaultClient/LuminaVaultClient/Utilities/LVLayout.swift
import SwiftUI

/// Layout tokens for chrome the app draws *over* its content, so scroll
/// surfaces can reserve room for it by name instead of by magic number.
///
/// Sibling to `LVSpacing` / `LVSize` / `LVRadius`. Everything here is a
/// clearance, not a spacing value — reach for `LVSpacing` for rhythm inside a
/// layout and for `LVLayout` only when something floats above the content.
enum LVLayout {
    /// 120pt — room a tab-hosted scroll surface leaves below its last row so
    /// content clears the floating `LVTabBar`.
    ///
    /// The bar publishes 88pt through `LVTabBarHeightKey` when it carries the
    /// raised Capture disc (72pt without); the remainder is breathing room so
    /// the final card does not sit flush against the glass capsule.
    ///
    /// Apply it as `.contentMargins(.bottom, LVLayout.tabBarClearance, for:
    /// .scrollContent)` rather than as a trailing spacer view: an inset keeps
    /// the scroll indicators and the refresh control positioned correctly,
    /// where a spacer is just an extra row the scroll has to lay out.
    static let tabBarClearance: CGFloat = 120
}
