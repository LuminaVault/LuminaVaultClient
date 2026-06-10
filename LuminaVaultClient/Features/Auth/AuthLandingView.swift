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
    case apple, google, x, passkey, phone, email

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple:   return "Sign in with Apple"
        case .google:  return "Sign in with Google"
        case .x:       return "Sign in with X"
        case .passkey: return "Sign in with a passkey"
        case .phone:   return "Continue with phone"
        case .email:   return "Continue with email"
        }
    }

    var iconSystemName: String? {
        switch self {
        case .apple:   return "apple.logo"
        case .passkey: return "key.fill"
        case .phone:   return "phone.fill"
        case .email:   return "envelope.fill"
        case .google, .x: return nil // glyph rendered separately
        }
    }

    /// Bridges to the OAuth-only enum used by `AuthViewModel`. Returns nil
    /// for non-OAuth providers (phone/email/passkey use their own flows).
    var ssoProvider: SSOProvider? {
        switch self {
        case .apple:  return .apple
        case .google: return .google
        case .x:      return .x
        case .phone, .email, .passkey: return nil
        }
    }
}

struct AuthLandingView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel
    @AppStorage("lv.auth.preferredProvider") private var preferredRaw: String = ""
    @State private var showingPasskeySheet = false

    private var preferred: AuthProviderOption? {
        AuthProviderOption(rawValue: preferredRaw)
    }

    private var visibleProviders: [AuthProviderOption] {
        // Mirror SSORow: only show Google / X when their client IDs are
        // configured. Phone + email + passkey are always available; Apple is
        // always shown because §4.8 mandates SIWA presence whenever any
        // third party identity option is offered.
        var providers: [AuthProviderOption] = [.apple]
        if Config.googleClientID != nil { providers.append(.google) }
        if Config.xClientID != nil { providers.append(.x) }
        providers.append(.passkey)
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
            .padding(.bottom, LVSpacing.xl)
        }
        .safeAreaPadding(.bottom, LVSpacing.base)
        .lvBackground()
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: Binding(
            get: { vm.mfaRequired },
            set: { if !$0 { vm.mfaRequired = false } }
        )) { MFAChallengeView(vm: vm) }
        .sheet(isPresented: $showingPasskeySheet) {
            PasskeyUsernameSheet(vm: vm)
        }
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
        case .passkey:
            // HER-216 — passkey sign-in needs a username so the server can
            // hand back the right `allowCredentials` set. A small bottom
            // sheet collects it, then drives `vm.signInWithPasskey`.
            showingPasskeySheet = true
        case .phone, .email:
            // Navigation handled by NavigationLink wrappers inside
            // AuthLandingButton — phone / email cases push their dedicated
            // entry screens instead of firing a network call here.
            break
        }
    }
}

// MARK: - HER-216 passkey username sheet

/// Small bottom sheet that collects the username and dispatches a passkey
/// sign-in attempt. Kept private to `AuthLandingView` — the only place
/// passkey sign-in is initiated from the auth landing surface.
struct PasskeyUsernameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette
    @Bindable var vm: AuthViewModel
    @State private var username = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign in with a passkey")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Enter your username — your device will handle the rest.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
            TextField("username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(12)
                .lvGlassCard(cornerRadius: 10, intensity: 0.4)

            Button {
                let target = username.trimmingCharacters(in: .whitespaces)
                guard !target.isEmpty else { return }
                Task {
                    await vm.signInWithPasskey(username: target)
                    dismiss()
                }
            } label: {
                Text("Continue")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(palette.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20)
        .presentationDetents([.height(260)])
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
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { action() })
                .lvGlowPress()
        case .email:
            NavigationLink {
                EmailMagicLinkView(vm: vm)
            } label: { card }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { action() })
                .lvGlowPress()
        default:
            Button(action: action) { card }
                .buttonStyle(.plain)
                .lvGlowPress()
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
        .contentShape(Rectangle())
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isPreferred ? [.isSelected] : [])
    }

    // HER-291 — provider glyphs resolve via `LVIcon`. Apple keeps its
    // text-tone tint; passkey/phone/email use `palette.primary`. Google
    // and X stay as text glyphs (no SF Symbol counterpart).
    @ViewBuilder
    private var iconView: some View {
        switch option {
        case .apple:
            LVIconView(.apple, size: 18, tint: palette.textPrimary)
        case .google:
            Text("G")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        case .x:
            Text("𝕏")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        case .passkey:
            LVIconView(.keyFill, size: 16, tint: palette.primary, weight: .semibold)
        case .phone:
            LVIconView(.phoneFill, size: 16, tint: palette.primary, weight: .semibold)
        case .email:
            LVIconView(.envelopeFill, size: 16, tint: palette.primary, weight: .semibold)
        }
    }
}

#Preview {
    @Previewable @State var vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
    NavigationStack {
        AuthLandingView(vm: vm)
    }
}
