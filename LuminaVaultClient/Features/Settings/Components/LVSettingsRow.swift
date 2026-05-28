// LuminaVaultClient/LuminaVaultClient/Features/Settings/Components/LVSettingsRow.swift
//
// HER-303 — reusable nav row for `LVSectionCard`. Two variants:
//   * Plain title row → chevron + push into `destination`.
//   * Trailing-slot row → custom trailing view (e.g. ConnectionBadge)
//     between the title and the chevron.
//
// Replaces the inline `settingsRow` / Hermes Gateway bespoke row
// from `SettingsRootView`.

import SwiftUI

struct LVSettingsRow<Trailing: View, Destination: View>: View {
    @Environment(\.lvPalette) private var palette

    let title: String
    let icon: LVIcon
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let destination: () -> Destination

    init(
        _ title: String,
        icon: LVIcon,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
        self.destination = destination
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: LVSpacing.base) {
                LVIconView(icon, size: 18, tint: palette.glowPrimary, weight: .medium)
                    .frame(width: LVSize.rowGlyph)

                Text(title)
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)

                Spacer(minLength: LVSpacing.sm)

                trailing()

                LVIconView(
                    .chevronRight,
                    size: 12,
                    tint: palette.textSecondary.opacity(0.5),
                    weight: .semibold
                )
            }
            .padding(.vertical, LVSpacing.md)
            .padding(.horizontal, LVSpacing.base)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lvGlowPress()
    }
}

extension LVSettingsRow where Trailing == EmptyView {
    init(
        _ title: String,
        icon: LVIcon,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.init(title, icon: icon, trailing: { EmptyView() }, destination: destination)
    }
}

/// Hairline divider between rows inside an `LVSectionCard`.
struct LVSettingsDivider: View {
    @Environment(\.lvPalette) private var palette
    var body: some View {
        Divider()
            .background(palette.surfaceStroke)
            .padding(.leading, LVSpacing.xxl + LVSpacing.lg)
    }
}
