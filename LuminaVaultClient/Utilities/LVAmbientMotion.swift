// LuminaVaultClient/LuminaVaultClient/Utilities/LVAmbientMotion.swift
import SwiftUI

private struct LVAmbientMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether decorative, indefinitely-repeating *ambient* motion may run —
    /// `LVHaloBackdrop`'s dust drift and `LVLogoMark`'s breathing glow. It has
    /// no effect on interaction feedback, transitions, or any motion tied to a
    /// user action.
    ///
    /// Production never sets it; the components keep gating on
    /// `\.accessibilityReduceMotion` exactly as before and this only ANDs in.
    ///
    /// It exists because `accessibilityReduceMotion` is get-only on
    /// `EnvironmentValues`, so a test cannot ask for the frozen render. A
    /// `repeatForever` animation kicked off from `onAppear` is not stopped by
    /// `transaction.disablesAnimations` either, which is precisely why
    /// `AuthLandingViewSnapshotTests` was quarantined for disagreeing with
    /// itself between runs: two captures caught the halo at different phases.
    /// This is the "static-phase seam" that quarantine note asked for.
    var lvAmbientMotionEnabled: Bool {
        get { self[LVAmbientMotionKey.self] }
        set { self[LVAmbientMotionKey.self] = newValue }
    }
}
