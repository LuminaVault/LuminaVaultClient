import SwiftUI

struct ForgotPasswordResetView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            StepIcon(systemName: "checkmark.shield", color: palette.primary)
            Text("New password")
                .font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                .padding(.bottom, 4)
            Text("Must be at least 8 characters")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary).padding(.bottom, 24)

            VStack(spacing: 10) {
                LVSecureField(placeholder: "New password", text: $vm.newPassword, textContentType: .newPassword)
                LVSecureField(placeholder: "Confirm password", text: $vm.confirmNewPassword, textContentType: .newPassword)
            }
            .padding(.bottom, 16)

            if let err = vm.error {
                Text(err).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8)).padding(.bottom, 10)
            }
            LVButton("Reset Password", isLoading: vm.isLoading) {
                Task {
                    await vm.resetPassword()
                    if vm.error == nil { dismiss() }
                }
            }
        }
        .padding(.horizontal, 24)
    }
}
