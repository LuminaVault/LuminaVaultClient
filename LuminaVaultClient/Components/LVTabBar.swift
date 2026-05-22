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
struct LVTabItem: Identifiable, Equatable {
    /// Stable identity — used as the TabView selection value.
    let id: String
    /// Display label below the icon.
    let label: String
    /// SF Symbol fallback shown when no custom imageset is provided or when
    /// the imageset is missing in the catalog.
    let systemImage: String
    /// Optional namespaced imageset under `Lumina/Tab/` (e.g. `spaces`).
    let customImageName: String?
    /// When true, the tab pulses softly to invite attention. The Home tab
    /// uses this for "you have new insights waiting".
    let pulses: Bool

    init(
        id: String,
        label: String,
        systemImage: String,
        customImageName: String? = nil,
        pulses: Bool = false
    ) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.customImageName = customImageName
        self.pulses = pulses
    }
}

struct LVTabBar: View {
    @Environment(\.lvPalette) private var palette
    let primaryItems: [LVTabItem]
    let overflowItems: [LVTabItem]
    @Binding var selection: String
    private let underlineNamespace: Namespace.ID

    init(
        primaryItems: [LVTabItem],
        overflowItems: [LVTabItem] = [],
        selection: Binding<String>,
        underlineNamespace: Namespace.ID
    ) {
        self.primaryItems = primaryItems
        self.overflowItems = overflowItems
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
                systemImage: active.systemImage,
                customImageName: active.customImageName,
            )
        }
        return LVTabItem(id: "lv.tab.more", label: "More", systemImage: "ellipsis")
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(primaryItems) { item in
                LVTabBarButton(
                    item: item,
                    isActive: item.id == selection,
                    underlineNamespace: underlineNamespace,
                    onTap: { selectWithAnimation(item.id) }
                )
                .frame(maxWidth: .infinity)
            }
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
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            ZStack(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [palette.backgroundBase.opacity(0.55), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                Rectangle()
                    .fill(palette.surfaceStroke)
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
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

    var body: some View {
        Menu {
            ForEach(overflowItems) { overflowItem in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        selection = overflowItem.id
                    }
                } label: {
                    Label(overflowItem.label, systemImage: overflowItem.systemImage)
                }
            }
        } label: {
            LVTabBarItemContent(
                item: item,
                isActive: isActive,
                underlineNamespace: underlineNamespace,
            )
        }
        .menuStyle(.button)
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
        VStack(spacing: 4) {
            ZStack {
                if isActive {
                    Circle()
                        .fill(palette.glowPrimary.opacity(0.25))
                        .frame(width: 38, height: 38)
                        .blur(radius: 8)
                }
                iconView
                    .frame(width: 26, height: 26)
            }
            .lvPulse(active: item.pulses && !reduceMotion)
            Text(item.label)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? palette.primary : palette.textSecondary.opacity(0.85))
                .lineLimit(1)
            ZStack {
                if isActive {
                    Capsule()
                        .fill(palette.glowPrimary)
                        .frame(width: 24, height: 3)
                        .shadow(color: palette.glowPrimary, radius: 6)
                        .matchedGeometryEffect(id: "activeUnderline", in: underlineNamespace)
                } else {
                    Capsule().fill(Color.clear).frame(width: 24, height: 3)
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconView: some View {
        if let custom = item.customImageName,
           UIImage(named: "Lumina/Tab/\(custom)") != nil {
            Image("Lumina/Tab/\(custom)")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .saturation(isActive ? 1.0 : 0.55)
                .opacity(isActive ? 1.0 : 0.75)
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isActive ? palette.primary : palette.textSecondary.opacity(0.85))
        }
    }
}
