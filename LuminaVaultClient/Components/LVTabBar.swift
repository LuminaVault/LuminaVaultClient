// LuminaVaultClient/LuminaVaultClient/Components/LVTabBar.swift
// HER-255: custom glow tab bar. Replaces stock TabView chrome with a glass
// background + glowing underline on the active tab. Wires a "pending insights"
// pulse on the Home tab.
//
// iOS 26+ uses the native `GlassEffectContainer` + `.glassEffect` for the
// liquid glass capsule. Older deployment targets fall back to
// `.ultraThinMaterial` + subtle stroke.
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
        Group {
            if #available(iOS 26.0, *) {
                // Floating Liquid Glass capsule (iOS 26+ `.glassEffect`). Icon-only,
                // inset from the screen edges, sitting above the home indicator.
                GlassEffectContainer(spacing: LVSpacing.sm) {
                    tabItemsHStack
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
            } else {
                tabItemsHStack
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(palette.surfaceStroke.opacity(0.3), lineWidth: 0.5)
                    }
                }
        }
        .padding(.horizontal, LVSpacing.lg)
        .padding(.bottom, LVSpacing.xs)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: LVTabBarHeightKey.self, value: geo.size.height)
            }
        }
    }

    private var tabItemsHStack: some View {
        HStack(spacing: 0) { // zero-gap intentional — items flex equal-width
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
        .padding(.horizontal, LVSpacing.xs)
        .padding(.vertical, LVSpacing.xs)
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
        // Branded glyph + small label. A soft palette-tinted capsule slides
        // behind the active item via `matchedGeometryEffect` (driven by
        // `selectWithAnimation`'s spring). Clean — no sparkle/bloom/heavy glow.
        VStack(spacing: 2) {
            iconView
                .frame(width: 26, height: 26)
                .lvPulse(active: item.pulses && !reduceMotion)
            Text(item.label)
                .font(LVTypography.microTag.font.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? palette.primary : palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, LVSpacing.sm)
        .padding(.vertical, LVSpacing.xs)
        .background {
            if isActive {
                Capsule()
                    .fill(palette.primary.opacity(0.14))
                    .matchedGeometryEffect(id: "activeTab", in: underlineNamespace)
            }
        }
        .contentShape(Rectangle())
    }

    // Branded `Lumina/Tab/*` artwork when present (full-colour, fit), with mild
    // desaturation/dimming on inactive tabs. Falls back to the SF Symbol for
    // tabs without custom artwork (e.g. the More "ellipsis"). No holographic
    // bloom — keeps the floating-glass bar calm and modern.
    @ViewBuilder
    private var iconView: some View {
        if let assetName = item.icon.customAssetName, UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .saturation(isActive ? 1.0 : 0.7)
                .opacity(isActive ? 1.0 : 0.8)
        } else {
            Image(systemName: item.icon.sfSymbol)
                .font(.system(size: LVSize.tabBarGlyph, weight: isActive ? .semibold : .regular))
                .symbolVariant(isActive ? .fill : .none)
                .foregroundStyle(isActive ? palette.primary : palette.textSecondary)
        }
    }
}

/// Reports the measured height of the floating tab bar so scroll content can
/// clear the capsule on any device without hard-coded padding.
enum LVTabBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 60

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
