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
}

struct SSOButton: View {
    let provider: SSOProvider
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            providerIcon
                .frame(width: 72, height: 44)
                .background(Color.lvGlass)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.lvBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.accessibilityLabel)
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
}
