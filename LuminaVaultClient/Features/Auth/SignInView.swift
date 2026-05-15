// LuminaVaultClient/LuminaVaultClient/Features/Auth/SignInView.swift
import SwiftUI

struct SignInView: View {
    @Bindable var vm: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark(size: .auth, intensity: .standard)
                    .padding(.bottom, 24)

                Text("Welcome back")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.lvTextPrimary)
                Text("Your memories, illuminated.")
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

                LVButton("Sign In", isLoading: vm.isLoading) { Task { await vm.signIn() } }
                    .padding(.bottom, 18)

                SSORow(dividerLabel: "or continue with") { provider in
                    Task { await vm.handleSSOTap(provider: provider) }
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
        .navigationBarBackButtonHidden(true)
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
