// LuminaVaultClient/LuminaVaultClient/Features/Auth/EmailMagicLinkView.swift
import SwiftUI

/// HER-142 — parent container for the two-step email magic-link flow.
/// Mirrors `ForgotPasswordView`: switch on a step enum, back-button via
/// `Environment.dismiss`, reset state on disappear.
struct EmailMagicLinkView: View {
    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark(size: .auth, intensity: .standard, showSparkle: true)
                    .padding(.bottom, 18)

                StepIcon(
                    systemName: vm.emailMagicStep == .email ? "envelope" : "envelope.badge",
                    color: palette.primary
                )

                switch vm.emailMagicStep {
                case .email:  EmailMagicEmailView(vm: vm)
                case .verify: EmailMagicVerifyView(vm: vm)
                }
            }
            .padding(.top, 48).padding(.bottom, 40)
        }
        .lvBackground()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EmailMagicBackButton(vm: vm) }
        }
        .onDisappear { vm.resetEmailMagic(); vm.error = nil }
    }
}

private struct EmailMagicBackButton: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if vm.emailMagicStep == .verify {
                vm.emailMagicStep = .email
                vm.error = nil
            } else {
                dismiss()
            }
        } label: {
            LVIconView(.chevronLeft, size: 14, tint: palette.primary.opacity(0.8), weight: .semibold)
                .frame(width: 32, height: 32)
                .background(Color.lvGlass)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.surfaceStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

#Preview {
    @Previewable @State var vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
    NavigationStack { EmailMagicLinkView(vm: vm) }
}
