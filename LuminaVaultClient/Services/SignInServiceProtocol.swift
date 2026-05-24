// LuminaVaultClient/LuminaVaultClient/Services/SignInServiceProtocol.swift
import Foundation
import AuthenticationServices

/// Which server exchange route to use for the token in `ProviderCredential.idToken`.
/// Apple / Google issue OIDC id_tokens; X issues a plain OAuth 2.0 access_token,
/// and the server has separate routes for the two body shapes.
enum OAuthTokenKind: Sendable {
    case idToken
    case accessToken
}

/// Returned by every native SSO provider service. `idToken` carries whichever
/// token the provider issued — for `.idToken` providers (Apple, Google) it's
/// the JWT id_token; for `.accessToken` providers (X) it's the bearer
/// access_token. `tokenKind` tells the view model which exchange route to use.
///
/// `appleUserID` and `fullName` are populated only by `AppleSignInService` —
/// they back HER-209 credential-state polling and first-sign-up name capture.
struct ProviderCredential: Sendable {
    let idToken: String
    let rawNonce: String?
    let appleUserID: String?
    let fullName: PersonNameComponents?
    let tokenKind: OAuthTokenKind

    init(
        idToken: String,
        rawNonce: String? = nil,
        appleUserID: String? = nil,
        fullName: PersonNameComponents? = nil,
        tokenKind: OAuthTokenKind = .idToken
    ) {
        self.idToken = idToken
        self.rawNonce = rawNonce
        self.appleUserID = appleUserID
        self.fullName = fullName
        self.tokenKind = tokenKind
    }
}

@MainActor
protocol SignInServiceProtocol {
    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> ProviderCredential
}

/// User cancellation should be silent in the UI — neither an error banner
/// nor an analytics event. Provider services throw this; the view model
/// catches and swallows it.
struct SignInCancelled: Error {}
