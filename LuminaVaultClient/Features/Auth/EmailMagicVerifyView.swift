// LuminaVaultClient/LuminaVaultClient/Features/Auth/EmailMagicVerifyView.swift
import SwiftUI
import UIKit

/// HER-142 step 2 — collect 6-digit code, POST `/v1/auth/email/verify`.
/// Smart-paste banner if a 6-digit numeric string is on the clipboard.
/// Live "Resend in 0:XX" countdown bound to `vm.emailMagicResendSecondsLeft`.
struct EmailMagicVerifyView: View {
    @Bindable var vm: AuthViewModel
    @State private var clipboardCode: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text("Check your email")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.lvTextPrimary)
                .padding(.bottom, 4)
            (Text("We sent a code to ")
             + Text(vm.emailMagicEmail).foregroundColor(Color.lvCyan))
                .font(.system(size: 11))
                .foregroundStyle(Color.lvTextSub)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            if let code = clipboardCode {
                LVPasteBanner(code: code) {
                    vm.emailMagicCode = code
                    clipboardCode = nil
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }

            OTPFieldRow(code: $vm.emailMagicCode, accentColor: .lvCyan)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            resendRow
                .padding(.bottom, 20)

            if let err = vm.error {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            LVButton("Verify", isLoading: vm.isLoading) {
                Task { await vm.verifyEmailMagicCode() }
            }
            .padding(.horizontal, 24)
        }
        .onAppear { refreshClipboard() }
    }

    @ViewBuilder
    private var resendRow: some View {
        if vm.emailMagicResendSecondsLeft > 0 {
            Text("Resend in 0:\(String(format: "%02d", vm.emailMagicResendSecondsLeft))")
                .font(.system(size: 10))
                .foregroundStyle(Color.lvTextMuted)
        } else {
            Button("Resend code") {
                Task { await vm.resendEmailMagic() }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.lvCyan)
        }
    }

    private func refreshClipboard() {
        guard let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              clip.count == 6,
              clip.allSatisfy(\.isNumber) else {
            clipboardCode = nil
            return
        }
        clipboardCode = clip
    }
}
