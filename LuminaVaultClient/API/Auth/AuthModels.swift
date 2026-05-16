// LuminaVaultClient/LuminaVaultClient/API/Auth/AuthModels.swift
// DTO shapes mirror LuminaVaultShared/APIDTOs.swift exactly so a future
// `import LuminaVaultShared` (HER-213) is a literal find/replace.
import Foundation

struct LoginRequest: Encodable {
    let email: String
    let password: String
    let mfaCode: String?
}

struct RegisterRequest: Encodable {
    let email: String
    let username: String
    let password: String
}

struct ForgotPasswordRequest: Encodable {
    let email: String
}

struct ResetPasswordRequest: Encodable {
    let email: String
    let code: String
    let newPassword: String
}

struct MFAVerifyRequest: Encodable {
    let challengeId: UUID
    let code: String
}

struct OAuthExchangeRequest: Encodable {
    let idToken: String
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

struct AuthResponse: Decodable {
    let userId: UUID
    let email: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let mfaRequired: Bool?
    let mfaChallengeId: UUID?
}

struct PhoneStartRequest: Encodable {
    let phone: String
}

struct PhoneStartResponse: Decodable {
    let challengeId: UUID
    let expiresAt: Date
}

struct PhoneVerifyRequest: Encodable {
    let phone: String
    let code: String
}

struct EmptyResponse: Decodable {}
