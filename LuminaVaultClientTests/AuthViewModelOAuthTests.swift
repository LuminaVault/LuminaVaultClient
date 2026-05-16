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

    func testXSignInHappyPathCallsExchangeOAuth() async {
        mockClient.exchangeOAuthResult = .success(.stub)
        xService.result = .success(ProviderCredential(idToken: "x-access-token", rawNonce: nil))
        await sut.signInWithX()
        XCTAssertEqual(xService.signInCalls, 1)
        XCTAssertEqual(mockClient.exchangeOAuthCalls.first?.provider, "x")
        XCTAssertEqual(mockClient.exchangeOAuthCalls.first?.idToken, "x-access-token")
        XCTAssertTrue(appState.isAuthenticated)
        XCTAssertNil(sut.error)
    }

    func testXSignInCancelIsSilent() async {
        xService.result = .failure(SignInCancelled())
        await sut.signInWithX()
        XCTAssertEqual(mockClient.exchangeOAuthCalls.count, 0)
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(sut.error)
    }

    func testXSignInProviderErrorSurfacesMessage() async {
        xService.result = .failure(NSError(domain: "XSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "provider failed"]))
        await sut.signInWithX()
        XCTAssertEqual(mockClient.exchangeOAuthCalls.count, 0)
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNotNil(sut.error)
    }
}
