// LuminaVaultClient/LuminaVaultClient/Components/LVNavigationBrand.swift
// HER-255: small Hermie mascot avatar that lives in the navigation bar.
// Applied via `.lvNavBrand()` at the root of every tab so the mascot is
// always present in the corner.
import SwiftUI

enum LVNavBrandPosition {
    case topLeading
    case topTrailing
}

extension View {
    /// Places a 28-pt Hermie mascot in the navigation bar.
    func lvNavBrand(position: LVNavBrandPosition = .topLeading, size: CGFloat = 28) -> some View {
        modifier(LVNavBrandModifier(position: position, size: size))
    }
}

private struct LVNavBrandModifier: ViewModifier {
    @Environment(\.lvPalette) private var palette
    let position: LVNavBrandPosition
    let size: CGFloat

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: placement) {
                ZStack {
                    Circle()
                        .fill(palette.glowPrimary.opacity(0.25))
                        .frame(width: size + 6, height: size + 6)
                        .blur(radius: 4)
                    HermieMascotView(state: .idle, size: size)
                }
                .accessibilityLabel("Hermie")
                .accessibilityHidden(true) // decorative; nav title carries semantics
            }
        }
    }

    private var placement: ToolbarItemPlacement {
        switch position {
        case .topLeading:  return .topBarLeading
        case .topTrailing: return .topBarTrailing
        }
    }
}
