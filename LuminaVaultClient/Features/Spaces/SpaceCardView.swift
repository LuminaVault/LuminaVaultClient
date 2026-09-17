// LuminaVaultClient/LuminaVaultClient/Features/Spaces/SpaceCardView.swift
//
// HER-35: tile rendered in the LazyVGrid on the Spaces home.
//
// A plain grouped-background card. The glass fill, the cyan glow stroke and
// the glyph's halo went with the rest of the cinematic chrome: a grid of
// glowing tiles reads as decoration, and what the user is scanning for is the
// name and the count. The brand survives as the glyph's tint.
//
// Edit / Delete stay on a long-press `contextMenu` rather than a visible "…"
// per tile — also what keeps the `_UIReparentingView` warning away that a
// per-card `Menu` popover fired through `UIHostingController`.
//
// Server-supplied SF Symbol icon names still map to `LVIcon` cases so the
// cards pick up the branded `Lumina/Icons/*` PNGs (HER-301).
import SwiftUI

struct SpaceCardView: View {

    @Environment(\.lvPalette) private var palette

    let space: SpaceDTO
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LVIconView(
                Self.resolveIcon(space.icon),
                size: 32,
                tint: palette.accent,
                weight: .regular,
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("^[\(space.noteCount) note](inflect: true)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(LVSpacing.base)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
        )
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: LVIcon.sliderHorizontal3.sfSymbol)
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: LVIcon.trash.sfSymbol)
            }
        }
    }

    /// HER-307 — server returns an SF Symbol name (or nil). Map common
    /// values to `LVIcon` cases so cards pick up the branded glyph.
    /// Unknown / unset icons fall back to `.scrollWinged` (the winged
    /// scroll mark matches the Stitch reference for generic spaces).
    private static func resolveIcon(_ raw: String?) -> LVIcon {
        switch raw {
        case "brain.head.profile", "brain":     return .brainHeadProfile
        case "heart.fill", "heart":             return .heartWinged
        case "lightbulb.fill", "lightbulb":     return .lightbulbFill
        case "chart.line.uptrend.xyaxis",
             "chart.xyaxis.line":               return .chartUp
        case "briefcase.fill", "briefcase":     return .briefcase
        case "lock.shield.fill", "lock.shield": return .shieldBrain
        case "doc.text.fill", "doc.text",
             "scroll.fill", "scroll":           return .scrollWinged
        case "folder.fill", "folder":           return .layers
        case "house.fill", "house":             return .homeGlow
        case "camera.aperture", "camera.fill",
             "camera":                          return .cameraAperture
        case "mic.fill", "mic":                 return .micFill
        case "link", "link.circle":             return .linkCircle
        case "wand.and.stars":                  return .wandSparkle
        case "key.fill", "key":                 return .skeletonKeyPremium
        default:                                return .scrollWinged
        }
    }
}
