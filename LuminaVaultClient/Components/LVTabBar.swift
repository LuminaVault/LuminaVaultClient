// LuminaVaultClient/LuminaVaultClient/Components/LVTabBar.swift
// HER-255: custom glow tab bar. Replaces stock TabView chrome with a glass
// background + glowing underline on the active tab. Wires a "pending insights"
// pulse on the Home tab.
// HER-107: split into N primary items + a trailing More button. The bar
// renders the first `primaryItems` inline and packs everything else into
// a Menu attached to the More button. When an overflow item is the
// active tab, More's icon swaps to that item's icon (Apple HIG — the
// More tab represents the active overflow selection).
import SwiftUI

/// One entry in the LuminaVault tab bar.
///
/// HER-291: `icon` is now an `LVIcon` token. The token carries both
/// the SF Symbol fallback and the optional `Lumina/Tab/*` branded asset
/// path, so callers no longer pair `systemImage:` + `customImageName:`
/// by hand.
struct LVTabItem: Identifiable, Equatable {
    /// Stable identity — used as the TabView selection value.
    let id: String
    /// Display label below the icon.
    let label: String
    /// Token-resolved icon. Tab-flavoured cases (`.tabHome`, `.tabSpaces`,
    /// …) carry a `Lumina/Tab/*` custom asset; other cases fall through
    /// to their SF Symbol.
    let icon: LVIcon
    /// When true, the tab pulses softly to invite attention. The Home tab
    /// uses this for "you have new insights waiting".
    let pulses: Bool

    init(
        id: String,
        label: String,
        icon: LVIcon,
        pulses: Bool = false
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.pulses = pulses
    }
}

struct LVTabBar: View {
    @Environment(\.lvPalette) private var palette
    let primaryItems: [LVTabItem]
    let overflowItems: [LVTabItem]
    /// When true, the More overflow ("...") button renders as the FIRST
    /// (leading) item instead of trailing. Used to make the Menu the first
    /// option on the tab bar.
    let overflowLeading: Bool
    @Binding var selection: String
    private let underlineNamespace: Namespace.ID

    init(
        primaryItems: [LVTabItem],
        overflowItems: [LVTabItem] = [],
        overflowLeading: Bool = false,
        selection: Binding<String>,
        underlineNamespace: Namespace.ID
    ) {
        self.primaryItems = primaryItems
        self.overflowItems = overflowItems
        self.overflowLeading = overflowLeading
        self._selection = selection
        self.underlineNamespace = underlineNamespace
    }

    /// Active overflow item, or nil when the active tab is a primary one.
    private var activeOverflowItem: LVTabItem? {
        overflowItems.first(where: { $0.id == selection })
    }

    /// The More button's display item. Reflects the active overflow item
    /// when one is selected; otherwise the neutral "More" affordance.
    private var moreItem: LVTabItem {
        if let active = activeOverflowItem {
            return LVTabItem(
                id: "lv.tab.more",
                label: active.label,
                icon: active.icon,
            )
        }
        return LVTabItem(id: "lv.tab.more", label: "More", icon: .ellipsis)
    }

