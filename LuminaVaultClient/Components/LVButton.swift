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

/// The stock prominent button, with a label that is readable on its fill.
///
/// `.borderedProminent` always draws a white label, which is 1.53:1 on Memory
/// Cyan in dark mode. This keeps the stock control (shape, pressed state,
/// control size, Dynamic Type) and only supplies the fill and label colours,
/// so they stay a pair from the active palette. Use it instead of
/// `.borderedProminent`; the `prominent_button_contrast` lint rule enforces that.
///
/// Destructive buttons keep the system red and its white label. Disabled ones
/// keep the system's disabled colours.
struct LVProminentButtonStyle: PrimitiveButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        LVProminentButton(
            configuration: configuration,
            destructive: destructive || configuration.role == .destructive
        )
    }
}

private struct LVProminentButton: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    let configuration: PrimitiveButtonStyleConfiguration
    let destructive: Bool

    var body: some View {
        Button(role: configuration.role, action: configuration.trigger) {
            if destructive || !isEnabled {
                configuration.label
            } else {
                configuration.label.foregroundStyle(palette.onPrimary)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(destructive ? Color.red : palette.primary)
    }
}

extension PrimitiveButtonStyle where Self == LVProminentButtonStyle {
    static var lvProminent: LVProminentButtonStyle { LVProminentButtonStyle() }

    static func lvProminent(destructive: Bool) -> LVProminentButtonStyle {
        LVProminentButtonStyle(destructive: destructive)
    }
}
