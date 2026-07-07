// LuminaVaultClient/LuminaVaultClient/API/Auth/AuthEndpoints.swift
import Foundation

enum AuthEndpoints {
    struct Login: Endpoint {
        typealias Response = AuthResponse
        let email: String
        let password: String
        let mfaCode: String?
        var path: String { "/v1/auth/login" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? {
            LoginRequest(email: email, password: password, mfaCode: mfaCode)
        }
    }
    struct Register: Endpoint {
        typealias Response = AuthResponse
        let email: String
        let username: String
        let password: String
        var path: String { "/v1/auth/register" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? {
            RegisterRequest(email: email, username: username, password: password)
        }
    }
    struct ForgotPassword: Endpoint {
        typealias Response = EmptyResponse
        let email: String
        var path: String { "/v1/auth/forgot-password" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { ForgotPasswordRequest(email: email) }
    }
    struct ResetPassword: Endpoint {
        typealias Response = EmptyResponse
        let email: String
        let code: String
        let newPassword: String
        var path: String { "/v1/auth/reset-password" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? {
            ResetPasswordRequest(email: email, code: code, newPassword: newPassword)
        }
    }
    struct VerifyMFA: Endpoint {
        typealias Response = AuthResponse
        let challengeId: UUID
        let code: String
        var path: String { "/v1/auth/mfa/verify" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? {
            MFAVerifyRequest(challengeId: challengeId, code: code)
        }
    }
    struct OAuthExchange: Endpoint {
        typealias Response = AuthResponse
        let provider: String
        let idToken: String
        var path: String { "/v1/auth/oauth/\(provider)/exchange" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { OAuthExchangeRequest(idToken: idToken) }
    }
    /// HER-144: X (Twitter) sign-in returns an OAuth 2.0 access_token (no
    /// id_token), so the server's `/v1/auth/oauth/x/exchange` route decodes a
    /// distinct `{ accessToken }` body via `OAuthAccessTokenRequest` from
    /// `LuminaVaultShared` (matches the `openapi.yaml` schema).
    struct OAuthAccessTokenExchange: Endpoint {
        typealias Response = AuthResponse
        let provider: String
        let accessToken: String
        var path: String { "/v1/auth/oauth/\(provider)/exchange" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { OAuthAccessTokenRequest(accessToken: accessToken) }
    }
    struct RefreshToken: Endpoint {
        typealias Response = AuthResponse
        let token: String
        var path: String { "/v1/auth/refresh" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { RefreshRequest(refreshToken: token) }
    }
    struct PhoneStart: Endpoint {
        typealias Response = PhoneStartResponse
        let phone: String
        var path: String { "/v1/auth/phone/start" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { PhoneStartRequest(phone: phone) }
    }
    struct PhoneVerify: Endpoint {
        typealias Response = AuthResponse
        let phone: String
        let code: String
        var path: String { "/v1/auth/phone/verify" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { PhoneVerifyRequest(phone: phone, code: code) }
    }
    struct EmailMagicStart: Endpoint {
        typealias Response = EmailMagicStartResponse
        let email: String
        var path: String { "/v1/auth/email/start" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { EmailMagicStartRequest(email: email) }
    }
    struct EmailMagicVerify: Endpoint {
        typealias Response = AuthResponse
        let email: String
        let code: String
        var path: String { "/v1/auth/email/verify" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? {
            EmailMagicVerifyRequest(email: email, code: code)
        }
    }
    struct GetMe: Endpoint {
        typealias Response = MeResponse
        var path: String { "/v1/auth/me" }
        var method: HTTPMethod { .get }
    }
    struct UpdatePrivacy: Endpoint {
        typealias Response = MeResponse
        let request: UpdatePrivacyRequest
        var path: String { "/v1/auth/me/privacy" }
        var method: HTTPMethod { .put }
        var body: (any Encodable)? { request }
    }
    struct Logout: Endpoint {
        typealias Response = EmptyResponse
        let refreshToken: String
        var path: String { "/v1/auth/logout" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { RefreshRequest(refreshToken: refreshToken) }
    }

    // MARK: - HER-216 WebAuthn / passkey

    struct WebAuthnRegisterBegin: Endpoint {
        typealias Response = WebAuthnBeginRegistrationResponse
        let username: String
        let displayName: String?
        var path: String { "/v1/auth/webauthn/register/begin" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? {
            WebAuthnBeginRegistrationRequest(username: username, displayName: displayName)
        }
    }

    struct WebAuthnRegisterFinish: Endpoint {
        typealias Response = WebAuthnFinishRegistrationResponse
        let request: WebAuthnFinishRegistrationRequest
        var path: String { "/v1/auth/webauthn/register/finish" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { request }
    }

    struct WebAuthnAuthenticateBegin: Endpoint {
        typealias Response = WebAuthnBeginAuthenticationResponse
        let username: String
        var path: String { "/v1/auth/webauthn/authenticate/begin" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { WebAuthnBeginAuthenticationRequest(username: username) }
    }

    struct WebAuthnAuthenticateFinish: Endpoint {
        typealias Response = AuthResponse
        let request: WebAuthnFinishAuthenticationRequest
        var path: String { "/v1/auth/webauthn/authenticate/finish" }
        var method: HTTPMethod { .post }
        var requiresAuth: Bool { false }
        var body: (any Encodable)? { request }
    }

    struct WebAuthnListCredentials: Endpoint {
        typealias Response = WebAuthnCredentialListResponse
        var path: String { "/v1/auth/webauthn/credentials" }
        var method: HTTPMethod { .get }
    }

    struct WebAuthnDeleteCredential: Endpoint {
        typealias Response = EmptyResponse
        let credentialID: String
        var path: String {
            let encoded = credentialID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentialID
            return "/v1/auth/webauthn/credentials/\(encoded)"
        }
        var method: HTTPMethod { .delete }
    }
}
