// LuminaVaultClient/LuminaVaultClient/Utilities/LVTheme.swift
import SwiftUI

enum LVAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case dark   = "Dark"
    case light  = "Light"
    var id: String { rawValue }
    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }
}

@Observable
final class LVThemeManager {
    var appearance: LVAppearance = .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "lv_appearance") }
    }
    init() {
        let saved = UserDefaults.standard.string(forKey: "lv_appearance") ?? ""
        appearance = LVAppearance(rawValue: saved) ?? .system
    }
}
