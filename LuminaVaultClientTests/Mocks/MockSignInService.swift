// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockSignInService.swift
import Foundation
import AuthenticationServices
@testable import LuminaVaultClient

@MainActor
final class MockSignInService: SignInServiceProtocol {
    var result: Result<ProviderCredential, Error> = .success(
        ProviderCredential(idToken: "mock-id-token", rawNonce: nil)
    )
    private(set) var signInCalls: Int = 0

    func signIn(presentationAnchor: ASPresentationAnchor) async throws -> ProviderCredential {
        signInCalls += 1
        return try result.get()
    }
}
