// LuminaVaultClient/LuminaVaultClient/Features/Spaces/SpaceCardView.swift
//
// HER-35: tile rendered in the LazyVGrid on the Spaces home.
// HER-307: cinematic upgrade —
//   * Drops the visible "…" Menu chrome (Stitch reference shows clean
//     glass tiles); Edit / Delete moved to a long-press `contextMenu`
//     attached to the whole card. Also kills the noisy
//     `_UIReparentingView` warning that fired every time SwiftUI's
//     Menu popover re-parented through UIHostingController.
//   * Maps server-supplied SF Symbol icon names to `LVIcon` cases so
//     the cards pick up the branded `Lumina/Icons/*` PNGs (HER-301).
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
                size: 36,
                tint: palette.glowPrimary,
                weight: .light,
            )
            .shadow(color: palette.glowPrimary.opacity(0.6), radius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)

                Text("\(space.noteCount) \(space.noteCount == 1 ? "note" : "notes")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.glowPrimary)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .lvGlassCard(cornerRadius: 24, intensity: 0.7)
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
