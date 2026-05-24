// LuminaVaultClient/LuminaVaultClientTests/AuthViewModelOAuthTests.swift
import XCTest
import Foundation
@testable import LuminaVaultClient

@MainActor
final class AuthViewModelOAuthTests: XCTestCase {
    var mockClient: MockAuthClient!
    var appState: AppState!
    var appleService: MockSignInService!
    var googleService: MockSignInService!
    var xService: MockSignInService!
    var sut: AuthViewModel!

    override func setUp() {
        super.setUp()
        mockClient = MockAuthClient()
        let keychain = KeychainService(service: "com.luminavault.oauthtest")
        keychain.clearAll()
        appState = AppState(keychain: keychain)
        appleService = MockSignInService()
        googleService = MockSignInService()
        xService = MockSignInService()
        sut = AuthViewModel(
            authClient: mockClient,
            appState: appState,
            appleService: appleService,
            googleService: googleService,
            xService: xService
        )
    }

    // MARK: - Apple

    func testAppleSignInHappyPathCallsExchangeOAuth() async {
        mockClient.exchangeOAuthResult = .success(.stub)
        appleService.result = .success(ProviderCredential(idToken: "apple-id-token", rawNonce: "nonce"))
        await sut.signInWithApple()
        XCTAssertEqual(appleService.signInCalls, 1)
        XCTAssertEqual(mockClient.exchangeOAuthCalls.count, 1)
        XCTAssertEqual(mockClient.exchangeOAuthCalls.first?.provider, "apple")
        XCTAssertEqual(mockClient.exchangeOAuthCalls.first?.idToken, "apple-id-token")
        XCTAssertTrue(appState.isAuthenticated)
        XCTAssertNil(sut.error)
    }

    func testAppleSignInCancelIsSilent() async {
        appleService.result = .failure(SignInCancelled())
        await sut.signInWithApple()
        XCTAssertEqual(mockClient.exchangeOAuthCalls.count, 0)
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(sut.error)
    }

    func testAppleSignInProviderErrorSurfacesMessage() async {
        appleService.result = .failure(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "provider failed"]))
        await sut.signInWithApple()
        XCTAssertEqual(mockClient.exchangeOAuthCalls.count, 0)
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNotNil(sut.error)
    }

    // HER-209: Apple's user ID + first-time fullName must land in the Keychain
    // for credential-state polling + display-name retention.
    func testAppleSignInPersistsUserIDAndFullName() async {
        mockClient.exchangeOAuthResult = .success(.stub)
        var components = PersonNameComponents()
        components.givenName = "Ada"
        components.familyName = "Lovelace"
        appleService.result = .success(ProviderCredential(
            idToken: "apple-id-token",
            rawNonce: "nonce",
            appleUserID: "001234.abcdef.5678",
            fullName: components
        ))
        await sut.signInWithApple()
        XCTAssertEqual(appState.keychain.appleUserId, "001234.abcdef.5678")
        let stored = appState.keychain.appleFullName
        XCTAssertEqual(stored?.givenName, "Ada")
        XCTAssertEqual(stored?.familyName, "Lovelace")
    }

    // HER-209: subsequent Apple sign-ins return fullName == nil. Don't clobber
    // the value captured on first sign-up.
    func testAppleSignInDoesNotOverwriteExistingFullName() async {
        var initialComponents = PersonNameComponents()
        initialComponents.givenName = "Grace"
        initialComponents.familyName = "Hopper"
        appState.keychain.appleFullName = initialComponents
        appState.keychain.appleUserId = "001234.abcdef.5678"

        mockClient.exchangeOAuthResult = .success(.stub)
        appleService.result = .success(ProviderCredential(
            idToken: "apple-id-token",
            rawNonce: nil,
            appleUserID: "001234.abcdef.5678",
            fullName: nil
        ))
        await sut.signInWithApple()
        let stored = appState.keychain.appleFullName
        XCTAssertEqual(stored?.givenName, "Grace")
        XCTAssertEqual(stored?.familyName, "Hopper")
    }

    // Sign-out clears the persisted Apple credentials so a different Apple
    // account can sign in cleanly.
    func testSignOutClearsAppleKeychainEntries() async {
        appState.keychain.appleUserId = "001234.abcdef.5678"
        var components = PersonNameComponents()
        components.givenName = "Ada"
        appState.keychain.appleFullName = components

        await appState.signOut()

        XCTAssertNil(appState.keychain.appleUserId)
        XCTAssertNil(appState.keychain.appleFullName)
    }

    // MARK: - Google

    func testGoogleSignInHappyPathCallsExchangeOAuth() async {
        mockClient.exchangeOAuthResult = .success(.stub)
        googleService.result = .success(ProviderCredential(idToken: "google-id-token", rawNonce: nil))
        await sut.signInWithGoogle()
        XCTAssertEqual(googleService.signInCalls, 1)
        XCTAssertEqual(mockClient.exchangeOAuthCalls.first?.provider, "google")
        XCTAssertEqual(mockClient.exchangeOAuthCalls.first?.idToken, "google-id-token")
        XCTAssertTrue(appState.isAuthenticated)
        XCTAssertNil(sut.error)
    }

    func testGoogleSignInCancelIsSilent() async {
        googleService.result = .failure(SignInCancelled())
        await sut.signInWithGoogle()
        XCTAssertEqual(mockClient.exchangeOAuthCalls.count, 0)
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(sut.error)
    }

    func testGoogleSignInProviderErrorSurfacesMessage() async {
        googleService.result = .failure(NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "provider failed"]))
        await sut.signInWithGoogle()
        XCTAssertEqual(mockClient.exchangeOAuthCalls.count, 0)
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNotNil(sut.error)
    }

    // MARK: - X

    func testXSignInHappyPathCallsExchangeOAuthAccessToken() async {
        // HER-144: X uses the access-token exchange route, not the id-token one.
        mockClient.exchangeOAuthAccessTokenResult = .success(.stub)
        xService.result = .success(ProviderCredential(
            idToken: "x-access-token",
            rawNonce: nil,
            tokenKind: .accessToken
        ))
        await sut.signInWithX()
        XCTAssertEqual(xService.signInCalls, 1)
        XCTAssertEqual(mockClient.exchangeOAuthAccessTokenCalls.count, 1)
        XCTAssertEqual(mockClient.exchangeOAuthAccessTokenCalls.first?.provider, "x")
        XCTAssertEqual(mockClient.exchangeOAuthAccessTokenCalls.first?.accessToken, "x-access-token")
        XCTAssertTrue(mockClient.exchangeOAuthCalls.isEmpty, "X must not hit the id-token route")
        XCTAssertTrue(appState.isAuthenticated)
        XCTAssertNil(sut.error)
    }

    func testXSignInCancelIsSilent() async {
        xService.result = .failure(SignInCancelled())
        await sut.signInWithX()
        XCTAssertEqual(mockClient.exchangeOAuthAccessTokenCalls.count, 0)
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(sut.error)
    }

    func testXSignInProviderErrorSurfacesMessage() async {
        xService.result = .failure(XSignInError.invalidGrant("provider failed"))
        await sut.signInWithX()
        XCTAssertEqual(mockClient.exchangeOAuthAccessTokenCalls.count, 0)
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNotNil(sut.error)
    }
}
