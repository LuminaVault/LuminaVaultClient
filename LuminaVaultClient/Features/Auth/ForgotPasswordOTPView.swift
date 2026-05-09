import SwiftUI

struct ForgotPasswordOTPView: View {
    @Bindable var vm: AuthViewModel

    var body: some View {
        VStack(spacing: 0) {
            StepIcon(systemName: "envelope", color: .lvAmber)
            Text("Check your email")
                .font(.system(size: 20, weight: .heavy)).foregroundStyle(Color.lvTextPrimary)
                .padding(.bottom, 4)
            Group {
                Text("We sent a code to ") + Text(vm.forgotEmail).foregroundColor(Color.lvCyan)
            }
            .font(.system(size: 11)).foregroundStyle(Color.lvTextSub)
            .multilineTextAlignment(.center).padding(.bottom, 24)

            OTPFieldRow(code: $vm.otpCode).padding(.bottom, 16)

            if let err = vm.error {
                Text(err).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8)).padding(.bottom, 10)
            }
            LVButton("Verify Code", isLoading: vm.isLoading) { Task { await vm.verifyResetCode() } }
                .padding(.bottom, 16)

            Button("Didn't receive it? Resend") { Task { await vm.sendResetCode() } }
                .font(.system(size: 10)).foregroundStyle(Color.lvCyan.opacity(0.65))
        }
        .padding(.horizontal, 24)
    }
}
