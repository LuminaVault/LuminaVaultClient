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
    func refreshToken(_ token: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.RefreshToken(token: token))
    }
    func phoneStart(phone: String) async throws -> PhoneStartResponse {
        try await client.execute(AuthEndpoints.PhoneStart(phone: phone))
    }
    func phoneVerify(phone: String, code: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.PhoneVerify(phone: phone, code: code))
    }
}
