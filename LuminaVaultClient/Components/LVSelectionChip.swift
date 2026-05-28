// LuminaVaultClient/LuminaVaultClient/Components/LVSelectionChip.swift
//
// HER-100 — reusable selection chip used by the SOUL.md quiz chip
// grids (single-select tone, multi-select priorities, single-select
// format/length). Pure presentation: the caller owns the boolean
// `isSelected` and the tap closure.

import SwiftUI

struct LVSelectionChip: View {
    let label: String
    let isSelected: Bool
    var systemImage: String?
    let action: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: LVSpacing.sm) {
                if let systemImage {
                    // HER-291: kept as Image — runtime symbol name
                    Image(systemName: systemImage)
                        .font(LVTypography.fieldLabel.font)
                }
                Text(label)
                    .font(LVTypography.fieldLabel.font)
            }
            .padding(.vertical, LVSpacing.md)
            .padding(.horizontal, LVSpacing.base)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? palette.accent.opacity(0.18) : palette.surface)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? palette.accent : palette.surfaceStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
