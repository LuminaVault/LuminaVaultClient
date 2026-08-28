// LuminaVaultClient/LuminaVaultClient/Components/LVTabBarMinimizeState.swift
//
// Revolut / expo-glass-tabs minimize-on-scroll: scroll down shrinks the
// floating pill (labels collapse, padding tightens); scroll up or focusing
// the bar expands it again. Rubber-band overscroll is ignored.

import SwiftUI

/// Two-state minimize driver for the floating tab bar.
///
/// This used to publish a continuous `progress: CGFloat`, written from
/// ``noteScroll(offsetY:)`` on essentially every scroll frame. Because
/// `LVTabBar` reads it and applies `.animation(_:value:)`, each of those writes
/// invalidated the whole bar *and restarted the spring* — sixty spring
/// re-targets per gesture, all of them fighting each other, behind the app's
/// busiest scroll surfaces.
///
/// The bar only ever renders two meaningful states, so the state is now the
/// discrete ``isMinimized`` and the spring runs twice per gesture: once when
/// the user commits to scrolling down, once when they commit to scrolling back
/// up. The visual result is the same two endpoints with the same spring
/// between them.
@Observable
final class LVTabBarMinimizeState {
    /// `false` = fully expanded, `true` = fully minimized.
    private(set) var isMinimized = false

    /// Directional travel accumulated since the last flip or reversal. Not
    /// observed — only ``isMinimized`` is, so scrolling that does not cross the
    /// threshold costs nothing downstream.
    @ObservationIgnored private var travel: CGFloat = 0
    @ObservationIgnored private var lastOffsetY: CGFloat?

    /// Committed travel, in points, required to flip state. Large enough that
    /// a stray finger tremor cannot cross it; small enough that a deliberate
    /// flick collapses the bar immediately.
    static let threshold: CGFloat = 12

    /// Per-frame delta below which the sample is treated as noise.
    private static let deltaFloor: CGFloat = 0.8

    /// Shared spring with the active-pill morph. This value is the one
    /// `LVMotion.snap` was derived from; the alias stays so existing call
    /// sites keep reading in tab-bar terms.
    static let spring = LVMotion.snap

    /// Drive minimize from a vertical scroll offset (contentOffset.y).
    func noteScroll(offsetY: CGFloat) {
        // Ignore top rubber-band (negative) and bottom bounce noise.
        guard offsetY >= 0 else {
            lastOffsetY = nil
            travel = 0
            return
        }
        defer { lastOffsetY = offsetY }
        guard let last = lastOffsetY else { return }

        let delta = offsetY - last
        guard abs(delta) > Self.deltaFloor else { return }

        // Reversing direction discards the travel banked the other way. That
        // is the hysteresis: crossing the threshold always takes a full 12pt of
        // *committed* movement, so a scroll that hovers at the boundary cannot
        // chatter the bar between states.
        if travel != 0, travel.sign != delta.sign { travel = 0 }
        travel += delta

        guard abs(travel) >= Self.threshold else { return }
        let next = travel > 0
        travel = 0
        guard next != isMinimized else { return }
        isMinimized = next
    }

    /// Collapse back to fully expanded.
    ///
    /// `isReduced` is the caller's `\.accessibilityReduceMotion`; the state
    /// object has no environment of its own, so the view hands it in.
    func expand(reduceMotion isReduced: Bool = false) {
        travel = 0
        guard isMinimized else { return }
        withAnimation(LVMotion.reduced(Self.spring, isReduced)) {
            isMinimized = false
        }
    }
}

private struct LVTabBarMinimizeOnScrollModifier: ViewModifier {
    @Environment(LVTabBarMinimizeState.self) private var minimize

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                minimize.noteScroll(offsetY: newOffset)
            }
    }
}

extension View {
    /// Attach to primary tab `ScrollView`s so the floating glass bar
    /// minimizes on scroll-down and expands on scroll-up.
    func lvTabBarMinimizeOnScroll() -> some View {
        modifier(LVTabBarMinimizeOnScrollModifier())
    }
}
