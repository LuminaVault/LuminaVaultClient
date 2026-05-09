// LuminaVaultClient/LuminaVaultClientTests/KeychainServiceTests.swift
import XCTest
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
}
