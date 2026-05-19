// LuminaVaultClient/LuminaVaultClientTests/LinkedAccountsViewModelTests.swift
//
// HER-240b — state-machine tests for `LinkedAccountsViewModel`.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class LinkedAccountsViewModelTests: XCTestCase {
    var mockClient: MockIntegrationsClient!
    var sut: LinkedAccountsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockIntegrationsClient()
        sut = LinkedAccountsViewModel(client: mockClient)
    }

    // MARK: - load()

    func testLoadReadyWhenServerReturnsStatus() async {
        mockClient.statusResult = .success(.stubDisconnected)
        await sut.load()
        if case .ready(let status) = sut.state {
            XCTAssertFalse(status.connected)
            XCTAssertEqual(status.tier, "trial")
        } else {
            XCTFail("expected ready state, got \(sut.state)")
        }
        XCTAssertEqual(mockClient.calls, [.status])
    }

    func testLoadFailsCleanlyOnError() async {
        mockClient.statusResult = .failure(APIError.httpError(statusCode: 503, body: nil))
        await sut.load()
        if case .failed(let message) = sut.state {
            XCTAssertTrue(message.contains("503"))
        } else {
            XCTFail("expected failed state")
        }
    }

    // MARK: - applyConnectResult()

    func testApplyConnectResultFoldsStatusWithoutReFetch() {
        sut.applyConnectResult(.stubConnected)
        if case .ready(let status) = sut.state {
            XCTAssertTrue(status.connected)
            XCTAssertEqual(status.tier, "pro")
        } else {
            XCTFail("expected ready state")
        }
        XCTAssertEqual(mockClient.calls, [], "apply must be local — no network call")
    }

    // MARK: - disconnect()

    func testDisconnectSucceedsAndDemotesTier() async {
        mockClient.disconnectResult = .success(.stubDisconnected)
        sut.applyConnectResult(.stubConnected)
        await sut.disconnect()
        XCTAssertEqual(sut.xaiStatus?.tier, "trial")
        XCTAssertFalse(sut.isWorking)
        XCTAssertNil(sut.disconnectError)
        XCTAssertEqual(mockClient.calls, [.disconnect])
    }

    func testDisconnectFailureSurfacesErrorWithoutMutatingState() async {
        mockClient.disconnectResult = .failure(APIError.httpError(statusCode: 502, body: nil))
        sut.applyConnectResult(.stubConnected)
        await sut.disconnect()
        XCTAssertEqual(sut.xaiStatus?.tier, "pro", "state untouched on failure")
        XCTAssertNotNil(sut.disconnectError)
    }
}
