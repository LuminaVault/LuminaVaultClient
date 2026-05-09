// LuminaVaultClient/LuminaVaultClient/Features/Auth/SignUpView.swift
import SwiftUI

struct SignUpView: View {
    @Bindable var vm: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark().padding(.bottom, 20)

                Text("Create account")
                    .font(.system(size: 20, weight: .heavy)).foregroundStyle(Color.lvTextPrimary)
                Text("Capture. Compile. Illuminate.")
                    .font(.system(size: 11)).foregroundStyle(Color.lvTextSub)
                    .padding(.top, 4).padding(.bottom, 22)

                VStack(spacing: 10) {
                    LVTextField(placeholder: "Full name", text: $vm.name,
                                textContentType: .name)
                    LVTextField(placeholder: "Email", text: $vm.email,
                                keyboardType: .emailAddress,
                                textContentType: .emailAddress,
                                autocapitalization: .never)
                    LVSecureField(placeholder: "Password", text: $vm.password,
                                  textContentType: .newPassword)
                    LVSecureField(placeholder: "Confirm password", text: $vm.confirmPassword,
                                  textContentType: .newPassword)
                }
                .padding(.bottom, 16)

                if let err = vm.error {
                    Text(err).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8))
                        .padding(.bottom, 10)
                }

                LVButton("Create Account", isLoading: vm.isLoading) { Task { await vm.signUp() } }
                    .padding(.bottom, 18)

                SSORow(dividerLabel: "or sign up with") { provider in
                    Task { await vm.handleSSOTap(provider: provider) }
                }
                .padding(.bottom, 18)

                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .font(.system(size: 11)).foregroundStyle(Color.lvTextSub)
                    Button("Sign In") { dismiss() }
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.lvCyan)
                }
            }
            .padding(.horizontal, 24).padding(.top, 48).padding(.bottom, 40)
        }
        .lvBackground()
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    @Previewable @State var vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
    NavigationStack { SignUpView(vm: vm) }
}
