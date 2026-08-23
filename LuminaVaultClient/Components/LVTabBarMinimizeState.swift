// LuminaVaultClient/LuminaVaultClient/Components/LVTabBarMinimizeState.swift
//
// Revolut / expo-glass-tabs minimize-on-scroll: scroll down shrinks the
// floating pill (labels collapse, padding tightens); scroll up or focusing
// the bar expands it again. Rubber-band overscroll is ignored.

import SwiftUI

@Observable
final class LVTabBarMinimizeState {
    /// 0 = fully expanded, 1 = fully minimized.
    var progress: CGFloat = 0

    private var lastOffsetY: CGFloat?

    /// Shared spring with the active-pill morph. This value is the one
    /// `LVMotion.snap` was derived from; the alias stays so existing call
    /// sites keep reading in tab-bar terms.
    static let spring = LVMotion.snap

    /// Drive minimize from a vertical scroll offset (contentOffset.y).
    func noteScroll(offsetY: CGFloat) {
        // Ignore top rubber-band (negative) and bottom bounce noise.
        guard offsetY >= 0 else {
            lastOffsetY = nil
            return
        }
        defer { lastOffsetY = offsetY }
        guard let last = lastOffsetY else { return }

        let delta = offsetY - last
        guard abs(delta) > 0.8 else { return }

        // ~80pt of travel maps to a full collapse/expand.
        let next = (progress + delta / 80).clamped(to: 0...1)
        guard abs(next - progress) > 0.002 else { return }
        progress = next
    }

    /// Collapse back to fully expanded.
    ///
    /// `isReduced` is the caller's `\.accessibilityReduceMotion`; the state
    /// object has no environment of its own, so the view hands it in.
    func expand(reduceMotion isReduced: Bool = false) {
        guard progress > 0.001 else { return }
        withAnimation(LVMotion.reduced(Self.spring, isReduced)) {
            progress = 0
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
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
