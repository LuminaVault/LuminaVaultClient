// LuminaVaultClient/LuminaVaultClient/Components/LVTabBar.swift
// HER-255: custom glow tab bar. Replaces stock TabView chrome with a glass
// background + glowing underline on the active tab. Wires a "pending insights"
// pulse on the Home tab.
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
    let items: [LVTabItem]
    @Binding var selection: String
    /// Optional horizontal namespace for matchedGeometryEffect (the underline).
    private let underlineNamespace: Namespace.ID
    /// HER-243 — when > 0, splits the items into two halves with a clear
    /// horizontal spacer in the middle, leaving room for an overlaid FAB.
    private let centerGapWidth: CGFloat

    init(
        items: [LVTabItem],
        selection: Binding<String>,
        underlineNamespace: Namespace.ID,
        centerGapWidth: CGFloat = 0,
    ) {
        self.items = items
        _selection = selection
        self.underlineNamespace = underlineNamespace
        self.centerGapWidth = centerGapWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            if centerGapWidth > 0, items.count >= 2 {
                let mid = items.count / 2
                let frontHalf = Array(items.prefix(mid))
                let backHalf = Array(items.suffix(from: mid))
                ForEach(frontHalf) { item in
                    tabButton(item)
                }
                Spacer().frame(width: centerGapWidth)
                ForEach(backHalf) { item in
                    tabButton(item)
                }
            } else {
                ForEach(items) { item in
                    tabButton(item)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
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

    @ViewBuilder
    private func tabButton(_ item: LVTabItem) -> some View {
        LVTabBarButton(
            item: item,
            isActive: item.id == selection,
            underlineNamespace: underlineNamespace,
            onTap: { withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                selection = item.id
            } },
        )
        .frame(maxWidth: .infinity)
    }
}

private struct LVTabBarButton: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LVTabItem
    let isActive: Bool
    let underlineNamespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    if isActive {
                        // Glow halo behind the active icon.
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
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
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
