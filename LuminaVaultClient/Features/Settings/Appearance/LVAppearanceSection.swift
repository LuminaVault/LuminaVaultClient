// LuminaVaultClient/LuminaVaultClient/Features/Settings/Appearance/LVAppearanceSection.swift
// HER-255: Theme + light/dark switch inside Settings.
//
// Two pickers stacked inside a single Section:
//   1. Theme  — Cyan-Gold / Nebula / Solar palettes (swatches)
//   2. Mode   — System / Light / Dark (segmented)
import SwiftUI

struct LVAppearanceSection: View {
    @Environment(LVThemeManager.self) private var manager

    var body: some View {
        @Bindable var bindable = manager
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LVThemePicker(selection: $bindable.theme)

            Text("Mode")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LVAppearancePicker(selection: $bindable.appearance)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct LVThemePicker: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: LVTheme

    var body: some View {
        HStack(spacing: 14) {
            ForEach(LVTheme.allCases) { theme in
                LVThemeSwatch(
                    theme: theme,
                    isSelected: selection == theme,
                    onTap: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                            selection = theme
                        }
                    }
                )
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LVThemeSwatch: View {
    let theme: LVTheme
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: theme.swatch,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isSelected ? 56 : 48, height: isSelected ? 56 : 48)
                        .shadow(color: theme.swatch[0].opacity(0.55), radius: isSelected ? 16 : 8)
                        .shadow(color: theme.swatch[1].opacity(0.35), radius: isSelected ? 26 : 14)
                    if isSelected {
                        Circle()
                            .stroke(.white.opacity(0.85), lineWidth: 2)
                            .frame(width: 56, height: 56)
                    }
                }
                Text(theme.displayName)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

struct LVAppearancePicker: View {
    @Binding var selection: LVAppearance

    var body: some View {
        Picker("Mode", selection: $selection) {
            ForEach(LVAppearance.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}
