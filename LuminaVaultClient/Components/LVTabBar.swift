// LuminaVaultClient/LuminaVaultClient/Components/LVTabBar.swift
// HER-255: custom glow tab bar. Replaces stock TabView chrome with a glass
// background + glowing underline on the active tab. Wires a "pending insights"
// pulse on the Home tab.
//
// iOS 26+ uses the native `GlassEffectContainer` + `.glassEffect` for the
// liquid glass capsule. Older deployment targets (currently iOS 18) fall back
// to `.ultraThinMaterial` + subtle stroke (consistent with `lvGlassCard`).
// HER-107: split into N primary items + a trailing More button. The bar
// renders the first `primaryItems` inline and packs everything else into
// a Menu attached to the More button. When an overflow item is the
// active tab, More's icon swaps to that item's icon (Apple HIG — the
// More tab represents the active overflow selection).
//
// Revolut / expo-glass-tabs morph: inactive tabs are icon-only; the active
// tab grows into a wider light capsule with icon + label. Minimize-on-scroll
// collapses labels and tightens padding. Optional raised Capture sits above
// the bar centre and is NOT a TabView selection.
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
    @Environment(LVTabBarMinimizeState.self) private var minimize

    let primaryItems: [LVTabItem]
    let overflowItems: [LVTabItem]
    /// When true, the More overflow ("...") button renders as the FIRST
    /// (leading) item instead of trailing. Used to make the Menu the first
    /// option on the tab bar.
    let overflowLeading: Bool
    /// Raised Capture disc over the bar centre. Action-only — never a
    /// TabView selection tag.
    let showsCenterCapture: Bool
    @Binding var selection: String
    private let underlineNamespace: Namespace.ID

    init(
        primaryItems: [LVTabItem],
        overflowItems: [LVTabItem] = [],
        overflowLeading: Bool = false,
        showsCenterCapture: Bool = true,
        selection: Binding<String>,
        underlineNamespace: Namespace.ID
    ) {
        self.primaryItems = primaryItems
        self.overflowItems = overflowItems
        self.overflowLeading = overflowLeading
        self.showsCenterCapture = showsCenterCapture
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

    private var minimizeProgress: CGFloat { minimize.progress }

    /// Vertical / horizontal inset of the capsule — tightens as we minimize.
    private var capsulePaddingH: CGFloat {
        LVSpacing.xs + (1 - minimizeProgress) * 2
    }

    private var capsulePaddingV: CGFloat {
        LVSpacing.xs * (1 - 0.45 * minimizeProgress)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if #available(iOS 26.0, *) {
                    // Floating Liquid Glass capsule (iOS 26+ `.glassEffect`).
                    GlassEffectContainer(spacing: LVSpacing.sm) {
                        tabItemsHStack
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                } else {
                    // Fallback for older iOS: ultra-thin material capsule.
                    tabItemsHStack
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(palette.surfaceStroke.opacity(0.3), lineWidth: 0.5)
                        }
                }
            }
            .scaleEffect(1 - 0.06 * minimizeProgress, anchor: .bottom)
            .padding(.top, showsCenterCapture ? 22 : 0)

            if showsCenterCapture {
                CaptureFAB(style: .floating)
                    .scaleEffect(0.72 * (1 - 0.12 * minimizeProgress))
                    .offset(y: -6 + 4 * minimizeProgress)
                    .accessibilityLabel("New capture")
            }
        }
        .padding(.horizontal, LVSpacing.lg)
        .padding(.bottom, LVSpacing.xs)
        .animation(LVTabBarMinimizeState.spring, value: minimizeProgress)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: LVTabBarHeightKey.self, value: geo.size.height)
            }
        }
    }

    /// Common tab items row (HStack of primary + optional More).
    /// Intrinsic sizing so the active pill can grow wider than siblings.
    private var tabItemsHStack: some View {
        HStack(spacing: LVSpacing.xs) {
            if overflowLeading {
                moreButton
            }
            ForEach(primaryItems) { item in
                LVTabBarButton(
                    item: item,
                    isActive: item.id == selection,
                    minimizeProgress: minimizeProgress,
                    underlineNamespace: underlineNamespace,
                    onTap: { selectWithAnimation(item.id) }
                )
            }
            if !overflowLeading {
                moreButton
            }
        }
        .padding(.horizontal, capsulePaddingH)
        .padding(.vertical, capsulePaddingV)
    }

    @ViewBuilder
    private var moreButton: some View {
        if !overflowItems.isEmpty {
            LVTabBarMoreButton(
                item: moreItem,
                isActive: activeOverflowItem != nil,
                minimizeProgress: minimizeProgress,
                overflowItems: overflowItems,
                selection: $selection,
                underlineNamespace: underlineNamespace,
            )
        }
    }

    private func selectWithAnimation(_ id: String) {
        minimize.expand()
        withAnimation(LVTabBarMinimizeState.spring) {
            selection = id
        }
    }
}

