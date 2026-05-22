// LuminaVaultClient/LuminaVaultClient/Features/Auth/EmailMagicEmailView.swift
import SwiftUI

/// HER-142 step 1 — collect email, POST `/v1/auth/email/start`.
struct EmailMagicEmailView: View {
    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Sign in with a code")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.bottom, 4)
            Text("We'll email you a 6-digit code. No password needed.")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            LVTextField(
                placeholder: "Email",
                text: $vm.emailMagicEmail,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            if let err = vm.error {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            LVButton("Send code", isLoading: vm.isLoading) {
                Task { await vm.startEmailMagic() }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Button("Sign in with password instead") {
                vm.error = nil
                dismiss()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.primary.opacity(0.7))
        }
    }
}
