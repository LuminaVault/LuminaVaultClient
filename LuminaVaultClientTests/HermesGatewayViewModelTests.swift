// LuminaVaultClient/LuminaVaultClientTests/HermesGatewayViewModelTests.swift
//
// HER-218 — state-machine tests for `HermesGatewayViewModel`.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class HermesGatewayViewModelTests: XCTestCase {
    var mockClient: MockSettingsClient!
    var sut: HermesGatewayViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockSettingsClient()
        sut = HermesGatewayViewModel(client: mockClient)
    }

    // MARK: - load()

    func testLoadEmptyStateOn404() async {
        mockClient.getResult = .success(nil)
        await sut.load()
        XCTAssertEqual(sut.state, .empty)
        XCTAssertEqual(mockClient.calls, [.get])
    }

    func testLoadConfiguredVerified() async {
        mockClient.getResult = .success(.stubVerified)
        await sut.load()
        guard case let .configured(baseUrl, hasAuthHeader, status) = sut.state else {
            return XCTFail("expected configured state, got \(sut.state)")
        }
        XCTAssertEqual(baseUrl, "https://hermes.example.com")
        XCTAssertTrue(hasAuthHeader)
        XCTAssertEqual(status, .verified(at: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    func testLoadConfiguredUnverified() async {
        mockClient.getResult = .success(.stubUnverified)
        await sut.load()
        guard case let .configured(_, _, status) = sut.state else {
            return XCTFail("expected configured state")
        }
        XCTAssertEqual(status, .unverified)
    }

    // MARK: - useMyOwnGateway / editExistingConfig

    func testUseMyOwnGatewayOpensFormWithEmptyFields() {
        sut.state = .empty
        sut.baseUrlInput = "leftover"
        sut.authHeaderInput = "leftover-token"
        sut.useMyOwnGateway()
        if case let .editing(prefilledBaseUrl, prefilledHasAuthHeader) = sut.state {
            XCTAssertNil(prefilledBaseUrl)
            XCTAssertFalse(prefilledHasAuthHeader)
        } else {
            XCTFail("expected editing state")
        }
        XCTAssertEqual(sut.baseUrlInput, "")
        XCTAssertEqual(sut.authHeaderInput, "")
    }

    func testEditExistingConfigPrefillsURLOnly() {
        sut.state = .configured(
            baseUrl: "https://hermes.example.com",
            hasAuthHeader: true,
            status: .verified(at: Date(timeIntervalSince1970: 1_700_000_000)),
        )
        sut.editExistingConfig()
        if case let .editing(prefilledBaseUrl, prefilledHasAuthHeader) = sut.state {
            XCTAssertEqual(prefilledBaseUrl, "https://hermes.example.com")
            XCTAssertTrue(prefilledHasAuthHeader)
        } else {
            XCTFail("expected editing state")
        }
        // URL prefilled, header field stays empty (server never returns plaintext).
        XCTAssertEqual(sut.baseUrlInput, "https://hermes.example.com")
        XCTAssertEqual(sut.authHeaderInput, "")
    }

    // MARK: - submit()

    func testSubmitRejectsNonHTTPSURL() async {
        sut.baseUrlInput = "http://hermes.example.com"
        await sut.submit()
        XCTAssertEqual(sut.lastError, "Base URL must start with https://")
        XCTAssertTrue(mockClient.calls.isEmpty)
    }

    func testSubmitRejectsMalformedURL() async {
        sut.baseUrlInput = "not a url"
        await sut.submit()
        XCTAssertEqual(sut.lastError, "Base URL must start with https://")
        XCTAssertTrue(mockClient.calls.isEmpty)
    }

    func testSubmitSuccessCallsPUTThenTestAndMovesToVerified() async {
        mockClient.putResult = .success(.stubUnverified)
        mockClient.testResult = .success(.init(verifiedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        sut.baseUrlInput = "https://hermes.example.com"
        sut.authMode = .bearer
        sut.authHeaderInput = "Bearer abc"

        await sut.submit()

        XCTAssertEqual(mockClient.calls.count, 2)
        XCTAssertEqual(mockClient.calls[0], .put(baseUrl: "https://hermes.example.com", authHeader: "Bearer abc"))
        XCTAssertEqual(mockClient.calls[1], .test)
        if case let .configured(_, _, status) = sut.state {
            XCTAssertEqual(status, .verified(at: Date(timeIntervalSince1970: 1_800_000_000)))
        } else {
            XCTFail("expected configured state")
        }
        XCTAssertNil(sut.verifyError)
        XCTAssertNil(sut.lastError)
    }

    func testSubmitVerifyFailureKeepsConfigButSetsBanner() async {
        mockClient.putResult = .success(.stubUnverified)
        mockClient.testResult = .failure(APIError.httpError(statusCode: 502, data: Data()))
        sut.baseUrlInput = "https://hermes.example.com"
        sut.authMode = .bearer
        sut.authHeaderInput = "Bearer abc"

        await sut.submit()

        XCTAssertEqual(sut.verifyError, .http5xx)
        if case let .configured(_, _, status) = sut.state {
            XCTAssertEqual(status, .unverified)
        } else {
            XCTFail("expected configured state")
        }
        // Form fields retained for retry without re-paste.
        XCTAssertEqual(sut.baseUrlInput, "https://hermes.example.com")
        XCTAssertEqual(sut.authHeaderInput, "Bearer abc")
    }

    func testSubmitTrimsBlankAuthHeaderToNil() async {
        mockClient.putResult = .success(.stubUnverified)
        sut.baseUrlInput = "https://hermes.example.com"
        sut.authMode = .bearer
        sut.authHeaderInput = "   "
        await sut.submit()
        XCTAssertEqual(mockClient.calls.first, .put(baseUrl: "https://hermes.example.com", authHeader: nil))
    }

    func testSubmitNoneAuthModeSendsNilHeader() async {
        mockClient.putResult = .success(.stubUnverified)
        sut.baseUrlInput = "https://hermes.example.com"
        sut.authMode = .none
        // Leftover bearer text is ignored when the picker is on None.
        sut.authHeaderInput = "Bearer ignored"
        await sut.submit()
        XCTAssertEqual(mockClient.calls.first, .put(baseUrl: "https://hermes.example.com", authHeader: nil))
    }

    func testSubmitBearerWithoutPrefixGetsBearerPrepended() async {
        mockClient.putResult = .success(.stubUnverified)
        sut.baseUrlInput = "https://hermes.example.com"
        sut.authMode = .bearer
        sut.authHeaderInput = "abc123"
        await sut.submit()
        XCTAssertEqual(mockClient.calls.first, .put(baseUrl: "https://hermes.example.com", authHeader: "Bearer abc123"))
    }

    func testSubmitBasicBuildsBase64AuthorizationHeader() async {
        mockClient.putResult = .success(.stubUnverified)
        sut.baseUrlInput = "https://hermes.example.com"
        sut.authMode = .basic
        sut.basicUsernameInput = "alice"
        sut.basicPasswordInput = "s3cr3t"
        await sut.submit()
        // base64("alice:s3cr3t") == "YWxpY2U6czNjcjN0"
        XCTAssertEqual(
            mockClient.calls.first,
            .put(baseUrl: "https://hermes.example.com", authHeader: "Basic YWxpY2U6czNjcjN0"),
        )
    }

    // MARK: - testAgain()

    func testTestAgainSuccessFlipsToVerified() async {
        sut.state = .configured(baseUrl: "https://hermes.example.com", hasAuthHeader: true, status: .unverified)
        mockClient.testResult = .success(.init(verifiedAt: Date(timeIntervalSince1970: 1_900_000_000)))
        await sut.testAgain()
        if case let .configured(_, _, status) = sut.state {
            XCTAssertEqual(status, .verified(at: Date(timeIntervalSince1970: 1_900_000_000)))
        } else {
            XCTFail("expected configured state")
        }
    }

    func testTestAgainFailureClassifiesError() async {
        sut.state = .configured(baseUrl: "https://hermes.example.com", hasAuthHeader: true, status: .verified(at: .now))
        mockClient.testResult = .failure(APIError.networkFailure(URLError(.timedOut)))
        await sut.testAgain()
        XCTAssertEqual(sut.verifyError, .timeout)
    }

    func testTestAgainNoopWhenNotConfigured() async {
        sut.state = .empty
        await sut.testAgain()
        XCTAssertTrue(mockClient.calls.isEmpty)
    }

    // MARK: - disconnect()

    func testDisconnectSuccessGoesToEmpty() async {
        sut.state = .configured(baseUrl: "https://hermes.example.com", hasAuthHeader: true, status: .verified(at: .now))
        await sut.disconnect()
        XCTAssertEqual(sut.state, .empty)
        XCTAssertEqual(mockClient.calls, [.delete])
    }

    func testDisconnectFailureSurfacesError() async {
        sut.state = .configured(baseUrl: "https://hermes.example.com", hasAuthHeader: true, status: .verified(at: .now))
        mockClient.deleteError = APIError.httpError(statusCode: 500, data: Data())
        await sut.disconnect()
        XCTAssertNotNil(sut.lastError)
        // State unchanged so the user can retry.
        if case .empty = sut.state { XCTFail("expected state unchanged on failure") }
    }
}
