// LuminaVaultClient/LuminaVaultClient/Components/SSOButton.swift
import SwiftUI

enum SSOProvider: String, CaseIterable {
    case apple, google, x

    var accessibilityLabel: String {
        switch self {
        case .apple:  return "Sign in with Apple"
        case .google: return "Sign in with Google"
        case .x:      return "Sign in with X"
        }
    }

    var labelText: String {
        switch self {
        case .apple:  return "Sign in with Apple"
        case .google: return "Sign in with Google"
        case .x:      return "Sign in with X"
        }
    }
}

extension SSOButton {
    /// Visual treatment for an SSO button.
    ///
    /// - `.primary`: full-width tall button with icon + label. Used for Apple
    ///   per App Store §4.8 + Apple HIG, which call for SIWA to be at least as
    ///   prominent as any third-party identity option.
    /// - `.icon`: compact icon-only chip. Used for Google / X / other
    ///   third-party providers that ride below the primary CTA.
    enum Style {
        case primary
        case icon
    }
}

struct SSOButton: View {

    @Environment(\.lvPalette) private var palette

    let provider: SSOProvider
    var style: Style = .icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch style {
            case .primary:
                primaryContent
                    .frame(maxWidth: .infinity)
                    .frame(height: LVSize.buttonHeight)
                    .background(Color.lvGlass)
                    .overlay(
                        RoundedRectangle(cornerRadius: LVRadius.md)
                            .stroke(primaryBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
            case .icon:
                providerIcon
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.lvGlass)
                    .overlay(
                        RoundedRectangle(cornerRadius: LVRadius.md)
                            .stroke(palette.surfaceStroke, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: LVRadius.md))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.accessibilityLabel)
    }

    @ViewBuilder
    private var primaryContent: some View {
        HStack(spacing: LVSpacing.md) {
            providerIcon
            Text(provider.labelText)
                .font(LVTypography.fieldLabel.font)
                .foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        switch provider {
        case .apple:
            LVIconView(.apple, size: 18, tint: palette.textPrimary)
        case .google:
            // Official multi-color Google "G" mark — keep brand colors (no tint).
            Image("google_logo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case .x:
            Text("𝕏")
                .font(.system(size: 16, weight: .bold)) // TODO HER-icon-tokens: text glyph used as icon stand-in
                .foregroundStyle(palette.textPrimary)
        }
    }

    private var primaryBorder: Color {
        provider == .apple ? palette.textPrimary.opacity(0.45) : palette.surfaceStroke
    }
}
