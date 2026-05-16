// LuminaVaultClient/LuminaVaultClient/Services/SignInServiceProtocol.swift
import Foundation
import AuthenticationServices

/// Returned by every native SSO provider service. The server-side
/// `/v1/auth/oauth/<provider>/exchange` route only consumes `idToken`;
/// `rawNonce` is currently informational (server validates the nonce hash
/// embedded in the Apple JWT itself).
struct ProviderCredential: Sendable {
    let idToken: String
    let rawNonce: String?
}

@MainActor
protocol SignInServiceProtocol {
    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> ProviderCredential
}

/// User cancellation should be silent in the UI — neither an error banner
/// nor an analytics event. Provider services throw this; the view model
/// catches and swallows it.
struct SignInCancelled: Error {}
