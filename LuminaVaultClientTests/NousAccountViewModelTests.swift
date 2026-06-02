// LuminaVaultClient/LuminaVaultClientTests/NousAccountViewModelTests.swift
//
// Nous Subscription Integration — state-machine tests for
// `NousAccountViewModel` (OAuth device-code connect/disconnect).

import XCTest
@testable import LuminaVaultClient

@MainActor
final class NousAccountViewModelTests: XCTestCase {
    var mockClient: MockIntegrationsClient!
    var sut: NousAccountViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockIntegrationsClient()
        sut = NousAccountViewModel(client: mockClient)
    }

    // MARK: - load()

    func testLoadReadyWhenServerReturnsStatus() async {
        mockClient.nousStatusResult = .success(.stubDisconnected)
        await sut.load()
        if case let .ready(status) = sut.state {
            XCTAssertFalse(status.connected)
        } else {
            XCTFail("expected ready state, got \(sut.state)")
        }
        XCTAssertEqual(mockClient.calls, [.nousStatus])
    }

    func testLoadFailsCleanlyOnError() async {
        mockClient.nousStatusResult = .failure(APIError.httpError(statusCode: 503, data: Data()))
        await sut.load()
        if case let .failed(message) = sut.state {
            XCTAssertTrue(message.contains("503"))
        } else {
            XCTFail("expected failed state")
        }
    }

    // MARK: - device-code connect flow

    func testStartConnectMovesToAwaitingApproval() async {
        mockClient.nousStartResult = .success(.stub)
        await sut.startConnect()
        if case let .awaitingApproval(start) = sut.connectPhase {
            XCTAssertEqual(start.userCode, "STUB-CODE")
        } else {
            XCTFail("expected awaitingApproval, got \(sut.connectPhase)")
        }
        XCTAssertEqual(mockClient.calls, [.nousStart])
    }

    func testCompleteConnectMarksConnectedAndResetsPhase() async {
        mockClient.nousStartResult = .success(.stub)
        mockClient.nousCompleteResult = .success(.stubConnected)
        await sut.startConnect()
        await sut.completeConnect()
        XCTAssertTrue(sut.nousStatus?.connected ?? false)
        if case .idle = sut.connectPhase {} else {
            XCTFail("expected idle phase after successful connect, got \(sut.connectPhase)")
        }
        XCTAssertEqual(sut.nousStatus?.plan, "Hermes Pro")
        XCTAssertEqual(mockClient.calls, [.nousStart, .nousComplete(sessionID: "nous-session-stub")])
    }

    func testCompleteConnectFailureKeepsApprovalPhaseForRetry() async {
        mockClient.nousStartResult = .success(.stub)
        mockClient.nousCompleteResult = .failure(APIError.httpError(statusCode: 502, data: Data()))
        await sut.startConnect()
        await sut.completeConnect()
        if case .awaitingApproval = sut.connectPhase {
            // expected — user can retry approval
        } else {
            XCTFail("expected to stay in awaitingApproval, got \(sut.connectPhase)")
        }
        XCTAssertNotNil(sut.actionError)
    }

    // MARK: - disconnect()

    func testDisconnectRevertsToManaged() async {
        mockClient.nousDisconnectResult = .success(.stubDisconnected)
        sut.state = .ready(.stubConnected)
        await sut.disconnect()
        XCTAssertFalse(sut.nousStatus?.connected ?? true)
        XCTAssertFalse(sut.isWorking)
        XCTAssertNil(sut.actionError)
        XCTAssertEqual(mockClient.calls, [.nousDisconnect])
    }

    func testDisconnectFailureSurfacesErrorWithoutMutatingState() async {
        mockClient.nousDisconnectResult = .failure(APIError.httpError(statusCode: 502, data: Data()))
        sut.state = .ready(.stubConnected)
        await sut.disconnect()
        XCTAssertTrue(sut.nousStatus?.connected ?? false, "state untouched on failure")
        XCTAssertNotNil(sut.actionError)
    }
}
