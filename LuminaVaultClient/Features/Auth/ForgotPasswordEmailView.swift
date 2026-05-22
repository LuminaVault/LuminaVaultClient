// LuminaVaultClient/LuminaVaultClient/Features/Auth/ForgotPasswordEmailView.swift
import SwiftUI

struct ForgotPasswordEmailView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel

    var body: some View {
        VStack(spacing: 0) {
            StepIcon(systemName: "lock", color: palette.primary)
            Text("Forgot password?")
                .font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                .padding(.bottom, 4)
            Text("We'll send a verification code to your email")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center).padding(.bottom, 24)

            LVTextField(placeholder: "Email", text: $vm.forgotEmail,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never)
                .padding(.bottom, 16)

            if let err = vm.error {
                Text(err).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8)).padding(.bottom, 10)
            }
            LVButton("Send Code", isLoading: vm.isLoading) { Task { await vm.sendResetCode() } }
        }
        .padding(.horizontal, 24)
    }
}
