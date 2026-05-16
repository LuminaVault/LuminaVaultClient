// LuminaVaultClient/LuminaVaultClient/Utilities/PreviewAuthClient.swift
import Foundation

final class PreviewAuthClient: AuthClientProtocol {
    private func stub() -> AuthResponse {
        AuthResponse(
            userId: UUID(),
            email: "preview@example.com",
            accessToken: "",
            refreshToken: "",
            expiresIn: 3600,
            mfaRequired: nil,
            mfaChallengeId: nil
        )
    }

    func login(email: String, password: String, mfaCode: String?) async throws -> AuthResponse { stub() }
    func register(email: String, username: String, password: String) async throws -> AuthResponse { stub() }
    func forgotPassword(email: String) async throws {}
    func resetPassword(email: String, code: String, newPassword: String) async throws {}
    func verifyMFA(challengeId: UUID, code: String) async throws -> AuthResponse { stub() }
    func exchangeOAuth(provider: String, idToken: String) async throws -> AuthResponse { stub() }
    func refreshToken(_ token: String) async throws -> AuthResponse { stub() }
    func phoneStart(phone: String) async throws -> PhoneStartResponse {
        PhoneStartResponse(challengeId: UUID(), expiresAt: Date().addingTimeInterval(300))
    }
    func phoneVerify(phone: String, code: String) async throws -> AuthResponse { stub() }
    func emailMagicStart(email: String) async throws -> EmailMagicStartResponse {
        EmailMagicStartResponse(challengeId: UUID(), expiresAt: Date(timeIntervalSinceNow: 600))
    }
    func emailMagicVerify(email: String, code: String) async throws -> AuthResponse { stub() }
}
