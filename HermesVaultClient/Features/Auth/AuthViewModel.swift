// HermesVaultClient/HermesVaultClient/Features/Auth/AuthViewModel.swift
import SwiftUI

@Observable
@MainActor
final class AuthViewModel {
    // Sign In
    var email = ""
    var password = ""
    // Sign Up
    var name = ""
    var confirmPassword = ""
    // Forgot Password
    var forgotEmail = ""
    var otpCode = ""
    var resetToken = ""
    var newPassword = ""
    var confirmNewPassword = ""
    var forgotStep = 1
    // MFA
    var mfaCode = ""
    var mfaMethod: MFAMethod = .totp
    // Shared
    var isLoading = false
    var error: String? = nil
    var mfaRequired = false

    private let authClient: any AuthClientProtocol
    private let appState: AppState

    init(authClient: any AuthClientProtocol, appState: AppState) {
        self.authClient = authClient
        self.appState = appState
    }

    func signIn() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let r = try await authClient.login(email: email, password: password)
            r.user.mfaEnabled ? (mfaRequired = true) : appState.handleAuthSuccess(r)
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func signUp() async {
        guard password == confirmPassword else { error = "Passwords do not match"; return }
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let r = try await authClient.register(name: name, email: email, password: password)
            appState.handleAuthSuccess(r)
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func sendResetCode() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do { try await authClient.forgotPassword(email: forgotEmail); forgotStep = 2 }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func verifyResetCode() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do { try await authClient.verifyOTP(email: forgotEmail, code: otpCode); forgotStep = 3 }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func resetPassword() async {
        guard newPassword == confirmNewPassword else { error = "Passwords do not match"; return }
        isLoading = true; error = nil; defer { isLoading = false }
        do { try await authClient.resetPassword(token: resetToken, newPassword: newPassword); forgotStep = 1 }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func verifyMFA() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let r = try await authClient.verifyMFA(code: mfaCode, mfaMethod: mfaMethod)
            appState.handleAuthSuccess(r)
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func handleSSOTap(provider: SSOProvider) async {
        // Apple: use AuthenticationServices to get identityToken, then call ssoLogin
        // Google: integrate GoogleSignIn SDK, get idToken, then call ssoLogin
        // X: OAuth 2.0 PKCE web flow, exchange for token, then call ssoLogin
        // Stub until SDK integration is complete:
        error = "\(provider.rawValue.capitalized) SSO requires SDK setup — see docs/superpowers/specs/2026-05-08-hermesclient-auth-design.md"
    }
}
