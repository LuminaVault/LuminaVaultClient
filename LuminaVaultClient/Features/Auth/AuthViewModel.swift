// LuminaVaultClient/LuminaVaultClient/Features/Auth/AuthViewModel.swift
import SwiftUI
import Foundation
import AuthenticationServices
import UIKit

@Observable
@MainActor
final class AuthViewModel {
    // Sign In
    var email = ""
    var password = ""
    // Sign Up
    var username = ""
    var confirmPassword = ""
    // Forgot Password
    var forgotEmail = ""
    var otpCode = ""
    var newPassword = ""
    var confirmNewPassword = ""
    var forgotStep = 1
    // MFA
    var mfaCode = ""
    var mfaChallengeId: UUID? = nil
    // Shared
    var isLoading = false
    var error: String? = nil
    var mfaRequired = false

    private let authClient: any AuthClientProtocol
    private let appState: AppState
    private let appleService: any SignInServiceProtocol
    private let googleService: (any SignInServiceProtocol)?
    private let xService: (any SignInServiceProtocol)?

    init(
        authClient: any AuthClientProtocol,
        appState: AppState,
        appleService: any SignInServiceProtocol = AppleSignInService(),
        googleService: (any SignInServiceProtocol)? = nil,
        xService: (any SignInServiceProtocol)? = nil
    ) {
        self.authClient = authClient
        self.appState = appState
        self.appleService = appleService
        self.googleService = googleService
        self.xService = xService
    }

    func signIn() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let r = try await authClient.login(email: email, password: password, mfaCode: nil)
            if r.mfaRequired == true {
                mfaChallengeId = r.mfaChallengeId
                mfaRequired = true
            } else {
                appState.handleAuthSuccess(r)
            }
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func signUp() async {
        guard password == confirmPassword else { error = "Passwords do not match"; return }
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let r = try await authClient.register(email: email, username: username, password: password)
            appState.handleAuthSuccess(r)
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func sendResetCode() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do { try await authClient.forgotPassword(email: forgotEmail); forgotStep = 2 }
        catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    // Server validates the OTP at reset-password time (no separate verify
    // endpoint), so step 2 → 3 is a local advance + non-empty sanity check.
    func verifyResetCode() async {
        guard !otpCode.isEmpty else { error = "Enter the code from your email"; return }
        error = nil
        forgotStep = 3
    }

    func resetPassword() async {
        guard newPassword == confirmNewPassword else { error = "Passwords do not match"; return }
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            try await authClient.resetPassword(email: forgotEmail, code: otpCode, newPassword: newPassword)
            forgotStep = 1
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func verifyMFA() async {
        guard let challengeId = mfaChallengeId else {
            error = "Missing MFA challenge. Please sign in again."
            return
        }
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let r = try await authClient.verifyMFA(challengeId: challengeId, code: mfaCode)
            appState.handleAuthSuccess(r)
        } catch { self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    func handleSSOTap(provider: SSOProvider) async {
        switch provider {
        case .apple:  await signInWithApple()
        case .google: await signInWithGoogle()
        case .x:      await signInWithX()
        }
    }

    func signInWithApple() async {
        await runOAuth(provider: "apple", service: appleService)
    }

    func signInWithGoogle() async {
        guard let service = googleService else {
            error = "Google Sign-In not configured"
            return
        }
        await runOAuth(provider: "google", service: service)
    }

    func signInWithX() async {
        guard let service = xService else {
            error = "X Sign-In not configured"
            return
        }
        await runOAuth(provider: "x", service: service)
    }

    private func runOAuth(provider: String, service: any SignInServiceProtocol) async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let credential = try await service.signIn(presentationAnchor: Self.currentPresentationAnchor())
            let response = try await authClient.exchangeOAuth(provider: provider, idToken: credential.idToken)
            appState.handleAuthSuccess(response)
        } catch is SignInCancelled {
            // Silent — user cancelled the system sheet, no banner.
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func currentPresentationAnchor() -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? ASPresentationAnchor()
    }
}
