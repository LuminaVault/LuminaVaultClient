// LuminaVaultClient/LuminaVaultClient/Features/Auth/AuthLandingView.swift
//
// HER-140 — single-screen provider picker that lands after GetStartedView
// (or as the post-splash destination on subsequent launches).
//
// The user picks one of five providers: Apple, Google, X, Phone, Email.
// The last selection is persisted in UserDefaults as
// `lv.auth.preferredProvider` so the matching button is visually
// emphasised on the next launch — a small affordance that saves the
// average returning user a tap.
import SwiftUI

/// Identifies a provider on the landing screen. A superset of `SSOProvider`
/// (which is OAuth-only and reused by `AuthViewModel.handleSSOTap`).
enum AuthProviderOption: String, CaseIterable, Identifiable, Sendable {
    case apple, google, x, phone, email

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple:  return "Sign in with Apple"
        case .google: return "Sign in with Google"
        case .x:      return "Sign in with X"
        case .phone:  return "Continue with phone"
        case .email:  return "Continue with email"
        }
    }

    var iconSystemName: String? {
        switch self {
        case .apple:  return "apple.logo"
        case .phone:  return "phone.fill"
        case .email:  return "envelope.fill"
        case .google, .x: return nil // glyph rendered separately
        }
    }

    /// Bridges to the OAuth-only enum used by `AuthViewModel`. Returns nil
    /// for non-OAuth providers (phone/email use their own flows).
    var ssoProvider: SSOProvider? {
        switch self {
        case .apple:  return .apple
        case .google: return .google
        case .x:      return .x
        case .phone, .email: return nil
        }
    }
}

struct AuthLandingView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel
    @AppStorage("lv.auth.preferredProvider") private var preferredRaw: String = ""

    private var preferred: AuthProviderOption? {
        AuthProviderOption(rawValue: preferredRaw)
    }

    private var visibleProviders: [AuthProviderOption] {
        // Mirror SSORow: only show Google / X when their client IDs are
        // configured. Phone + email are always available; Apple is always
        // shown because §4.8 mandates SIWA presence whenever any third
        // party identity option is offered.
        var providers: [AuthProviderOption] = [.apple]
        if Config.googleClientID != nil { providers.append(.google) }
        if Config.xClientID != nil { providers.append(.x) }
        providers.append(contentsOf: [.phone, .email])
        return providers
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark(size: .auth, intensity: .standard, showSparkle: true)
                    .padding(.bottom, 24)

                Text("Welcome to LuminaVault")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Pick a way to sign in or create an account.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
                    .padding(.bottom, 26)

                providerStack
                    .padding(.bottom, 22)

                if let err = vm.error {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.bottom, 12)
                }

                NavigationLink {
                    SignInView(vm: vm)
                } label: {
                    Text("Use email & password")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primary)
                }
                .padding(.bottom, 10)

                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    NavigationLink("Sign Up") { SignUpView(vm: vm) }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 40)
        }
        .lvBackground()
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: Binding(
            get: { vm.mfaRequired },
            set: { if !$0 { vm.mfaRequired = false } }
        )) { MFAChallengeView(vm: vm) }
    }

    private var providerStack: some View {
        VStack(spacing: 10) {
            ForEach(visibleProviders) { option in
                AuthLandingButton(
                    vm: vm,
                    option: option,
                    isPreferred: option == preferred,
                    action: { handleTap(option) }
                )
            }
        }
    }

    private func handleTap(_ option: AuthProviderOption) {
        preferredRaw = option.rawValue
        switch option {
        case .apple, .google, .x:
            guard let sso = option.ssoProvider else { return }
            Task { await vm.handleSSOTap(provider: sso) }
        case .phone, .email:
            // Navigation handled by NavigationLink wrappers inside
            // AuthLandingButton — phone / email cases push their dedicated
            // entry screens instead of firing a network call here.
            break
        }
    }
}

/// One stacked landing-screen button. OAuth providers fire a tap action
/// (network call inside `AuthViewModel`); phone / email wrap the same
/// visual treatment around a `NavigationLink` to the next screen.
private struct AuthLandingButton: View {
    @Environment(\.lvPalette) private var palette

    let vm: AuthViewModel
    let option: AuthProviderOption
    let isPreferred: Bool
    let action: () -> Void

    var body: some View {
        switch option {
        case .phone:
            NavigationLink {
                PhoneEntryView(vm: vm)
            } label: { card }
                .simultaneousGesture(TapGesture().onEnded { action() })
                .buttonStyle(.plain)
        case .email:
            NavigationLink {
                EmailMagicLinkView(vm: vm)
            } label: { card }
                .simultaneousGesture(TapGesture().onEnded { action() })
                .buttonStyle(.plain)
        default:
            Button(action: action) { card }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var card: some View {
        HStack(spacing: 10) {
            iconView
            Text(option.label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            if isPreferred {
                Text("Last used")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(palette.primary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .lvGlassCard(cornerRadius: 12, intensity: isPreferred ? 0.7 : 0.35)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPreferred ? palette.primary.opacity(0.55) : Color.clear,
                        lineWidth: isPreferred ? 1.5 : 0)
        )
        .scaleEffect(isPreferred ? 1.02 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPreferred)
        .lvGlowPress()
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isPreferred ? [.isSelected] : [])
    }

    @ViewBuilder
    private var iconView: some View {
        switch option {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 18))
                .foregroundStyle(palette.textPrimary)
        case .google:
            Text("G")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        case .x:
            Text("𝕏")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        case .phone:
            Image(systemName: "phone.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.primary)
        case .email:
            Image(systemName: "envelope.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.primary)
        }
    }
}

#Preview {
    @Previewable @State var vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
    NavigationStack {
        AuthLandingView(vm: vm)
    }
}
