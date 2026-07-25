// LuminaVaultClient/LuminaVaultClient/Utilities/LVActiveTabEnvironment.swift
//
// Lets heavy animating surfaces (RealityKit, TimelineView, Rive) pause when
// their TabView tab is not selected. TabView keeps primary tabs mounted, so
// onDisappear alone is not enough.

import SwiftUI

private struct LVActiveTabKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    /// Current `MainTabView` selection id (`home`, `think`, `brain`, …).
    var lvActiveTab: String {
        get { self[LVActiveTabKey.self] }
        set { self[LVActiveTabKey.self] = newValue }
    }
}
