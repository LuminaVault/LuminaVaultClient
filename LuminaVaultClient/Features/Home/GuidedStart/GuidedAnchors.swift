// LuminaVaultClient/LuminaVaultClient/Features/Home/GuidedStart/GuidedAnchors.swift
//
// How a control tells the spotlight where it is.
//
// A target marks itself with `.guidedTarget(.sync, in: .home)`; a single
// `.overlayPreferenceValue(GuidedAnchorKey.self)` on the TabView resolves
// whatever reached it against its own geometry. That shape was measured in
// the `spike/guided-anchors` probe, not guessed, and three of its findings
// are baked into this file:
//
// 1. Anchors DO travel from a row inside an inset-grouped `List` inside a
//    per-tab `NavigationStack` up to one overlay on the `TabView`, accurate
//    to within 0.5pt. So one overlay is enough; no per-tab overlays.
//
// 2. A previously-selected tab's anchors linger in the preference forever
//    and report stale geometry — the probe drew two spotlights, one of them
//    over an unrelated row. The key therefore carries the *owning tab*
//    alongside the target so the overlay can drop everything that is not on
//    screen. The tab is passed in explicitly rather than read from
//    `\.lvActiveTab`: that environment value is the *selection*, injected on
//    the whole TabView, so every tab's content sees the same string and a
//    stale anchor would re-stamp itself as current the moment anything in
//    the background tab re-rendered. A literal at the call site cannot lie.
//
// 3. Named coordinate spaces are not an alternative. Across a tab or sheet
//    boundary `frame(in: .named(…))` silently resolves to window coordinates
//    instead of failing — a ~90pt error with no warning. Anchors only.
//
// Also measured, and a limit to design around rather than paper over:
// anchors raised inside a presented sheet never reach an overlay outside the
// sheet. A sheet that needs a spotlight needs its own overlay. None of the
// three shipped steps points inside a sheet — step 2 spotlights the Sync &
// Learn row on Home, not anything the sheet puts on top of it.

import SwiftUI

// MARK: - Key

/// Identifies one anchor: what it is, and which tab it lives on.
///
/// `GuidedTab` rather than `MainTabView.AppTab` because the coordinator
/// already owns that two-case vocabulary (`home`, `chat`) and the shell maps
/// it to the real tabs. Nothing in the guided-start core depends on the tab
/// view's enum.
struct GuidedAnchorID: Hashable, Sendable {
    let tab: GuidedTab
    let target: GuidedTarget

    init(tab: GuidedTab, target: GuidedTarget) {
        self.tab = tab
        self.target = target
    }
}

/// Carries every registered target's bounds up to the overlay.
///
/// Last writer wins on a duplicate id, which is the useful behaviour for a
/// target that is momentarily rendered twice during a transition: the newer
/// geometry is the one on screen.
enum GuidedAnchorKey: PreferenceKey {
    static let defaultValue: [GuidedAnchorID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [GuidedAnchorID: Anchor<CGRect>],
        nextValue: () -> [GuidedAnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Marking a target

extension View {
    /// Publishes this view's bounds as the guided-start `target` on `tab`.
    ///
    /// Put it on the smallest view that is actually the control being taught
    /// — the spotlight hole is this rect plus a small inset, so marking a
    /// whole section punches a hole the size of a section.
    ///
    /// `tab` is the tab the marked view *lives on*, which is a constant at
    /// every call site. It is not "the tab that is currently selected".
    func guidedTarget(_ target: GuidedTarget, in tab: GuidedTab) -> some View {
        anchorPreference(key: GuidedAnchorKey.self, value: .bounds) { anchor in
            [GuidedAnchorID(tab: tab, target: target): anchor]
        }
    }
}

// MARK: - Resolving

extension Dictionary where Key == GuidedAnchorID, Value == Anchor<CGRect> {
    /// The anchor for `target` on `tab`, or `nil`.
    ///
    /// `nil` is an ordinary, expected answer, not an error: a tab the user
    /// has never visited has never been built and publishes nothing. The
    /// probe measured that 50ms after switching to it the anchor is present
    /// and correct, so there is no first-frame lag to work around — but the
    /// overlay still has to render something sane in the meantime.
    func anchor(for target: GuidedTarget, on tab: GuidedTab?) -> Anchor<CGRect>? {
        guard let tab else { return nil }
        return self[GuidedAnchorID(tab: tab, target: target)]
    }
}
