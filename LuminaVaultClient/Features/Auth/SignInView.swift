// LuminaVaultClient/LuminaVaultClient/Features/Auth/SignInView.swift
//
// HER-140: SignInView is now the email + password screen only. The
// magic-link tab toggle, phone tertiary CTA, and provider buttons moved
// to AuthLandingView, which is the new post-splash destination.
// SignInView remains reachable from the "Use email & password" link on
// the landing screen.
import SwiftUI

struct SignInView: View {
    @Bindable var vm: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark(size: .auth, intensity: .standard, showSparkle: true)
                    .padding(.bottom, 24)

                Text("Welcome back")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.lvTextPrimary)
                Text("Sign in with your email and password.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lvTextSub)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                VStack(spacing: 10) {
                    LVTextField(
                        placeholder: "Email", text: $vm.email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never
                    )
                    LVSecureField(placeholder: "Password", text: $vm.password)
                }

                HStack {
                    Spacer()
                    NavigationLink("Forgot password?") {
                        ForgotPasswordView(vm: vm)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.lvCyan.opacity(0.6))
                }
                .padding(.top, 6).padding(.bottom, 16)

                if let err = vm.error {
                    Text(err).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8))
                        .padding(.bottom, 10)
                }

                LVButton("Sign In", isLoading: vm.isLoading) {
                    Task { await vm.signIn() }
                }
                .padding(.bottom, 18)

                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .font(.system(size: 11)).foregroundStyle(Color.lvTextSub)
                    NavigationLink("Sign Up") { SignUpView(vm: vm) }
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.lvCyan)
                }
            }
            .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 40)
        }
        .lvBackground()
        .navigationDestination(isPresented: Binding(
            get: { vm.mfaRequired },
            set: { if !$0 { vm.mfaRequired = false } }
        )) { MFAChallengeView(vm: vm) }
    }
}

#Preview {
    @Previewable @State var vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
    NavigationStack { SignInView(vm: vm) }
}
