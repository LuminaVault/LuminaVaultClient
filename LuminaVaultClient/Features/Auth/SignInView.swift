// LuminaVaultClient/LuminaVaultClient/Features/Auth/SignInView.swift
import SwiftUI

/// HER-142: a tab toggle on the sign-in form switches the primary CTA from
/// email+password to "send me a sign-in code". When in `.magicLink` mode the
/// password field + "Forgot password?" link drop out; tapping the button
/// posts `/v1/auth/email/start` and pushes `EmailMagicLinkView`.
enum SignInMethod: String, CaseIterable, Identifiable {
    case password
    case magicLink

    var id: String { rawValue }
    var label: String {
        switch self {
        case .password:  return "Password"
        case .magicLink: return "Magic Link"
        }
    }
}

struct SignInView: View {
    @Bindable var vm: AuthViewModel
    @State private var method: SignInMethod = .password

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark(size: .auth, intensity: .standard, showSparkle: true)
                    .padding(.bottom, 24)

                Text("Welcome back")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.lvTextPrimary)
                Text("Your memories, illuminated.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lvTextSub)
                    .padding(.top, 4)
                    .padding(.bottom, 18)

                methodToggle
                    .padding(.bottom, 16)

                VStack(spacing: 10) {
                    LVTextField(
                        placeholder: "Email", text: $vm.email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never
                    )
                    if method == .password {
                        LVSecureField(placeholder: "Password", text: $vm.password)
                    }
                }

                if method == .password {
                    HStack {
                        Spacer()
                        NavigationLink("Forgot password?") {
                            ForgotPasswordView(vm: vm)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.lvCyan.opacity(0.6))
                    }
                    .padding(.top, 6).padding(.bottom, 16)
                } else {
                    Spacer().frame(height: 16)
                }

                if let err = vm.error {
                    Text(err).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8))
                        .padding(.bottom, 10)
                }

                LVButton(method == .password ? "Sign In" : "Send code", isLoading: vm.isLoading) {
                    Task {
                        switch method {
                        case .password:
                            await vm.signIn()
                        case .magicLink:
                            vm.emailMagicEmail = vm.email
                            await vm.startEmailMagic()
                        }
                    }
                }
                .padding(.bottom, 18)

                SSORow(dividerLabel: "or continue with") { provider in
                    Task { await vm.handleSSOTap(provider: provider) }
                }
                .padding(.bottom, 14)

                // HER-141: phone OTP entry point. Tertiary CTA so Apple Sign-In
                // remains the primary §4.8-compliant button.
                NavigationLink {
                    PhoneEntryView(vm: vm)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill").font(.system(size: 12, weight: .semibold))
                        Text("Continue with phone")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.lvCyan)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.lvGlass)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lvBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .navigationDestination(isPresented: Binding(
            get: { vm.emailMagicStep == .verify },
            set: { if !$0 { vm.resetEmailMagic() } }
        )) { EmailMagicLinkView(vm: vm) }
    }

    private var methodToggle: some View {
        HStack(spacing: 0) {
            ForEach(SignInMethod.allCases) { item in
                Button {
                    method = item
                    vm.error = nil
                } label: {
                    Text(item.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(method == item ? Color.lvCyan : Color.lvTextMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(method == item ? Color.lvCyan.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(method == item
                            ? RoundedRectangle(cornerRadius: 8).stroke(Color.lvCyan.opacity(0.3), lineWidth: 1)
                            : nil)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.label) sign-in")
            }
        }
        .padding(3)
        .background(Color.lvGlass)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.lvBorder, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
    NavigationStack { SignInView(vm: vm) }
}
