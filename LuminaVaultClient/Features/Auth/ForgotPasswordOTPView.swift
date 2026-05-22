import SwiftUI

struct ForgotPasswordOTPView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel

    var body: some View {
        VStack(spacing: 0) {
            StepIcon(systemName: "envelope", color: palette.accent)
            Text("Check your email")
                .font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                .padding(.bottom, 4)
            Group {
                Text("We sent a code to ") + Text(vm.forgotEmail).foregroundColor(palette.primary)
            }
            .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            .multilineTextAlignment(.center).padding(.bottom, 24)

            OTPFieldRow(code: $vm.otpCode).padding(.bottom, 16)

            if let err = vm.error {
                Text(err).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8)).padding(.bottom, 10)
            }
            LVButton("Verify Code", isLoading: vm.isLoading) { Task { await vm.verifyResetCode() } }
                .padding(.bottom, 16)

            Button("Didn't receive it? Resend") { Task { await vm.sendResetCode() } }
                .font(.system(size: 10)).foregroundStyle(palette.primary.opacity(0.65))
        }
        .padding(.horizontal, 24)
    }
}
