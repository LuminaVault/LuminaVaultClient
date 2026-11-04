// LuminaVaultClient/LuminaVaultClient/Components/LVButton.swift
import SwiftUI

/// The app's primary call to action.
///
/// Memory Keeper (2026-10): a solid `palette.primary` fill with a dark label.
/// The old primary→secondary→accent gradient, perpetual shimmer sweep and
/// double glow shadow are gone — cyan already marks "this is interactive",
/// and gold is reserved for premium moments (`lvAuroraGoldRing`). Feedback is
/// a short press scale instead of constant motion.
struct LVButton: View {

    @Environment(\.lvPalette) private var palette

    private let title: String
    private let isLoading: Bool
    private let action: () -> Void

    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().progressViewStyle(.circular).tint(palette.onPrimary).scaleEffect(0.85)
                } else {
                    Text(title)
                        .font(LVTypography.button.font)
                        .foregroundStyle(palette.onPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: LVSize.buttonHeight)
            .background(palette.primary, in: RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous))
        }
        .buttonStyle(LVPressScaleStyle())
        .disabled(isLoading)
    }
}

/// 0.97 scale while pressed, 150ms. Reduce Motion keeps the opacity dip only.
struct LVPressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
