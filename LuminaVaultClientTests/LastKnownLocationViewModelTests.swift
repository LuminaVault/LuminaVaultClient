// LuminaVaultClient/LuminaVaultClientTests/LastKnownLocationViewModelTests.swift
//
// Muse Stage C — the Data Access row for the location fix the server keeps
// for offline scheduled jobs: what it shows, and "Forget location".
//
// Async on purpose: synchronous @MainActor XCTest methods crash this host.

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class LastKnownLocationViewModelTests: XCTestCase {
    private static let capturedAt = Date(timeIntervalSince1970: 1_790_146_800)
    private static let lisbon = LastKnownLocationResponse(
        cached: true, place: "Lisbon", latitude: 38.7223, longitude: -9.1393, capturedAt: capturedAt
    )

    func testCachedPlaceIsShownByName() async {
        let vm = LastKnownLocationViewModel(client: StubLocationClient(response: Self.lisbon))

        await vm.load()

        XCTAssertEqual(vm.location, Self.lisbon)
        XCTAssertEqual(vm.placeText, "Lisbon")
        XCTAssertEqual(vm.location?.capturedAt, Self.capturedAt)
    }

    func testUnnamedPlaceFallsBackToCoordinates() async {
        let unnamed = LastKnownLocationResponse(cached: true, latitude: 38.7223, longitude: -9.1393, capturedAt: Self.capturedAt)
        let vm = LastKnownLocationViewModel(client: StubLocationClient(response: unnamed))

        await vm.load()

        XCTAssertEqual(vm.placeText, "38.72, -9.14")
    }

    func testNothingCachedHasNoLocation() async {
        let vm = LastKnownLocationViewModel(client: StubLocationClient(response: LastKnownLocationResponse(cached: false)))

        await vm.load()

        XCTAssertEqual(vm.state, .ready(LastKnownLocationResponse(cached: false)))
        XCTAssertNil(vm.location)
        XCTAssertNil(vm.placeText)
    }

    func testForgetDeletesAndClears() async {
        let client = StubLocationClient(response: Self.lisbon)
        let vm = LastKnownLocationViewModel(client: client)
        await vm.load()

        await vm.forget()

        let forgets = await client.forgetCalls
        XCTAssertEqual(forgets, 1)
        XCTAssertNil(vm.location)
        XCTAssertNil(vm.lastError)
        XCTAssertFalse(vm.isWorking)
    }

    func testForgetFailureKeepsTheLocation() async {
        let client = StubLocationClient(response: Self.lisbon, forgetError: APIError.unauthorized)
        let vm = LastKnownLocationViewModel(client: client)
        await vm.load()

        await vm.forget()

        XCTAssertEqual(vm.location, Self.lisbon)
        XCTAssertEqual(vm.lastError, "Couldn't forget your location. Try again.")
    }

    func testLoadFailure() async {
        let vm = LastKnownLocationViewModel(client: StubLocationClient(response: Self.lisbon, getError: APIError.unauthorized))

        await vm.load()

        XCTAssertEqual(vm.state, .failed("Couldn't load your saved location."))
        XCTAssertNil(vm.location)
    }
}

private actor StubLocationClient: LastKnownLocationClientProtocol {
    private let response: LastKnownLocationResponse
    private let getError: Error?
    private let forgetError: Error?
    private(set) var forgetCalls = 0

    init(response: LastKnownLocationResponse, getError: Error? = nil, forgetError: Error? = nil) {
        self.response = response
        self.getError = getError
        self.forgetError = forgetError
    }

    func get() async throws -> LastKnownLocationResponse {
        if let getError { throw getError }
        return response
    }

    func forget() async throws {
        forgetCalls += 1
        if let forgetError { throw forgetError }
    }
}
