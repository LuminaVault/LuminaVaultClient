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
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
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
