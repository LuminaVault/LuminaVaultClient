// LuminaVaultClient/LuminaVaultClient/API/Auth/AuthHTTPClient.swift
import Foundation

final class AuthHTTPClient: AuthClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func login(email: String, password: String, mfaCode: String?) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.Login(email: email, password: password, mfaCode: mfaCode))
    }
    func register(email: String, username: String, password: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.Register(email: email, username: username, password: password))
    }
    func forgotPassword(email: String) async throws {
        _ = try await client.execute(AuthEndpoints.ForgotPassword(email: email))
    }
    func resetPassword(email: String, code: String, newPassword: String) async throws {
        _ = try await client.execute(AuthEndpoints.ResetPassword(email: email, code: code, newPassword: newPassword))
    }
    func verifyMFA(challengeId: UUID, code: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.VerifyMFA(challengeId: challengeId, code: code))
    }
    func exchangeOAuth(provider: String, idToken: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.OAuthExchange(provider: provider, idToken: idToken))
    }
    func exchangeOAuthAccessToken(provider: String, accessToken: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.OAuthAccessTokenExchange(provider: provider, accessToken: accessToken))
    }
    func refreshToken(_ token: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.RefreshToken(token: token))
    }
    func phoneStart(phone: String) async throws -> PhoneStartResponse {
        try await client.execute(AuthEndpoints.PhoneStart(phone: phone))
    }
    func phoneVerify(phone: String, code: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.PhoneVerify(phone: phone, code: code))
    }
    func emailMagicStart(email: String) async throws -> EmailMagicStartResponse {
        try await client.execute(AuthEndpoints.EmailMagicStart(email: email))
    }
    func emailMagicVerify(email: String, code: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.EmailMagicVerify(email: email, code: code))
    }
    func getMe() async throws -> MeResponse {
        try await client.execute(AuthEndpoints.GetMe())
    }
    func logout(refreshToken: String) async throws {
        _ = try await client.execute(AuthEndpoints.Logout(refreshToken: refreshToken))
    }

    // MARK: - HER-216 WebAuthn / passkey

    func webAuthnRegisterBegin(username: String, displayName: String?) async throws -> WebAuthnBeginRegistrationResponse {
        try await client.execute(AuthEndpoints.WebAuthnRegisterBegin(username: username, displayName: displayName))
    }

    func webAuthnRegisterFinish(_ request: WebAuthnFinishRegistrationRequest) async throws -> WebAuthnFinishRegistrationResponse {
        try await client.execute(AuthEndpoints.WebAuthnRegisterFinish(request: request))
    }

    func webAuthnAuthenticateBegin(username: String) async throws -> WebAuthnBeginAuthenticationResponse {
        try await client.execute(AuthEndpoints.WebAuthnAuthenticateBegin(username: username))
    }

    func webAuthnAuthenticateFinish(_ request: WebAuthnFinishAuthenticationRequest) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.WebAuthnAuthenticateFinish(request: request))
    }

    func webAuthnListCredentials() async throws -> WebAuthnCredentialListResponse {
        try await client.execute(AuthEndpoints.WebAuthnListCredentials())
    }

    func webAuthnDeleteCredential(credentialID: String) async throws {
        _ = try await client.execute(AuthEndpoints.WebAuthnDeleteCredential(credentialID: credentialID))
    }
}
