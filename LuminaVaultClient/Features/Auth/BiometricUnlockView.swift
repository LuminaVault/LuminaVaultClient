// LuminaVaultClient/LuminaVaultClient/Features/Auth/BiometricUnlockView.swift
//
// HER-103 — cold-launch lock screen after a biometric unlock cancellation.

import SwiftUI

struct BiometricUnlockView: View {
    let isAuthenticating: Bool
    let retry: () -> Void
    let signInInstead: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            LVIconView(.lockShield, size: 52, tint: Color.accentColor, weight: .semibold)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("LuminaVault is locked")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Use Face ID or Touch ID to unlock your stored session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button {
                    retry()
                } label: {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                        }
                        Text(isAuthenticating ? "Verifying" : "Unlock")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)

                Button("Sign in instead", role: .destructive) {
                    signInInstead()
                }
                .buttonStyle(.bordered)
                .disabled(isAuthenticating)
            }
            .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    BiometricUnlockView(
        isAuthenticating: false,
        retry: {},
        signInInstead: {}
    )
}
