// LuminaVaultClient/LuminaVaultClient/Utilities/LVMotion.swift
import SwiftUI

/// LuminaVault motion scale. Sibling to `LVSpacing` / `LVRadius` / `LVGlow`:
/// every `withAnimation`, `.animation(_:value:)` and `.transition` should name
/// a token here rather than an inline literal.
///
/// The values are derived from what the app already ships — 17 distinct
/// duration literals and 7 distinct spring pairs, of which `0.35/0.85` (×5)
/// and `0.3/0.7` (×2) were the de-facto house springs. Nothing here is
/// invented; the scale just names the cluster centres and drops the outliers.
///
/// High damping is the default. Only ``snap`` carries bounce, and only because
/// it rides a real scroll drag, where a little overshoot reads as momentum
/// handoff rather than decoration.
///
/// **Reduce Motion.** Do not reach for these tokens directly in a view. Use
/// ``SwiftUICore/View/lvAnimation(_:value:)``, which swaps in an opacity-safe
/// curve when `\.accessibilityReduceMotion` is on. `LVMotion.reduced(_:)` is
/// the same substitution for imperative `withAnimation` call sites.
enum LVMotion {
    // MARK: - Curves

    /// 0.12s — state flips the user should not perceive as motion at all
    /// (selection tint, enable/disable).
    static let instant = Animation.easeOut(duration: 0.12)

    /// 0.18s — small, local changes: a chip appearing, a caret, a glyph swap.
    static let quick = Animation.easeInOut(duration: 0.18)

    /// 0.25s — the workhorse. Toasts, inline cards, container reflow.
    static let standard = Animation.easeInOut(duration: 0.25)

    /// 0.4s — a change large enough to want tracking with the eye: a sheet
    /// body swapping, a hero collapsing.
    static let deliberate = Animation.easeInOut(duration: 0.4)

    /// 1.8s — ambient loops only (breathing glows, drifting backdrops). Always
    /// gate these on Reduce Motion; a slow oscillation is exactly the kind of
    /// motion that triggers vestibular discomfort.
    static let ambient = Animation.easeInOut(duration: 1.8)

    // MARK: - Springs

    /// Fast with a touch of overshoot. Reserved for motion continuing a
    /// gesture the user is still making — the tab-bar minimize, the
    /// jump-to-latest pill, composer line growth under the keyboard.
    static let snap = Animation.spring(response: 0.28, dampingFraction: 0.78)

    /// The default spring. Effectively critically damped, so it settles
    /// without a wobble; use it for anything not driven by a live drag.
    ///
    /// Named `standardSpring` rather than `standard` only because the curve
    /// scale already owns that name — this and ``standard`` are the two
    /// defaults, one timed and one physical.
    static let standardSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Slower and fully settled. For large surfaces where a fast spring would
    /// read as a snap rather than a movement.
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.9)

    // MARK: - Reduce Motion

    /// The substitute curve: short, no spring, no travel. Paired with a
    /// `.transition(.opacity)` it degrades any of the tokens above into a
    /// cross-fade, which is what "reduce motion" asks for — not "no feedback".
    static let reduceMotionFallback = Animation.easeOut(duration: 0.18)

    /// Returns `animation` normally, or the opacity-only fallback when the
    /// user has Reduce Motion on.
    ///
    /// Views should prefer ``SwiftUICore/View/lvAnimation(_:value:)``. Reach
    /// for this directly only inside a `withAnimation` block, where the
    /// environment value has to be read by the caller:
    ///
    /// ```swift
    /// @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// …
    /// withAnimation(LVMotion.reduced(LVMotion.standardSpring, reduceMotion)) { … }
    /// ```
    static func reduced(_ animation: Animation, _ isReduced: Bool) -> Animation {
        isReduced ? reduceMotionFallback : animation
    }
}

extension View {
    /// `.animation(_:value:)` that honours Reduce Motion.
    ///
    /// This is the single seam through which the app closes its Reduce-Motion
    /// gaps: pass the token you want, and the modifier substitutes
    /// ``LVMotion/reduceMotionFallback`` when the setting is on, so springs,
    /// travel and overshoot all collapse to a short cross-fade without each
    /// call site growing its own `if reduceMotion` branch.
    func lvAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(LVAnimationModifier(animation: animation, value: value))
    }

    /// Reduce-Motion-aware repeating animation. Returns the loop normally, and
    /// *no animation at all* when Reduce Motion is on — a `repeatForever` has
    /// no meaningful cross-fade equivalent, so the right degradation is for
    /// the value to settle at its resting state and stay there.
    func lvRepeatingAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(LVRepeatingAnimationModifier(animation: animation, value: value))
    }
}

private struct LVAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(LVMotion.reduced(animation, reduceMotion), value: value)
    }
}

private struct LVRepeatingAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
