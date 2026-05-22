// LuminaVaultClient/LuminaVaultClientTests/DeviceRegistrationCoordinatorTests.swift
// HER-214 — coordinator behavior: register, idempotent rotation, unregister.

import XCTest
import LuminaVaultShared
@testable import LuminaVaultClient

final class DeviceRegistrationCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuite: String!

    override func setUp() {
        super.setUp()
        defaultsSuite = "her214.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuite)
        defaults = nil
        defaultsSuite = nil
        super.tearDown()
    }

    @MainActor
    func testRegisterPostsTokenAndPersistsHex() async {
        let mock = MockDeviceClient()
        let coord = DeviceRegistrationCoordinator(client: mock, defaults: defaults)

        await coord.register(tokenHex: "abcdef0123")

        XCTAssertEqual(mock.registerCalls.count, 1)
        XCTAssertEqual(mock.registerCalls.first?.token, "abcdef0123")
        XCTAssertEqual(mock.registerCalls.first?.platform, .ios)
        XCTAssertEqual(coord.lastRegisteredTokenHex, "abcdef0123")
    }

    @MainActor
    func testRegisterSkipsWhenTokenUnchanged() async {
        let mock = MockDeviceClient()
        let coord = DeviceRegistrationCoordinator(client: mock, defaults: defaults)

        await coord.register(tokenHex: "abcdef")
        await coord.register(tokenHex: "abcdef")

        XCTAssertEqual(mock.registerCalls.count, 1)
    }

    @MainActor
    func testRegisterRePostsOnTokenRotation() async {
        let mock = MockDeviceClient()
        let coord = DeviceRegistrationCoordinator(client: mock, defaults: defaults)

        await coord.register(tokenHex: "tok-v1")
        await coord.register(tokenHex: "tok-v2")

        XCTAssertEqual(mock.registerCalls.count, 2)
        XCTAssertEqual(mock.registerCalls.last?.token, "tok-v2")
        XCTAssertEqual(coord.lastRegisteredTokenHex, "tok-v2")
    }

    @MainActor
    func testRegisterFailureDoesNotPersistHex() async {
        struct Boom: Error {}
        let mock = MockDeviceClient()
        mock.registerError = Boom()
        let coord = DeviceRegistrationCoordinator(client: mock, defaults: defaults)

        await coord.register(tokenHex: "abc")

        XCTAssertNil(coord.lastRegisteredTokenHex)
    }

    @MainActor
    func testUnregisterDeletesPersistedTokenAndClearsCache() async {
        let mock = MockDeviceClient()
        let coord = DeviceRegistrationCoordinator(client: mock, defaults: defaults)
        await coord.register(tokenHex: "deadbeef")

        await coord.unregisterCurrentToken()

        XCTAssertEqual(mock.unregisterCalls, ["deadbeef"])
        XCTAssertNil(coord.lastRegisteredTokenHex)
    }

    @MainActor
    func testUnregisterIsNoOpWhenNothingRegistered() async {
        let mock = MockDeviceClient()
        let coord = DeviceRegistrationCoordinator(client: mock, defaults: defaults)

        await coord.unregisterCurrentToken()

        XCTAssertTrue(mock.unregisterCalls.isEmpty)
    }

    @MainActor
    func testUnregisterClearsPersistenceEvenWhenServerCallFails() async {
        struct Boom: Error {}
        let mock = MockDeviceClient()
        let coord = DeviceRegistrationCoordinator(client: mock, defaults: defaults)
        await coord.register(tokenHex: "deadbeef")
        mock.unregisterError = Boom()

        await coord.unregisterCurrentToken()

        XCTAssertEqual(mock.unregisterCalls, ["deadbeef"])
        XCTAssertNil(coord.lastRegisteredTokenHex)
    }

    @MainActor
    func testRegisterIgnoresEmptyToken() async {
        let mock = MockDeviceClient()
        let coord = DeviceRegistrationCoordinator(client: mock, defaults: defaults)

        await coord.register(tokenHex: "")

        XCTAssertTrue(mock.registerCalls.isEmpty)
        XCTAssertNil(coord.lastRegisteredTokenHex)
    }
}

// MARK: - Mock

private final class MockDeviceClient: DeviceClientProtocol, @unchecked Sendable {
    var registerCalls: [DeviceRegistrationRequest] = []
    var unregisterCalls: [String] = []
    var registerError: Error?
    var unregisterError: Error?

    func register(_ body: DeviceRegistrationRequest) async throws -> DeviceRegistrationResponse {
        registerCalls.append(body)
        if let err = registerError { throw err }
        return DeviceRegistrationResponse(id: UUID(), token: body.token, platform: body.platform.rawValue)
    }

    func unregister(token: String) async throws {
        unregisterCalls.append(token)
        if let err = unregisterError { throw err }
    }
}
