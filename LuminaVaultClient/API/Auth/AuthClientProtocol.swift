// LuminaVaultClient/LuminaVaultClient/API/Auth/AuthClientProtocol.swift
import Foundation

protocol AuthClientProtocol {
    func login(email: String, password: String, mfaCode: String?) async throws -> AuthResponse
    func register(email: String, username: String, password: String) async throws -> AuthResponse
    func forgotPassword(email: String) async throws
    func resetPassword(email: String, code: String, newPassword: String) async throws
    func verifyMFA(challengeId: UUID, code: String) async throws -> AuthResponse
    func exchangeOAuth(provider: String, idToken: String) async throws -> AuthResponse
    func exchangeOAuthAccessToken(provider: String, accessToken: String) async throws -> AuthResponse
    func refreshToken(_ token: String) async throws -> AuthResponse
    func phoneStart(phone: String) async throws -> PhoneStartResponse
    func phoneVerify(phone: String, code: String) async throws -> AuthResponse
    func emailMagicStart(email: String) async throws -> EmailMagicStartResponse
    func emailMagicVerify(email: String, code: String) async throws -> AuthResponse
    func getMe() async throws -> MeResponse
    func logout(refreshToken: String) async throws

    // HER-216 WebAuthn / passkey
    func webAuthnRegisterBegin(username: String, displayName: String?) async throws -> WebAuthnBeginRegistrationResponse
    func webAuthnRegisterFinish(_ request: WebAuthnFinishRegistrationRequest) async throws -> WebAuthnFinishRegistrationResponse
    func webAuthnAuthenticateBegin(username: String) async throws -> WebAuthnBeginAuthenticationResponse
    func webAuthnAuthenticateFinish(_ request: WebAuthnFinishAuthenticationRequest) async throws -> AuthResponse
    func webAuthnListCredentials() async throws -> WebAuthnCredentialListResponse
    func webAuthnDeleteCredential(credentialID: String) async throws
}
