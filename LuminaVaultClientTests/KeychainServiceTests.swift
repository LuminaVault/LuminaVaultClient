// LuminaVaultClient/LuminaVaultClientTests/KeychainServiceTests.swift
import XCTest
import Foundation
@testable import LuminaVaultClient

final class KeychainServiceTests: XCTestCase {
    var sut: KeychainService!

    override func setUp() {
        super.setUp()
        sut = KeychainService(service: "com.luminavault.test")
        sut.clearAll()
    }
    override func tearDown() { sut.clearAll(); super.tearDown() }

    func testSaveAndReadAccessToken() {
        sut.accessToken = "tok123"
        XCTAssertEqual(sut.accessToken, "tok123")
    }
    func testDeleteAccessToken() {
        sut.accessToken = "tok123"
        sut.accessToken = nil
        XCTAssertNil(sut.accessToken)
    }
    func testClearAllWipesTokens() {
        sut.accessToken = "a"; sut.refreshToken = "b"
        sut.clearAll()
        XCTAssertNil(sut.accessToken)
        XCTAssertNil(sut.refreshToken)
    }
    func testBiometricsEnabledDefaultsFalse() {
        XCTAssertFalse(sut.biometricsEnabled)
    }
    func testBiometricsEnabledPersists() {
        sut.biometricsEnabled = true
        XCTAssertTrue(sut.biometricsEnabled)
    }

    // HER-209: Apple-specific Keychain entries — userID for credential-state
    // polling, fullName for display-name retention across sign-ins.
    func testAppleUserIdRoundTrip() {
        XCTAssertNil(sut.appleUserId)
        sut.appleUserId = "001234.abcdef.5678"
        XCTAssertEqual(sut.appleUserId, "001234.abcdef.5678")
        sut.appleUserId = nil
        XCTAssertNil(sut.appleUserId)
    }
    func testAppleFullNameRoundTrip() {
        XCTAssertNil(sut.appleFullName)
        var components = PersonNameComponents()
        components.givenName = "Ada"
        components.familyName = "Lovelace"
        components.middleName = "Augusta"
        sut.appleFullName = components

        let read = sut.appleFullName
        XCTAssertEqual(read?.givenName, "Ada")
        XCTAssertEqual(read?.familyName, "Lovelace")
        XCTAssertEqual(read?.middleName, "Augusta")

        sut.appleFullName = nil
        XCTAssertNil(sut.appleFullName)
    }
    func testClearAllRemovesAppleEntries() {
        sut.appleUserId = "001234.abcdef.5678"
        var components = PersonNameComponents()
        components.givenName = "Ada"
        sut.appleFullName = components

        sut.clearAll()

        XCTAssertNil(sut.appleUserId)
        XCTAssertNil(sut.appleFullName)
    }
}
