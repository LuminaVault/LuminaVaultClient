// LuminaVaultClient/LuminaVaultClientTests/GrokConnectFlowViewModelTests.swift
//
// HER-240b — state-machine tests for `GrokConnectFlowViewModel`.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class GrokConnectFlowViewModelTests: XCTestCase {
    var mockClient: MockIntegrationsClient!
    var sut: GrokConnectFlowViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockIntegrationsClient()
        sut = GrokConnectFlowViewModel(client: mockClient)
    }

    // MARK: - start()

    func testStartTransitionsToAwaitingCallback() async {
        mockClient.startResult = .success(.stub)
        await sut.start()
        if case let .awaitingCallback(sessionID, url) = sut.state {
            XCTAssertEqual(sessionID, "session-stub")
            XCTAssertEqual(url.absoluteString, "https://accounts.x.ai/authorize?stub=1")
        } else {
            XCTFail("expected awaitingCallback, got \(sut.state)")
        }
    }

    func testStartFailsCleanlyOnInvalidURL() async {
        mockClient.startResult = .success(XaiStartResponse(sessionID: "s", authorizeURL: ""))
        await sut.start()
        if case .failed(let message) = sut.state {
            XCTAssertTrue(message.contains("invalid authorize URL"))
        } else {
            XCTFail("expected failed state")
        }
    }

    func testStartFailsCleanlyOnHTTPError() async {
        mockClient.startResult = .failure(APIError.httpError(statusCode: 501, data: Data()))
        await sut.start()
        if case .failed(let message) = sut.state {
            XCTAssertTrue(message.contains("hasn't enabled"))
        } else {
            XCTFail("expected failed state")
        }
    }

    // MARK: - submitCallback()

    func testSubmitCallbackPromotesToSuccess() async {
        mockClient.startResult = .success(.stub)
        mockClient.completeResult = .success(.stubConnected)
        await sut.start()
        let callback = URL(string: "http://127.0.0.1:56121/callback?code=abc&state=xyz")!
        await sut.submitCallback(callback)
        if case let .success(status) = sut.state {
            XCTAssertEqual(status.tier, "pro")
            XCTAssertTrue(status.connected)
        } else {
            XCTFail("expected success state, got \(sut.state)")
        }
        XCTAssertEqual(
            mockClient.calls.last,
            .complete(sessionID: "session-stub", callbackURL: callback.absoluteString),
        )
    }

    func testSubmitCallbackIgnoredWhenNotInAwaitingState() async {
        // Default state is .idle; submitCallback should be a no-op.
        let callback = URL(string: "http://127.0.0.1:56121/callback?code=x")!
        await sut.submitCallback(callback)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(mockClient.calls, [])
    }

    // MARK: - cancel()

    func testCancelResetsToIdle() async {
        mockClient.startResult = .success(.stub)
        await sut.start()
        sut.cancel()
        XCTAssertEqual(sut.state, .idle)
    }
}
