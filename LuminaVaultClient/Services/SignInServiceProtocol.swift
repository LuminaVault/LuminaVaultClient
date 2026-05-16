// LuminaVaultClient/LuminaVaultClient/Services/SignInServiceProtocol.swift
import Foundation
import AuthenticationServices

/// Returned by every native SSO provider service. The server-side
/// `/v1/auth/oauth/<provider>/exchange` route only consumes `idToken`;
/// `rawNonce` is informational (server validates the nonce hash embedded in
/// the Apple JWT itself in a future server ticket).
///
/// `appleUserID` and `fullName` are populated only by `AppleSignInService` —
/// they back HER-209 credential-state polling and first-sign-up name capture.
struct ProviderCredential: Sendable {
    let idToken: String
    let rawNonce: String?
    let appleUserID: String?
    let fullName: PersonNameComponents?

    init(
        idToken: String,
        rawNonce: String? = nil,
        appleUserID: String? = nil,
        fullName: PersonNameComponents? = nil
    ) {
        self.idToken = idToken
        self.rawNonce = rawNonce
        self.appleUserID = appleUserID
        self.fullName = fullName
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
