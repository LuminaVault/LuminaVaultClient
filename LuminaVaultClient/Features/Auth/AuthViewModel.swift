// LuminaVaultClient/LuminaVaultClient/Features/Auth/AuthViewModel.swift
import SwiftUI
import Foundation
import AuthenticationServices
import UIKit
import PhoneNumberKit

enum PhoneAuthStep {
    case entry
    case code
}

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
    // Phone OTP (HER-141)
    var phoneCountry: Country = Countries.default
    var phoneInput: String = ""
    var phoneE164: String = ""
    var phoneOtpCode: String = ""
    var phoneStep: PhoneAuthStep = .entry
    var phoneChallengeExpiresAt: Date? = nil
    var phoneResendSecondsLeft: Int = 0
    // Shared
    var isLoading = false
    var error: String? = nil
    var mfaRequired = false

    // Heavyweight metadata loader — share one instance across the VM.
    private let phoneNumberKit = PhoneNumberKit()
    // Cancellation on VM dealloc is handled by `weak self` inside the Task —
    // we deliberately don't touch this from `deinit` (MainActor isolation).
    private var phoneResendTask: Task<Void, Never>? = nil

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
            persistAppleCredentialIfNeeded(provider: provider, credential: credential)
        } catch is SignInCancelled {
            // Silent — user cancelled the system sheet, no banner.
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // HER-209: stash Apple's user ID (for credential-state polling) and the
    // fullName Apple only returns on first sign-up. Subsequent Apple sign-ins
    // surface a nil `fullName` — don't clobber what we captured the first time.
    private func persistAppleCredentialIfNeeded(provider: String, credential: ProviderCredential) {
        guard provider == "apple" else { return }
        if let userID = credential.appleUserID, !userID.isEmpty {
            appState.keychain.appleUserId = userID
        }
        if let fullName = credential.fullName,
           appState.keychain.appleFullName == nil {
            appState.keychain.appleFullName = fullName
        }
    }

    private static func currentPresentationAnchor() -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? ASPresentationAnchor()
    }

    // MARK: - Phone OTP (HER-141)

    /// Live-format raw digits using PhoneNumberKit's PartialFormatter scoped to
    /// the currently selected country.
    func formatPhoneAsTyped(_ raw: String) -> String {
        let formatter = PartialFormatter(
            phoneNumberKit: phoneNumberKit,
            defaultRegion: phoneCountry.isoCode,
            withPrefix: false
        )
        return formatter.formatPartial(raw)
    }

    /// Validate input then POST `/v1/auth/phone/start`. On success, advance
    /// the step machine to `.code` and arm the 60s resend cooldown.
    func startPhoneOTP() async {
        error = nil
        // Validate & normalise to E.164 via PhoneNumberKit so the server's
        // regex check matches whatever the user typed in local format.
        let raw = phoneInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            error = "Enter a valid phone number"
            return
        }
        let parsed: PhoneNumber
        do {
            parsed = try phoneNumberKit.parse(raw, withRegion: phoneCountry.isoCode)
        } catch {
            self.error = "Enter a valid phone number"
            return
        }
        let e164 = phoneNumberKit.format(parsed, toType: .e164)
        phoneE164 = e164

        isLoading = true; defer { isLoading = false }
        do {
            let r = try await authClient.phoneStart(phone: e164)
            phoneChallengeExpiresAt = r.expiresAt
            phoneOtpCode = ""
            phoneStep = .code
            startResendCooldown()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// POST `/v1/auth/phone/verify`. Translates the server's 410/401/429 codes
    /// into the inline copy required by HER-141 acceptance.
    func verifyPhoneOTP() async {
        guard !phoneE164.isEmpty else {
            error = "Send a code first"
            return
        }
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let r = try await authClient.phoneVerify(phone: phoneE164, code: phoneOtpCode)
            appState.handleAuthSuccess(r)
            resetPhoneState()
        } catch let apiError as APIError {
            self.error = Self.phoneError(for: apiError)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Re-issue OTP. Guarded by the cooldown so users can't spam start while a
    /// previous code is still valid; the server has a stricter IP-level limit
    /// (3/min, 10/day) that this UI cooldown front-loads.
    func resendPhoneOTP() async {
        guard phoneResendSecondsLeft == 0 else { return }
        await startPhoneOTP()
    }

    /// Maps APIError → user-facing phone OTP copy. Falls through to the
    /// generic description so unhandled codes still surface something.
    static func phoneError(for apiError: APIError) -> String {
        switch apiError {
        case .unauthorized:
            return "Invalid code. Try again."
        case .httpError(let code, _) where code == 410:
            return "Code expired — request a new one."
        case .httpError(let code, _) where code == 429:
            return "Too many attempts — try again later."
        case .httpError(let code, _) where code == 400:
            return "Enter a valid phone number"
        default:
            return apiError.errorDescription ?? "Something went wrong."
        }
    }

    private func startResendCooldown() {
        phoneResendTask?.cancel()
        phoneResendSecondsLeft = 60
        phoneResendTask = Task { @MainActor [weak self] in
            while let self, self.phoneResendSecondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.phoneResendSecondsLeft -= 1
            }
        }
    }

    private func resetPhoneState() {
        phoneResendTask?.cancel()
        phoneResendTask = nil
        phoneInput = ""
        phoneE164 = ""
        phoneOtpCode = ""
        phoneStep = .entry
        phoneChallengeExpiresAt = nil
        phoneResendSecondsLeft = 0
    }
}
