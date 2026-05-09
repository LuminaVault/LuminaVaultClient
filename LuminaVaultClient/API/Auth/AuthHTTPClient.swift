// LuminaVaultClient/LuminaVaultClient/API/Auth/AuthHTTPClient.swift
final class AuthHTTPClient: AuthClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.Login(email: email, password: password))
    }
    func register(name: String, email: String, password: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.Register(name: name, email: email, password: password))
    }
    func forgotPassword(email: String) async throws {
        _ = try await client.execute(AuthEndpoints.ForgotPassword(email: email))
    }
    func verifyOTP(email: String, code: String) async throws {
        _ = try await client.execute(AuthEndpoints.VerifyOTP(email: email, code: code))
    }
    func resetPassword(token: String, newPassword: String) async throws {
        _ = try await client.execute(AuthEndpoints.ResetPassword(token: token, newPassword: newPassword))
    }
    func verifyMFA(code: String, mfaMethod: MFAMethod) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.VerifyMFA(code: code, mfaMethod: mfaMethod))
    }
    func ssoLogin(provider: String, identityToken: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.SSOLogin(provider: provider, identityToken: identityToken))
    }
    func refreshToken(_ token: String) async throws -> AuthResponse {
        try await client.execute(AuthEndpoints.RefreshToken(token: token))
    }
}