private struct LVTabBarButton: View {
    let item: LVTabItem
    let isActive: Bool
    let minimizeProgress: CGFloat
    let underlineNamespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            LVTabBarItemContent(
                item: item,
                isActive: isActive,
                minimizeProgress: minimizeProgress,
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
    let minimizeProgress: CGFloat
    let overflowItems: [LVTabItem]
    @Binding var selection: String
    let underlineNamespace: Namespace.ID

    @Environment(LVTabBarMinimizeState.self) private var minimize

    // HER-bugfix — plain Button + confirmationDialog (not Menu) so
    // matchedGeometryEffect stays in one hosting controller.
    @State private var showOverflow = false

    var body: some View {
        Button {
            minimize.expand()
            showOverflow = true
        } label: {
            LVTabBarItemContent(
                item: item,
                isActive: isActive,
                minimizeProgress: minimizeProgress,
                underlineNamespace: underlineNamespace,
            )
        }
        .buttonStyle(.plain)
        .confirmationDialog("More", isPresented: $showOverflow, titleVisibility: .visible) {
            ForEach(overflowItems) { overflowItem in
                Button(overflowItem.label) {
                    withAnimation(LVTabBarMinimizeState.spring) {
                        selection = overflowItem.id
                    }
                }
            }
        }
        .accessibilityLabel(isActive ? "More — \(item.label) active" : "More")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }
}

/// Pure visual content for one tab bar item.
/// Inactive: icon-only. Active (expanded): horizontal icon + label inside a
/// wider light capsule. Minimized: all icon-only, tighter padding.
private struct LVTabBarItemContent: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LVTabItem
    let isActive: Bool
    let minimizeProgress: CGFloat
    let underlineNamespace: Namespace.ID

    /// Show the label only when this tab is active and the bar isn't minimized.
    private var showsLabel: Bool {
        isActive && minimizeProgress < 0.55
    }

    private var labelOpacity: Double {
        showsLabel ? Double(1 - (minimizeProgress / 0.55)) : 0
    }

    private var activePillFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.08)
    }

    private var horizontalPadding: CGFloat {
        if isActive && showsLabel {
            return LVSpacing.md + LVSpacing.xs // ~16 — wider active capsule
        }
        return LVSpacing.sm
    }

    private var verticalPadding: CGFloat {
        let base: CGFloat = isActive ? LVSpacing.sm : LVSpacing.xs + 2
        return base * (1 - 0.35 * minimizeProgress)
    }

    var body: some View {
        HStack(spacing: LVSpacing.xs) {
            iconView
                .frame(width: 24, height: 24)
                .lvPulse(active: item.pulses && !reduceMotion)

            if showsLabel {
                Text(item.label)
                    .font(LVTypography.microTag.font.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .opacity(labelOpacity)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background {
            if isActive {
                Capsule()
                    .fill(activePillFill)
                    .matchedGeometryEffect(id: "activeTab", in: underlineNamespace)
            }
        }
        .contentShape(Capsule())
        .layoutPriority(isActive ? 1 : 0)
    }

    @ViewBuilder
    private var iconView: some View {
        if let assetName = item.icon.customAssetName, UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .saturation(isActive ? 1.0 : 0.7)
                .opacity(isActive ? 1.0 : 0.75)
        } else {
            Image(systemName: item.icon.sfSymbol)
                .font(.system(size: LVSize.tabBarGlyph - 2, weight: isActive ? .semibold : .regular))
                .symbolVariant(isActive ? .fill : .none)
                .foregroundStyle(isActive ? palette.textPrimary : palette.textSecondary)
        }
    }
}

/// Reports the measured height of the floating tab bar so scroll content can
/// clear the capsule on any device without hard-coded padding.
enum LVTabBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 72

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
