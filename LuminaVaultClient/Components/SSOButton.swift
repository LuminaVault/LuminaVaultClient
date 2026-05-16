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
    let provider: SSOProvider
    var style: Style = .icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch style {
            case .primary:
                primaryContent
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.lvGlass)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(primaryBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .icon:
                providerIcon
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.lvGlass)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.lvBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.accessibilityLabel)
    }

    @ViewBuilder
    private var primaryContent: some View {
        HStack(spacing: 10) {
            providerIcon
            Text(provider.labelText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.lvTextPrimary)
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        switch provider {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 18))
                .foregroundStyle(Color.lvTextPrimary)
        case .google:
            // Replace with Image("google_logo") once asset added to Assets.xcassets
            Text("G")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.lvTextPrimary)
        case .x:
            Text("𝕏")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.lvTextPrimary)
        }
    }

    private var primaryBorder: Color {
        provider == .apple ? Color.lvTextPrimary.opacity(0.45) : Color.lvBorder
    }
}