    var body: some View {
        HStack(spacing: 0) { // zero-gap intentional — primary items flex equal-width
            if overflowLeading {
                moreButton
            }
            ForEach(primaryItems) { item in
                LVTabBarButton(
                    item: item,
                    isActive: item.id == selection,
                    underlineNamespace: underlineNamespace,
                    onTap: { selectWithAnimation(item.id) }
                )
                .frame(maxWidth: .infinity)
            }
            if !overflowLeading {
                moreButton
            }
        }
        .padding(.horizontal, LVSpacing.sm)
        .padding(.top, LVSpacing.sm)
        .padding(.bottom, LVSpacing.sm)
        .background {
            // HER-255 redesign — deep frosted "glass" slab. The base material
            // is darkened with a `backgroundBase` wash so the holographic icons
            // and active pill read with high contrast, and the top edge gets a
            // cyan-tinted "lit rim" (hairline + soft glow) for the sci-fi look.
            ZStack(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(palette.backgroundBase.opacity(0.6))
                LinearGradient(
                    colors: [palette.backgroundBase.opacity(0.35), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                Rectangle()
                    .fill(palette.glowPrimary.opacity(0.28))
                    .frame(height: 0.75)
                    .shadow(color: palette.glowPrimary.opacity(0.18), radius: 8, y: -2)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The More overflow button. Rendered leading or trailing per
    /// `overflowLeading`; hidden entirely when there are no overflow items.
    @ViewBuilder
    private var moreButton: some View {
        if !overflowItems.isEmpty {
            LVTabBarMoreButton(
                item: moreItem,
                isActive: activeOverflowItem != nil,
                overflowItems: overflowItems,
                selection: $selection,
                underlineNamespace: underlineNamespace,
            )
            .frame(maxWidth: .infinity)
        }
    }

    private func selectWithAnimation(_ id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            selection = id
        }
    }
}

private struct LVTabBarButton: View {
    let item: LVTabItem
    let isActive: Bool
    let underlineNamespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            LVTabBarItemContent(
                item: item,
                isActive: isActive,
                underlineNamespace: underlineNamespace,
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

private struct LVTabBarMoreButton: View {
    let item: LVTabItem
    let isActive: Bool
    let overflowItems: [LVTabItem]
    @Binding var selection: String
    let underlineNamespace: Namespace.ID

    // HER-bugfix — the overflow trigger was a SwiftUI `Menu`, whose label is
    // hosted in a separate UIHostingController. The label's
    // `matchedGeometryEffect` (shared `underlineNamespace` with the primary
    // tabs) then reparents across that hosting boundary, spamming
    // `_UIReparentingView ... is not supported` plus
    // `UIContextMenuInteraction updateVisibleMenuWithBlock` on every tap.
    // A plain Button keeps the label in the same hosting controller as the
    // primary tabs (which never warn); a confirmationDialog replaces the
    // dropdown without any UIMenu/context-menu interaction.
    @State private var showOverflow = false

    var body: some View {
        Button {
            showOverflow = true
        } label: {
            LVTabBarItemContent(
                item: item,
                isActive: isActive,
                underlineNamespace: underlineNamespace,
            )
        }
        .buttonStyle(.plain)
        .confirmationDialog("More", isPresented: $showOverflow, titleVisibility: .visible) {
            ForEach(overflowItems) { overflowItem in
                Button(overflowItem.label) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        selection = overflowItem.id
                    }
                }
            }
        }
        .accessibilityLabel(isActive ? "More — \(item.label) active" : "More")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

/// Pure visual content for one tab bar item. Wrapped in either a `Button`
/// (regular primary tab) or a `Menu` (More overflow trigger). Kept
/// separate so the Menu's label doesn't nest a Button — SwiftUI menus
/// don't combine cleanly with inner Buttons.
private struct LVTabBarItemContent: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LVTabItem
    let isActive: Bool
    let underlineNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: LVSpacing.xs) {
            ZStack {
                // HER-255 redesign — orbiting sparkle shimmer behind the active
                // icon. Reuses `SparkleField` (30fps-throttled Canvas that goes
                // static under Reduce Motion). Only the active tab mounts it, so
                // at most one particle field is ever alive.
                if isActive {
                    SparkleField(
                        density: 6,
                        maxRadius: 1.4,
                        driftSpeed: 0.8,
                        colors: [palette.primary, palette.accent, .white]
                    )
                    .frame(width: 34, height: 34)
                    .allowsHitTesting(false)
                }
                iconView
                    .frame(width: 26, height: 26)
            }
            .lvPulse(active: item.pulses && !reduceMotion)
            Text(item.label)
                .font(LVTypography.microTag.font.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? palette.primary : palette.textSecondary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, LVSpacing.sm)
        .padding(.vertical, LVSpacing.xs)
        .background {
            // HER-255 redesign — glowing active "pill" wrapping icon+label.
            // Slides between tabs via `matchedGeometryEffect` on the shared
            // `underlineNamespace` (driven by `selectWithAnimation`'s spring),
            // replacing the old circle-blur + underline-capsule pair.
            if isActive {
                activePill
            }
        }
        .contentShape(Rectangle())
    }

    /// Volumetric active highlight: a cyan-gradient rounded-rect with a glowing
    /// stroke and soft outer shadow. Theme-tinted via `palette.glowPrimary`.
    private var activePill: some View {
        RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        palette.glowPrimary.opacity(0.22),
                        palette.glowPrimary.opacity(0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                    .stroke(palette.glowPrimary.opacity(0.5), lineWidth: 1)
            }
            .shadow(color: palette.glowPrimary.opacity(0.45), radius: 12)
            .matchedGeometryEffect(id: "activeTabPill", in: underlineNamespace)
    }

    // HER-291 — name + custom-asset resolution comes from `LVIcon`,
    // but rendering stays tab-specific: branded `Lumina/Tab/*` glyphs
    // load with `renderingMode(.original)` so the full-colour artwork
    // shows through, with saturation damping on inactive tabs.
    // `LVIconView` is intentionally NOT used here — it forces template
    // rendering, which would flatten the brand artwork to a single
    // tint and break the existing tab-bar look.
    //
    // HER-255 redesign — the active icon gets a holographic treatment: a
    // blurred, cyan-multiplied bloom copy sits behind the sharp glyph, plus a
    // saturation lift and a cyan drop-shadow. Inactive icons stay dim and
    // desaturated.
    @ViewBuilder
    private var iconView: some View {
        if let assetName = item.icon.customAssetName,
           UIImage(named: assetName) != nil {
            ZStack {
                if isActive {
                    Image(assetName)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .blur(radius: 6)
                        .colorMultiply(palette.glowPrimary)
                        .opacity(0.7)
                }
                Image(assetName)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .saturation(isActive ? 1.15 : 0.55)
                    .opacity(isActive ? 1.0 : 0.75)
                    .shadow(color: isActive ? palette.glowPrimary.opacity(0.7) : .clear, radius: 8)
            }
        } else {
            Image(systemName: item.icon.sfSymbol)
                .font(.system(size: LVSize.tabBarGlyph, weight: .medium))
                .foregroundStyle(isActive ? palette.primary : palette.textSecondary.opacity(0.85))
                .shadow(color: isActive ? palette.glowPrimary.opacity(0.7) : .clear, radius: 8)
        }
    }
}
