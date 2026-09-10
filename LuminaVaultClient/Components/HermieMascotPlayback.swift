// LuminaVaultClient/LuminaVaultClient/Components/HermieMascotPlayback.swift
//
// The one decision `HermieMascotView` makes about its Rive state machine:
// run, or hold a frame. Pulled out of the view so it can be pinned without
// a Rive runtime, and so the snapshot suites' `\.lvAmbientMotionEnabled`
// seam reaches the mascot like it reaches every other ambient animation.
import Foundation

enum HermieMascotPlayback {
    /// - reduceMotion: the system accessibility setting; always wins.
    /// - ambientMotionEnabled: `\.lvAmbientMotionEnabled` — production never
    ///   sets it, snapshot tests set it false to capture a static frame.
    /// - sceneActive: offscreen Rive canvases must not burn CPU.
    /// - hostTab / activeTab: `TabView` keeps sibling tabs mounted, so a
    ///   mascot hosted on one tab only plays while that tab is the active
    ///   one. An empty `activeTab` means no tab has published yet → play.
    static func shouldPlay(
        reduceMotion: Bool,
        ambientMotionEnabled: Bool,
        sceneActive: Bool,
        hostTab: String?,
        activeTab: String
    ) -> Bool {
        guard !reduceMotion, ambientMotionEnabled, sceneActive else { return false }
        guard let hostTab else { return true }
        if activeTab.isEmpty { return true }
        return activeTab == hostTab
    }
}
