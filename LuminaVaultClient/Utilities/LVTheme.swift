// LuminaVaultClient/LuminaVaultClient/Utilities/LVTheme.swift
import SwiftUI

enum LVAppearance: String, CaseIterable, Identifiable, Codable {
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
    private static let appearanceKey = "lv_appearance"
    private static let themeKey = "lv_theme"

    var appearance: LVAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    var theme: LVTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    init() {
        let savedAppearance = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? ""
        appearance = LVAppearance(rawValue: savedAppearance) ?? .system

        let savedTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? ""
        theme = LVTheme(rawValue: savedTheme) ?? .system
    }

    /// Resolve the active palette given the current system color scheme.
    /// Honors any explicit appearance override the user has selected.
    func palette(systemScheme: ColorScheme) -> LVPalette {
        let resolved = appearance.colorSchemeOverride ?? systemScheme
        return theme.palette(for: resolved)
    }
}

// MARK: - Environment + theming modifier

private struct LVThemeManagerKey: EnvironmentKey {
    static let defaultValue: LVThemeManager? = nil
}

extension EnvironmentValues {
    var lvThemeManager: LVThemeManager? {
        get { self[LVThemeManagerKey.self] }
        set { self[LVThemeManagerKey.self] = newValue }
    }
}

extension View {
    /// Applies the user-selected appearance override + injects the resolved palette
    /// into the environment under `\.lvPalette`. Apply once at the scene root.
    func lvThemed(_ manager: LVThemeManager) -> some View {
        modifier(LVThemingModifier(manager: manager))
    }
}

private struct LVThemingModifier: ViewModifier {
    @Bindable var manager: LVThemeManager
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        content
            .environment(\.lvPalette, manager.palette(systemScheme: systemScheme))
            .environment(\.lvThemeManager, manager)
            .preferredColorScheme(manager.appearance.colorSchemeOverride)
    }
}
