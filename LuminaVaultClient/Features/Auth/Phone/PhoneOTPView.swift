// LuminaVaultClient/LuminaVaultClient/Features/Auth/Phone/PhoneOTPView.swift
// HER-141 step 2: 6-digit OTP entry with SMS-autofill + 60s resend cooldown.
import SwiftUI

struct PhoneOTPView: View {
    @Bindable var vm: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark(size: .auth, intensity: .subtle, showSparkle: false)
                    .padding(.bottom, 24)

                Text("Enter the code")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.lvTextPrimary)
                    .padding(.bottom, 4)
                Text("Sent to \(vm.phoneE164)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lvTextSub)
                    .padding(.bottom, 20)

                OTPFieldRow(
                    code: $vm.phoneOtpCode,
                    accentColor: .lvCyan,
                    textContentType: .oneTimeCode
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                resendRow.padding(.bottom, 18)

                if let err = vm.error {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.bottom, 10)
                }

                LVButton("Verify", isLoading: vm.isLoading) {
                    Task { await vm.verifyPhoneOTP() }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .padding(.top, 48).padding(.bottom, 40)
        }
        .lvBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    vm.phoneStep = .entry
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(Color.lvCyan)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var resendRow: some View {
        Group {
            if vm.phoneResendSecondsLeft > 0 {
                Text("Resend in 0:\(String(format: "%02d", vm.phoneResendSecondsLeft))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lvTextMuted)
            } else {
                Button("Resend code") {
                    Task { await vm.resendPhoneOTP() }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.lvCyan)
            }
        }
    }
}

#Preview {
    @Previewable @State var vm: AuthViewModel = {
        let v = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
        v.phoneE164 = "+15551234567"
        v.phoneResendSecondsLeft = 42
        return v
    }()
    NavigationStack { PhoneOTPView(vm: vm) }
}
